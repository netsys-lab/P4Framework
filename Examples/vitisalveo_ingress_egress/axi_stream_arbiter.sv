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
(* dont_touch = "true" *)
module axi_stream_arbiter (
    input logic clk,
    input logic rst_n,

    // AXI Stream Slave 1 Interface
    input logic  [1023:0] s_axis_tdata,
    input logic  [127:0]  s_axis_tkeep,
    input logic  [1:0]    s_axis_tvalid,
    output logic [1:0]    s_axis_tready,
    input logic  [1:0]    s_axis_tlast,

    // AXI Stream Master Interface
    output logic [511:0] m_axis_tdata,
    output logic [63:0]  m_axis_tkeep,
    output logic         m_axis_tvalid,
    input logic          m_axis_tready,
    output logic         m_axis_tlast
);

    // FSM States
    typedef enum logic [4:0] {
        IDLE        = 4'b0001,
        SEND_SLAVE1 = 4'b0010,
        SEND_SLAVE2 = 4'b0100,
        WAIT_LAST   = 4'b1000
    } state_t;

    state_t current_state, next_state;

    // Internal signals
    reg [511:0]  m_axis_tdata_reg;
    reg [63:0]   m_axis_tkeep_reg;
    reg          m_axis_tvalid_reg;
    reg          m_axis_tlast_reg;
    reg [1:0]    s_axis_tready_reg;

    // FSM State Transition
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // FSM Next State Logic
    always_comb begin
        next_state = current_state;
        case (current_state)

            IDLE: begin
                if (s_axis_tvalid[0:0] && s_axis_tready[0:0] && m_axis_tready) begin
                    next_state = SEND_SLAVE1;
                end else if (s_axis_tvalid[1:1] && s_axis_tready[1:1] && m_axis_tready) begin
                    next_state = SEND_SLAVE2;
                end else begin
                    next_state = IDLE;
                end
            end

            SEND_SLAVE1: begin
                if (s_axis_tlast[0:0] && m_axis_tready) begin
                        next_state = WAIT_LAST;
                end else begin
                        next_state = SEND_SLAVE1;
                 end
               end

            SEND_SLAVE2: begin
                if (s_axis_tlast[1:1] && m_axis_tready) begin
                        next_state = WAIT_LAST;
                    end else begin
                        next_state = SEND_SLAVE2;
                    end
                end

           WAIT_LAST: begin
               if (s_axis_tvalid[0:0] ) begin
                   next_state = SEND_SLAVE1;
               end else if (s_axis_tvalid[1:1]) begin
                   next_state = SEND_SLAVE2;
               end else begin
                   next_state = IDLE;
               end
           end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // FSM Output Logic
    always_comb begin
        m_axis_tdata_reg = 512'b0;
        m_axis_tkeep_reg = 64'b0;
        m_axis_tvalid_reg = 1'b0;
        m_axis_tlast_reg = 1'b0;
        s_axis_tready_reg = 2'b0;

        case (current_state)
            IDLE: begin
                m_axis_tdata_reg = 512'b0;
                m_axis_tkeep_reg = 64'b0;
                m_axis_tvalid_reg = 1'b0;
                m_axis_tlast_reg = 1'b0;
                s_axis_tready_reg = 2'b11;
                end

            SEND_SLAVE1: begin
                m_axis_tdata_reg       =  s_axis_tdata[511:0];
                m_axis_tkeep_reg       =  s_axis_tkeep[63:0];
                m_axis_tvalid_reg      =  s_axis_tvalid[0:0];
                m_axis_tlast_reg       =  s_axis_tlast[0:0];
                s_axis_tready_reg[0:0] =  m_axis_tready;
            end

            WAIT_LAST: begin
                if (s_axis_tvalid[0:0]) begin
                m_axis_tdata_reg       =  s_axis_tdata[511:0];
                m_axis_tkeep_reg       =  s_axis_tkeep[63:0];
                m_axis_tvalid_reg      =  s_axis_tvalid[0:0];
                m_axis_tlast_reg       =  s_axis_tlast[0:0];
                s_axis_tready_reg[0:0] =  m_axis_tready;
               end else if (s_axis_tvalid[1:1]) begin
                m_axis_tdata_reg       =  s_axis_tdata[1023:512];
                m_axis_tkeep_reg       =  s_axis_tkeep[127:64];
                m_axis_tvalid_reg      =  s_axis_tvalid[1:1];
                m_axis_tlast_reg       =  s_axis_tlast[1:1];
                s_axis_tready_reg[1:1] =  m_axis_tready;
               end else begin
                m_axis_tdata_reg = 512'b0;
                m_axis_tkeep_reg = 64'b0;
                m_axis_tvalid_reg = 1'b0;
                m_axis_tlast_reg = 1'b0;
                s_axis_tready_reg = 2'b11;
               end
           end

            SEND_SLAVE2: begin
                m_axis_tdata_reg       =  s_axis_tdata[1023:512];
                m_axis_tkeep_reg       =  s_axis_tkeep[127:64];
                m_axis_tvalid_reg      =  s_axis_tvalid[1:1];
                m_axis_tlast_reg       =  s_axis_tlast[1:1];
                s_axis_tready_reg[1:1] =  m_axis_tready;
            end
            default: begin
                m_axis_tdata_reg  = 512'b0;
                m_axis_tkeep_reg  = 64'b0;
                m_axis_tvalid_reg = 1'b0;
                m_axis_tlast_reg  = 1'b0;
                s_axis_tready_reg = 2'b0;
            end
        endcase
    end

    // Assign outputs
    assign m_axis_tdata  = m_axis_tdata_reg;
    assign m_axis_tkeep  = m_axis_tkeep_reg;
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign m_axis_tlast  = m_axis_tlast_reg;
    assign s_axis_tready = s_axis_tready_reg;


endmodule
