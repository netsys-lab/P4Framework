`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 02/06/2025 07:13:28 PM
// Design Name:
// Module Name: UDP_checksum
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module calculator_UDP_chksm_egress (
    input  logic        clk,                // Clock signal
    input  logic        rst,                // Active-low reset

    // AXI Stream Input
    input  logic [511:0] s_axis_tdata,
    input  logic [63:0]  s_axis_tkeep,
    input  logic         s_axis_tlast,
    output logic         s_axis_tready,
    input  logic         s_axis_tvalid,

    // Metadata Input
    input  logic [10:0]   user_metadata_in,       // (bit 0: is_scion, [10:1] offset)
    input  logic         user_metadata_in_valid,

    // Metadata Output
    output logic [16:0]  user_metadata_out,      // (bit 0: is_scion [16:1] checksum)
    output logic         user_metadata_out_valid,

    // AXI Stream Output
    output logic [511:0] m_axis_tdata,
    output logic [63:0]  m_axis_tkeep,
    output logic         m_axis_tlast,
    input  logic         m_axis_tready,
    output logic         m_axis_tvalid
);

    // Internal signals
    logic [15:0] checksum;                  // Computed checksum
    logic [31:0][15:0] words;               // 2D array to store 16-bit words
    logic [31:0][15:0] sum_stage1;          // @D array for partial addition
    logic [15:0] sum_stage2;                // Accumulated checksum
    logic [15:0] payload_offset;            //to store the remaining bytes to skip
    logic        processing;                // flag to indicate ongoing checksum calculation
    logic [24:0][511:0] fragment_buffer;    // Buffer to store fragments
    logic [5:0]   fragment_count;           // Number of fragments stored
    logic [5:0]   fragment_count_initial;   // Initial fragment count
    logic         metadata_latched;         // Flag to indicate metadata is latched
    logic [10:0]   metadata_latched_in;      // Latched user_metadata_in

    // FSM States
    typedef enum logic [3:0] {
        IDLE    = 4'b0001,
        PROCESS = 4'b0010,
        DELAY   = 4'B0100,
        DATAOUT = 4'b1000
    } checksum_FSM;

    checksum_FSM current_state, next_state;

    // State transition logic
    always_ff @(posedge clk ) begin
        if (!rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (s_axis_tvalid  && user_metadata_in_valid) begin
                    next_state = PROCESS;
                 end else begin
                    next_state = IDLE;
                end
            end
            PROCESS: begin
                if (s_axis_tlast ) begin
                    next_state = DELAY ;
                end else begin
                    next_state = PROCESS ;
                end
            end
            DELAY: begin
                next_state = DATAOUT;
            end
            DATAOUT: begin
                if (fragment_count == 0) begin
                    next_state = IDLE;
                end else begin
                    next_state = DATAOUT;
                end
            end
        endcase
    end

       // Output logic
    always_ff @(posedge clk ) begin
        if (!rst) begin
            s_axis_tready <= 1'b1;
            m_axis_tvalid <= 1'b0;
            user_metadata_out <= 17'b0;
            user_metadata_out_valid <= 1'b0;
            checksum <= 16'h0000;
            payload_offset <= 16'b0;
            processing <= 1'b0;
            words <= '{default: 16'b0};
            sum_stage1 <= '{default: 16'b0};
            sum_stage2 <= 16'b0;
            fragment_count <= 6'b0;
            fragment_count_initial <= 6'b0;
            fragment_buffer <= '{default: 512'b0};
            metadata_latched <= 1'b0;
            metadata_latched_in <= 17'b0;
        end else begin
            case (current_state)

                IDLE: begin
                    s_axis_tready <= 1'b1;
                    m_axis_tvalid <= 1'b0;
                    user_metadata_out <= 17'b0;
                    user_metadata_out_valid <= 1'b0;
                    checksum <= 16'h0000;
                    payload_offset <= 16'b0;
                    processing <= 1'b0;
                    words <= '{default: 16'b0};
                    sum_stage1 <= '{default: 16'b0};
                    sum_stage2 <= 16'b0;
                    fragment_count <= 6'b0;
                    fragment_count_initial <= 6'b0;
                    fragment_buffer <= '{default: 512'b0};
                    metadata_latched <= 1'b0;
                    metadata_latched_in <= 17'b0;

                    if (s_axis_tvalid && user_metadata_in_valid) begin
                        metadata_latched <= 1'b1;
                        metadata_latched_in <= user_metadata_in;
                        payload_offset <= user_metadata_in[10:1] / 2;
                        processing <= 1'b1;

                        fragment_buffer[0] <= s_axis_tdata;         // Stores the first fragment
                        fragment_count <= fragment_count + 1;

                        for (int i = 0; i < 32; i++) begin          // Calculate checksum for the first fragment
                            words[i] = s_axis_tdata[i * 16 +: 16];
                        end

                        for (int i = 0; i < 32; i++) begin
                            if (i < payload_offset) begin
                                sum_stage1[i] = 16'h0000;
                                if (payload_offset > 32) begin
                                    payload_offset <= payload_offset - 32;
                                end else begin
                                    payload_offset <= 16'b0;
                                end
                            end else if (s_axis_tkeep[i * 2] && s_axis_tkeep[i * 2 + 1]) begin
                                sum_stage1[i] = words[i];
                            end else if (s_axis_tkeep[i * 2] && !s_axis_tkeep[i * 2 + 1]) begin
                                sum_stage1[i] = {8'b0, words[i][7:0]};
                            end else begin
                                sum_stage1[i] = 16'h0000;
                            end
                        end

                        sum_stage2 = sum_stage1[0] + sum_stage1[1] + sum_stage1[2] + sum_stage1[3] +
                                     sum_stage1[4] + sum_stage1[5] + sum_stage1[6] + sum_stage1[7] +
                                     sum_stage1[8] + sum_stage1[9] + sum_stage1[10] + sum_stage1[11] +
                                     sum_stage1[12] + sum_stage1[13] + sum_stage1[14] + sum_stage1[15] +
                                     sum_stage1[16] + sum_stage1[17] + sum_stage1[18] + sum_stage1[19] +
                                     sum_stage1[20] + sum_stage1[21] + sum_stage1[22] + sum_stage1[23] +
                                     sum_stage1[24] + sum_stage1[25] + sum_stage1[26] + sum_stage1[27] +
                                     sum_stage1[28] + sum_stage1[29] + sum_stage1[30] + sum_stage1[31];
                         checksum <= checksum + sum_stage2;    //checksum of first fragment

                     end else begin
                        s_axis_tready <= 1'b1;
                        m_axis_tvalid <= 1'b0;
                        user_metadata_out <= 17'b0;
                        user_metadata_out_valid <= 1'b0;
                        checksum <= 16'h0000;
                        payload_offset <= 16'b0;
                        processing <= 1'b0;
                        words <= '{default: 16'b0};
                        sum_stage1 <= '{default: 16'b0};
                        sum_stage2 <= 16'b0;
                        fragment_count <= 6'b0;
                        metadata_latched <= 1'b0;
                        metadata_latched_in <= 17'b0;
                    end
                end

        PROCESS: begin
            if (s_axis_tvalid && processing) begin
                // Store the fragment
                fragment_buffer[fragment_count] <= s_axis_tdata;
                fragment_count <= fragment_count + 1;

                // Calculate checksum for the current fragment
                for (int i = 0; i < 32; i++) begin
                    words[i] = s_axis_tdata[i * 16 +: 16];
                end

                for (int i = 0; i < 32; i++) begin
                    if (i < payload_offset) begin
                        sum_stage1[i] = 16'h0000;
                        if (payload_offset > 32) begin
                            payload_offset <= payload_offset - 32;
                        end else begin
                            payload_offset <= 16'b0;
                        end
                    end else if (s_axis_tkeep[i * 2] && s_axis_tkeep[i * 2 + 1]) begin
                        sum_stage1[i] = words[i];
                    end else if (s_axis_tkeep[i * 2] && !s_axis_tkeep[i * 2 + 1]) begin
                        sum_stage1[i] = {8'b0, words[i][7:0]};
                    end else begin
                        sum_stage1[i] = 16'h0000;
                    end
                end

                sum_stage2 = sum_stage1[0] + sum_stage1[1] + sum_stage1[2] + sum_stage1[3] +
                             sum_stage1[4] + sum_stage1[5] + sum_stage1[6] + sum_stage1[7] +
                             sum_stage1[8] + sum_stage1[9] + sum_stage1[10] + sum_stage1[11] +
                             sum_stage1[12] + sum_stage1[13] + sum_stage1[14] + sum_stage1[15] +
                             sum_stage1[16] + sum_stage1[17] + sum_stage1[18] + sum_stage1[19] +
                             sum_stage1[20] + sum_stage1[21] + sum_stage1[22] + sum_stage1[23] +
                             sum_stage1[24] + sum_stage1[25] + sum_stage1[26] + sum_stage1[27] +
                             sum_stage1[28] + sum_stage1[29] + sum_stage1[30] + sum_stage1[31];
                checksum <= checksum + sum_stage2;

                // Handle the last fragment
                if (s_axis_tlast) begin
                    checksum <= ~checksum; // Finalize checksum
                    //processing <= 1'b0; // Stop processing
                end
            end
        end

       DELAY: begin
            fragment_count_initial <= fragment_count ; // Store the total number of fragments
                end

        DATAOUT: begin
                    if (m_axis_tready) begin
                        if (fragment_count > 0) begin
                            processing <= 1'b0;
                            // Output the current fragment
                            m_axis_tvalid <= 1'b1;
                            m_axis_tdata <= fragment_buffer[fragment_count_initial - fragment_count];
                            m_axis_tkeep <= 64'hFFFFFFFFFFFFFFFF;
                            m_axis_tlast <= (fragment_count == 1);


                                if (fragment_count == fragment_count_initial) begin         // Output metadata only with the first fragment
                                     user_metadata_out <= {checksum, metadata_latched_in[0]};  // bit 0: is_scion, Bbit [6:1] hopfield, [23:7] checksum
                                     user_metadata_out_valid <= 1'b1;                            // Assert metadata valid for the first fragment
                                end else begin
                                     user_metadata_out <= 17'b0;
                                     user_metadata_out_valid <= 1'b0;
                                end

                            fragment_count <= fragment_count - 1;
                        end else begin
                            m_axis_tvalid <= 1'b0;
                            user_metadata_out <= 17'b0;
                            user_metadata_out_valid <= 1'b0;
                        end
                    end
                 end
            endcase
        end
    end

endmodule
