`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 03/06/2025 09:52:01 PM
// Design Name:
// Module Name: ingress_checksum_calculator
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


module ingress_checksum_calculator #(
    parameter int Max_frag_count = 25  // Default value for Max_frag_count
) (
    input  logic        clk,                  // Clock signal
    input  logic        rst,                  // Active-low reset

    // Input
    input  logic [511:0] s_axis_tdata,
    input  logic [63:0]  s_axis_tkeep,
    input  logic         s_axis_tlast,
    output logic         s_axis_tready,
    input  logic         s_axis_tvalid,

    input  logic [16:0]   user_metadata_in,         // (bit 0: is_scion, [6:1] hop fields , [16:7] offset)
    input  logic          user_metadata_in_valid,

    //Output
    output logic [511:0] m_axis_tdata,
    output logic [63:0]  m_axis_tkeep,
    output logic         m_axis_tlast,
    input  logic         m_axis_tready,
    output logic         m_axis_tvalid,
    output logic [22:0]  user_metadata_out,        // (bit 0: is_scion, [6:1] hop fields , [22:7] checksum)
    output logic         user_metadata_out_valid
);

    // Internal signals
    logic [15:0] checksum[4];                                           // Computed checksum for each buffer
    logic [31:0][15:0] words;                                           // 2D array to store 16-bit words
    logic [31:0][15:0] sum_stage1;                                      // 2D array for partial addition
    logic [15:0] sum_stage2;                                            // Accumulated checksum
    logic [15:0] payload_offset;                                        // To store the remaining bytes to skip
    logic        processing[4];                                         // Flag to indicate ongoing checksum calculation for each buffer
    logic [Max_frag_count:0][511:0] fragment_buffer[4];                 // Quad buffer to store fragments of consecutive packets
    logic [5:0]   fragment_count[4];                                    // Number of fragments stored in each buffer
    logic [5:0]   fragment_count_initial[4];                            // Initial fragment count for each buffer
    logic         metadata_latched[4];                                  // Flag to indicate metadata is latched for each buffer
    logic [16:0]  metadata_latched_in[4];                               // Latched user_metadata_in for each buffer
    logic [1:0]   buffer_select;                                        // Signal to select current buffer to process incoming data
    logic         ready_to_transmit[4];                                 // Flag to indicate checksum calculation is done and the buffer is ready to transmit
    logic         transmit_active;                                      // Flag to indicate data transmission is active
    logic [1:0]   transmit_queue[4];                                    // Queue to store buffer indices of ready to transmit data
    logic [1:0]   transmit_queue_head;                                  // points to the buffer that currently being transmitted
    logic [1:0]   transmit_queue_tail;                                  // points to the next buffer in transmit queue

    logic [1:0]   current_buffer_index;                                 // Index of the buffer currently being transmitted
    logic [5:0]   current_fragment_count;                               // Current fragment count for the buffer being transmitted
    logic [5:0]   current_fragment_count_initial;                       // Initial fragment count for the buffer being transmitted


    // FSM States
    typedef enum logic [2:0] {
        IDLE    = 3'b001,
        PROCESS = 3'b010,
        DATAOUT = 3'b100
    } checksum_FSM;

    checksum_FSM current_state[4], next_state[4];   //4 different FSMs to manage 4 different packets

    // State transition logic for each buffer
    always_ff @(posedge clk ) begin
        if (!rst) begin
            for (int i = 0; i < 4; i++) begin
                current_state[i] <= IDLE;
            end
        end else begin
            for (int i = 0; i < 4; i++) begin
                current_state[i] <= next_state[i];
            end
        end
    end

    // Next state logic for each buffer
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            next_state[i] = current_state[i];
            case (current_state[i])
                IDLE: begin
                    if (s_axis_tvalid && user_metadata_in_valid && buffer_select == i) begin
                        next_state[i] = PROCESS;
                    end else begin
                        next_state[i] = IDLE;
                    end
                end
                PROCESS: begin
                    if (s_axis_tlast && buffer_select == i) begin
                        next_state[i] = DATAOUT;
                    end else begin
                        next_state[i] = PROCESS;
                    end
                end
                DATAOUT: begin
                    if (fragment_count[i] == 0) begin
                        next_state[i] = IDLE;
                    end else begin
                        next_state[i] = DATAOUT;
                    end
                end
            endcase
        end
    end

    // Output logic for each buffer
    always_ff @(posedge clk ) begin
        if (!rst) begin
            s_axis_tready <= 1'b1;
            m_axis_tvalid <= 1'b0;
            user_metadata_out <= 23'b0;
            user_metadata_out_valid <= 1'b0;
            checksum <= '{default: 16'h0000};
            payload_offset <= 16'b0;
            processing <= '{default: 1'b0};
            words <= '{default: 16'b0};
            sum_stage1 <= '{default: 16'b0};
            sum_stage2 <= 16'b0;
            fragment_count <= '{default: 6'b0};
            fragment_count_initial <= '{default: 6'b0};
            fragment_buffer <= '{default: 512'b0};
            metadata_latched <= '{default: 1'b0};
            metadata_latched_in <= '{default: 17'b0};
            buffer_select <= 2'b00;
            ready_to_transmit <= '{default: 1'b0};
            transmit_active <= 1'b0;
            transmit_queue <= '{default: 2'b00};
            transmit_queue_head <= 2'b00;
            transmit_queue_tail <= 2'b00;
            m_axis_tlast <= 1'b0;
            current_buffer_index <= 2'b0;
            current_fragment_count <= 6'b0;
            current_fragment_count_initial <= 6'b0;
            m_axis_tkeep <= 64'b0;
            m_axis_tdata <= 512'b0;
        end else begin
            for (int i = 0; i < 4; i++) begin
                case (current_state[i])
                    IDLE: begin
                        if (s_axis_tvalid && user_metadata_in_valid && buffer_select == i) begin
                            metadata_latched[i] <= 1'b1;                        //set metadata latched flag
                            metadata_latched_in[i] <= user_metadata_in;         //stores metadata input
                            payload_offset <= user_metadata_in[16:7] / 2;       //stores number of 16 bit words too skip
                            processing[i] <= 1'b1;                              //set checksum calculation processing flag

                            //checksum calculation of first fragment
                            fragment_buffer[i][0] <= s_axis_tdata;
                            fragment_count[i] <= fragment_count[i] + 1;
                            fragment_count_initial[i] <= fragment_count_initial[i] + 1;

                            for (int j = 0; j < 32; j++) begin
                                words[j] = s_axis_tdata[j * 16 +: 16];
                            end

                            for (int j = 0; j < 32; j++) begin
                                if (j < payload_offset) begin
                                    sum_stage1[j] = 16'h0000;
                                    if (payload_offset > 32) begin
                                        payload_offset <= payload_offset - 32;
                                    end else begin
                                        payload_offset <= 16'b0;
                                    end
                                end else if (s_axis_tkeep[j * 2] && s_axis_tkeep[j * 2 + 1]) begin
                                    sum_stage1[j] = words[j];
                                end else if (s_axis_tkeep[j * 2] && !s_axis_tkeep[j * 2 + 1]) begin
                                    sum_stage1[j] = {8'b0, words[j][7:0]};
                                end else begin
                                    sum_stage1[j] = 16'h0000;
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
                            checksum[i] <= checksum[i] + sum_stage2;
                        end
                    end

                    PROCESS: begin
                        if (s_axis_tvalid && processing[i] && buffer_select == i) begin
                            //checksum calculation of current fragment
                            fragment_buffer[i][fragment_count[i]] <= s_axis_tdata;
                            fragment_count[i] <= fragment_count[i] + 1;
                            fragment_count_initial[i] <= fragment_count_initial[i] + 1;

                            for (int j = 0; j < 32; j++) begin
                                words[j] = s_axis_tdata[j * 16 +: 16];
                            end

                            for (int j = 0; j < 32; j++) begin
                                if (j < payload_offset) begin
                                    sum_stage1[j] = 16'h0000;
                                    if (payload_offset > 32) begin
                                        payload_offset <= payload_offset - 32;
                                    end else begin
                                        payload_offset <= 16'b0;
                                    end
                                end else if (s_axis_tkeep[j * 2] && s_axis_tkeep[j * 2 + 1]) begin
                                    sum_stage1[j] = words[j];
                                end else if (s_axis_tkeep[j * 2] && !s_axis_tkeep[j * 2 + 1]) begin
                                    sum_stage1[j] = {8'b0, words[j][7:0]};
                                end else begin
                                    sum_stage1[j] = 16'h0000;
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
                            checksum[i] <= checksum[i] + sum_stage2;        //cumulative checksum

                            if (s_axis_tlast) begin
                                checksum[i] <= ~checksum[i];
                                ready_to_transmit[i] <= 1'b1;                       //sets transmission ready flag after checksum calculation for current packet
                                transmit_queue[transmit_queue_tail] <= i;           //add current buffer index to transmission queue
                                transmit_queue_tail <= transmit_queue_tail + 1;     //increment transmission queue tail
                                buffer_select <= buffer_select + 1;                 //incerments current buffer
                            end
                        end
                    end

                    DATAOUT: begin
                        if (m_axis_tready) begin
                            //transmission of fragments in current buffer in the transmission queue
                            current_buffer_index = transmit_queue[transmit_queue_head];
                            current_fragment_count = fragment_count[current_buffer_index];
                            current_fragment_count_initial = fragment_count_initial[current_buffer_index];

                            if (current_fragment_count > 0) begin
                                processing[current_buffer_index] <= 1'b0;

                                m_axis_tvalid <= 1'b1;
                                m_axis_tdata <= fragment_buffer[current_buffer_index][current_fragment_count_initial - current_fragment_count];
                                m_axis_tkeep <= 64'hFFFFFFFFFFFFFFFF;
                                m_axis_tlast <= (current_fragment_count == 1);

                                if (current_fragment_count == current_fragment_count_initial) begin
                                    user_metadata_out <= {checksum[current_buffer_index], metadata_latched_in[current_buffer_index][6:0]};
                                    user_metadata_out_valid <= 1'b1;
                                end else begin
                                    user_metadata_out <= 23'b0;
                                    user_metadata_out_valid <= 1'b0;
                                end

                                fragment_count[current_buffer_index] <= current_fragment_count - 1;
                            end else begin
                                m_axis_tvalid <= 1'b0;
                                user_metadata_out <= 23'b0;
                                user_metadata_out_valid <= 1'b0;
                                transmit_queue_head <= transmit_queue_head + 1;
                                m_axis_tdata <= 512'b0;

                                // Clear buffer-specific signals after transmission
                                fragment_count[current_buffer_index] <= 6'b0;
                                fragment_count_initial[current_buffer_index] <= 6'b0;
                                metadata_latched[current_buffer_index] <= 1'b0;
                                metadata_latched_in[current_buffer_index] <= 17'b0;
                                ready_to_transmit[current_buffer_index] <= 1'b0;

                                // Clear transmission  queue after transmission
                                if (transmit_queue_head == transmit_queue_tail) begin
                                    transmit_queue <= '{default: 2'b00};
                                    transmit_queue_head <= 2'b00;
                                    transmit_queue_tail <= 2'b00;
                                    buffer_select <= 2'b00;
                                end
                            end
                        end
                    end
                endcase
            end
        end
    end

endmodule



