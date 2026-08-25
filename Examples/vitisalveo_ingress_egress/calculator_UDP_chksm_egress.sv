`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
////FIN-OVGU Magdeburg
// Module Name: calculator_UDP_chksm_egress
// Revision 0.02 - Same fix set as ingress_checksum_calculator.sv, adapted to
//   this module's narrower metadata widths (27-bit in: bit0=tdest,
//   [16:1]=size, [26:17]=offset; 17-bit out: [16:1]=checksum, bit0=tdest).
//////////////////////////////////////////////////////////////////////////////////

module calculator_UDP_chksm_egress #(
    parameter int Max_frag_count = 25
) (
    input  logic        clk,
    input  logic        rst,

    input  logic [511:0] s_axis_tdata,
    input  logic [63:0]  s_axis_tkeep,
    input  logic         s_axis_tlast,
    output logic         s_axis_tready,
    input  logic         s_axis_tvalid,
    input  logic [26:0]   user_metadata_in,
    input  logic          user_metadata_in_valid,

    output logic [511:0] m_axis_tdata,
    output logic [63:0]  m_axis_tkeep,
    output logic         m_axis_tlast,
    input  logic         m_axis_tready,
    output logic         m_axis_tvalid,
    output logic [16:0]  user_metadata_out,
    output logic         user_metadata_out_valid
);

    logic [15:0] checksum[4];
    logic [15:0] final_checksum[4];
    logic [31:0][15:0] words;
    logic [31:0][15:0] sum_stage1;
    logic [17:0] fold_tmp;
    logic [15:0] payload_offset;
    logic [15:0] beat_offset_words;
    logic        processing[4];
    logic [Max_frag_count:0][511:0] fragment_buffer[4];
    logic [5:0]   fragment_count[4];
    logic [5:0]   fragment_count_initial[4];
    logic         metadata_latched[4];
    logic [26:0]  metadata_latched_in[4];
    logic [1:0]   buffer_select;
    logic         ready_to_transmit[4];
    logic         transmit_active;
    logic [1:0]   transmit_queue[4];
    logic [1:0]   transmit_queue_head;
    logic [1:0]   transmit_queue_tail;

    logic [1:0]   current_buffer_index;
    logic [5:0]   current_fragment_count;
    logic [5:0]   current_fragment_count_initial;

    logic [31:0][15:0] sum_stage1_pipe[4];
    logic        sum_stage1_valid_pipe[4];
    logic        sum_stage1_tlast_pipe[4];
    logic [31:0] sum_stage2_pipe[4];
    logic        sum_valid_pipe[4];
    logic        tlast_pipe[4];

    typedef enum logic [2:0] {
        IDLE     = 3'b001,
        PROCESS  = 3'b010,
        FINALIZE = 3'b011,
        DATAOUT  = 3'b100
    } checksum_FSM;

    checksum_FSM current_state[4], next_state[4];

    always_ff @(posedge clk ) begin
        if (!rst) begin
            for (int i = 0; i < 4; i++) current_state[i] <= IDLE;
        end else begin
            for (int i = 0; i < 4; i++) current_state[i] <= next_state[i];
        end
    end

    always_comb begin
        for (int i = 0; i < 4; i++) begin
            next_state[i] = current_state[i];
            case (current_state[i])
                IDLE: begin
                    if (s_axis_tvalid && user_metadata_in_valid && buffer_select == i) begin
                        next_state[i] = s_axis_tlast ? FINALIZE : PROCESS;
                    end else begin
                        next_state[i] = IDLE;
                    end
                end
                PROCESS: begin
                    next_state[i] = (s_axis_tlast && buffer_select == i) ? FINALIZE : PROCESS;
                end
                FINALIZE: begin
                    next_state[i] = ready_to_transmit[i] ? DATAOUT : FINALIZE;
                end
                DATAOUT: begin
                    next_state[i] = (fragment_count[i] == 0) ? IDLE : DATAOUT;
                end
            endcase
        end
    end

    assign s_axis_tready = (current_state[buffer_select] != DATAOUT) &&
                            (current_state[buffer_select] != FINALIZE);

    always_ff @(posedge clk ) begin
        if (!rst) begin
            m_axis_tvalid <= 1'b0;
            user_metadata_out <= 17'b0;
            user_metadata_out_valid <= 1'b0;
            checksum <= '{default: 16'h0000};
            final_checksum <= '{default: 16'h0000};
            payload_offset <= 16'b0;
            processing <= '{default: 1'b0};
            words <= '{default: 16'b0};
            sum_stage1 <= '{default: 16'b0};
            sum_stage1_pipe <= '{default: 16'b0};
            sum_stage1_valid_pipe <= '{default: 1'b0};
            sum_stage1_tlast_pipe <= '{default: 1'b0};
            sum_stage2_pipe <= '{default: 32'b0};
            sum_valid_pipe <= '{default: 1'b0};
            tlast_pipe <= '{default: 1'b0};
            fragment_count <= '{default: 6'b0};
            fragment_count_initial <= '{default: 6'b0};
            fragment_buffer <= '{default: 512'b0};
            metadata_latched <= '{default: 1'b0};
            metadata_latched_in <= '{default: 27'b0};
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
                if (sum_valid_pipe[i]) begin
                    fold_tmp = {2'b0, checksum[i]} + {2'b0, sum_stage2_pipe[i][15:0]} + {2'b0, sum_stage2_pipe[i][31:16]};
                    checksum[i] <= fold_tmp[15:0] + {14'b0, fold_tmp[17:16]};
                    sum_valid_pipe[i] <= 1'b0;
                    if (tlast_pipe[i]) begin
                        // FIXED: restored the one's-complement inversion.
                        final_checksum[i] <= ~(fold_tmp[15:0] + {14'b0, fold_tmp[17:16]});
                        ready_to_transmit[i] <= 1'b1;
                        transmit_queue[transmit_queue_tail] <= i;
                        transmit_queue_tail <= transmit_queue_tail + 1;
                        if (transmit_queue_head == transmit_queue_tail) begin
                            current_buffer_index <= i[1:0];
                        end
                    end
                end
            end

            for (int i = 0; i < 4; i++) begin
                if (sum_stage1_valid_pipe[i]) begin
                    sum_stage2_pipe[i] <= sum_stage1_pipe[i][0]  + sum_stage1_pipe[i][1]  + sum_stage1_pipe[i][2]  + sum_stage1_pipe[i][3] +
                                           sum_stage1_pipe[i][4]  + sum_stage1_pipe[i][5]  + sum_stage1_pipe[i][6]  + sum_stage1_pipe[i][7] +
                                           sum_stage1_pipe[i][8]  + sum_stage1_pipe[i][9]  + sum_stage1_pipe[i][10] + sum_stage1_pipe[i][11] +
                                           sum_stage1_pipe[i][12] + sum_stage1_pipe[i][13] + sum_stage1_pipe[i][14] + sum_stage1_pipe[i][15] +
                                           sum_stage1_pipe[i][16] + sum_stage1_pipe[i][17] + sum_stage1_pipe[i][18] + sum_stage1_pipe[i][19] +
                                           sum_stage1_pipe[i][20] + sum_stage1_pipe[i][21] + sum_stage1_pipe[i][22] + sum_stage1_pipe[i][23] +
                                           sum_stage1_pipe[i][24] + sum_stage1_pipe[i][25] + sum_stage1_pipe[i][26] + sum_stage1_pipe[i][27] +
                                           sum_stage1_pipe[i][28] + sum_stage1_pipe[i][29] + sum_stage1_pipe[i][30] + sum_stage1_pipe[i][31];
                    sum_valid_pipe[i] <= 1'b1;
                    tlast_pipe[i] <= sum_stage1_tlast_pipe[i];
                    sum_stage1_valid_pipe[i] <= 1'b0;
                end
            end

            for (int i = 0; i < 4; i++) begin
                case (current_state[i])
                    IDLE: begin
                        if (s_axis_tvalid && user_metadata_in_valid && buffer_select == i) begin
                            metadata_latched[i] <= 1'b1;
                            metadata_latched_in[i] <= user_metadata_in;
                            processing[i] <= 1'b1;

                            fragment_buffer[i][0] <= s_axis_tdata;
                            fragment_count[i] <= fragment_count[i] + 1;
                            fragment_count_initial[i] <= fragment_count_initial[i] + 1;

                            for (int j = 0; j < 32; j++) words[j] = s_axis_tdata[j * 16 +: 16];

                            beat_offset_words = user_metadata_in[26:17] / 2;
                            payload_offset <= (beat_offset_words > 32) ? (beat_offset_words - 32) : 16'b0;

                            for (int j = 0; j < 32; j++) begin
                                if (j < beat_offset_words) begin
                                    sum_stage1[j] = 16'h0000;
                                end else if (s_axis_tkeep[j * 2] && s_axis_tkeep[j * 2 + 1]) begin
                                    sum_stage1[j] = words[j];
                                end else if (s_axis_tkeep[j * 2] && !s_axis_tkeep[j * 2 + 1]) begin
                                    sum_stage1[j] = {8'b0, words[j][7:0]};
                                end else begin
                                    sum_stage1[j] = 16'h0000;
                                end
                            end

                            sum_stage1_pipe[i] <= sum_stage1;
                            sum_stage1_valid_pipe[i] <= 1'b1;
                            sum_stage1_tlast_pipe[i] <= s_axis_tlast;

                            if (s_axis_tlast) buffer_select <= buffer_select + 1;
                        end
                    end

                    PROCESS: begin
                        if (s_axis_tvalid && processing[i] && buffer_select == i) begin
                            fragment_buffer[i][fragment_count[i]] <= s_axis_tdata;
                            fragment_count[i] <= fragment_count[i] + 1;
                            fragment_count_initial[i] <= fragment_count_initial[i] + 1;

                            for (int j = 0; j < 32; j++) words[j] = s_axis_tdata[j * 16 +: 16];

                            beat_offset_words = payload_offset;
                            payload_offset <= (payload_offset > 32) ? (payload_offset - 32) : 16'b0;

                            for (int j = 0; j < 32; j++) begin
                                if (j < beat_offset_words) begin
                                    sum_stage1[j] = 16'h0000;
                                end else if (s_axis_tkeep[j * 2] && s_axis_tkeep[j * 2 + 1]) begin
                                    sum_stage1[j] = words[j];
                                end else if (s_axis_tkeep[j * 2] && !s_axis_tkeep[j * 2 + 1]) begin
                                    sum_stage1[j] = {8'b0, words[j][7:0]};
                                end else begin
                                    sum_stage1[j] = 16'h0000;
                                end
                            end

                            sum_stage1_pipe[i] <= sum_stage1;
                            sum_stage1_valid_pipe[i] <= 1'b1;
                            sum_stage1_tlast_pipe[i] <= s_axis_tlast;

                            if (s_axis_tlast) buffer_select <= buffer_select + 1;
                        end
                    end

                    FINALIZE: begin
                        // Waits on ready_to_transmit[i].
                    end

                    DATAOUT: begin
                        if (m_axis_tready) begin
                            current_fragment_count = fragment_count[current_buffer_index];
                            current_fragment_count_initial = fragment_count_initial[current_buffer_index];

                            if (current_fragment_count > 0) begin
                                processing[current_buffer_index] <= 1'b0;

                                m_axis_tvalid <= 1'b1;
                                m_axis_tdata <= fragment_buffer[current_buffer_index][current_fragment_count_initial - current_fragment_count];
                                m_axis_tkeep <= 64'hFFFFFFFFFFFFFFFF;
                                m_axis_tlast <= (current_fragment_count == 1);

                                if (current_fragment_count == current_fragment_count_initial) begin
                                    // Output layout: [16:1]=checksum, bit0=tdest
                                    // (matches the original metadata_latched_in[0:0]
                                    // usage -- bit 0 of the 27-bit input is tdest).
                                    user_metadata_out <= {final_checksum[current_buffer_index], metadata_latched_in[current_buffer_index][0:0]};
                                    user_metadata_out_valid <= 1'b1;
                                    checksum[current_buffer_index] <= 16'b0;
                                    final_checksum[current_buffer_index] <= 16'b0;
                                end else begin
                                    user_metadata_out <= 17'b0;
                                    user_metadata_out_valid <= 1'b0;
                                end

                                fragment_count[current_buffer_index] <= current_fragment_count - 1;
                            end else begin
                                m_axis_tvalid <= 1'b0;
                                user_metadata_out <= 17'b0;
                                user_metadata_out_valid <= 1'b0;
                                transmit_queue_head <= transmit_queue_head + 1;
                                m_axis_tdata <= 512'b0;

                                if (!(transmit_queue_head == transmit_queue_tail)) begin
                                    current_buffer_index <= transmit_queue[transmit_queue_head + 1];
                                end

                                fragment_count[current_buffer_index] <= 6'b0;
                                fragment_count_initial[current_buffer_index] <= 6'b0;
                                metadata_latched[current_buffer_index] <= 1'b0;
                                metadata_latched_in[current_buffer_index] <= 27'b0;
                                ready_to_transmit[current_buffer_index] <= 1'b0;

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
