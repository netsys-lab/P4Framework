// *************************************************************************
//
// Copyright 2020 Xilinx, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// *************************************************************************
//
// 250 MHz user box: SCION ingress/egress translation.
//
// RX: CMAC adapter -> ingress classifier -> ingress checksum -> ingress translator
//     -> FIFO 0 -> arbiter -> QDMA C2H
// TX: QDMA H2C -> egress translator -> AXIS switch
//        tdest 0: egress checksum -> egress checksum P4 -> CMAC adapter
//        tdest 1: FIFO 1 -> arbiter -> QDMA C2H (packets returned to the host)
//
// Vitis Net P4 metadata ports are packed structs: the first field of the
// P4 metadata_t is in the MSBs.
//   classifier         (33b): tuser_size[32:17] is_scion[16] hop_fields[15:10] payload_offset[9:0]
//   ingress translator (39b): tuser_size[38:23] is_scion[22] hop_fields[21:16] payload_chksum[15:0]
//   egress translator  (59b): axis_tdest[58] tuser_size[57:42] payload_offset[41:32]
//                             l4_src_port[31:16] l4_dst_port[15:0]
//   egress checksum    (16b): payload_chksum[15:0]
//
`include "open_nic_shell_macros.vh"
`timescale 1ns/1ps
module p2p_250mhz #(
  parameter int NUM_INTF = 4
) (
  // AXI-Lite input from crossbar to ingress classifier
  input                     s_axil_awvalid,
  input              [31:0] s_axil_awaddr,
  output                    s_axil_awready,
  input                     s_axil_wvalid,
  input              [31:0] s_axil_wdata,
  output                    s_axil_wready,
  output                    s_axil_bvalid,
  output              [1:0] s_axil_bresp,
  input                     s_axil_bready,
  input                     s_axil_arvalid,
  input              [31:0] s_axil_araddr,
  output                    s_axil_arready,
  output                    s_axil_rvalid,
  output             [31:0] s_axil_rdata,
  output              [1:0] s_axil_rresp,
  input                     s_axil_rready,

  // AXI-Lite input from crossbar to ingress translator
  input                     s_axil_new_awvalid,
  input              [31:0] s_axil_new_awaddr,
  output                    s_axil_new_awready,
  input                     s_axil_new_wvalid,
  input              [31:0] s_axil_new_wdata,
  output                    s_axil_new_wready,
  output                    s_axil_new_bvalid,
  output              [1:0] s_axil_new_bresp,
  input                     s_axil_new_bready,
  input                     s_axil_new_arvalid,
  input              [31:0] s_axil_new_araddr,
  output                    s_axil_new_arready,
  output                    s_axil_new_rvalid,
  output             [31:0] s_axil_new_rdata,
  output              [1:0] s_axil_new_rresp,
  input                     s_axil_new_rready,

  // AXI-Lite input from crossbar to egress translator
  input                     s_axil_egress_awvalid,
  input              [31:0] s_axil_egress_awaddr,
  output                    s_axil_egress_awready,
  input                     s_axil_egress_wvalid,
  input              [31:0] s_axil_egress_wdata,
  output                    s_axil_egress_wready,
  output                    s_axil_egress_bvalid,
  output              [1:0] s_axil_egress_bresp,
  input                     s_axil_egress_bready,
  input                     s_axil_egress_arvalid,
  input              [31:0] s_axil_egress_araddr,
  output                    s_axil_egress_arready,
  output                    s_axil_egress_rvalid,
  output             [31:0] s_axil_egress_rdata,
  output              [1:0] s_axil_egress_rresp,
  input                     s_axil_egress_rready,

  // QDMA H2C to egress translator
  input                s_axis_qdma_h2c_tvalid,
  input  [511:0]       s_axis_qdma_h2c_tdata,
  input   [63:0]       s_axis_qdma_h2c_tkeep,
  input                s_axis_qdma_h2c_tlast,
  input   [15:0]       s_axis_qdma_h2c_tuser_size,
  //input   [15:0]       s_axis_qdma_h2c_tuser_src,
  //input   [15:0]       s_axis_qdma_h2c_tuser_dst,
  output               s_axis_qdma_h2c_tready,

  // Arbiter to QDMA C2H
  output               m_axis_qdma_c2h_tvalid,
  output [511:0]       m_axis_qdma_c2h_tdata,
  output  [63:0]       m_axis_qdma_c2h_tkeep,
  output               m_axis_qdma_c2h_tlast,
  output  [15:0]       m_axis_qdma_c2h_tuser_size,
  //output  [15:0]       m_axis_qdma_c2h_tuser_src,
  //output  [15:0]       m_axis_qdma_c2h_tuser_dst,
  input                m_axis_qdma_c2h_tready,

  // Egress checksum P4 to CMAC packet adapter
  output               m_axis_adap_tx_250mhz_tvalid,
  output [511:0]       m_axis_adap_tx_250mhz_tdata,
  output  [63:0]       m_axis_adap_tx_250mhz_tkeep,
  output               m_axis_adap_tx_250mhz_tlast,
  output  [15:0]       m_axis_adap_tx_250mhz_tuser_size,
  output  [15:0]       m_axis_adap_tx_250mhz_tuser_src,
  output  [15:0]       m_axis_adap_tx_250mhz_tuser_dst,
  input                m_axis_adap_tx_250mhz_tready,

  // CMAC packet adapter to ingress classifier
  input                s_axis_adap_rx_250mhz_tvalid,
  input  [511:0]       s_axis_adap_rx_250mhz_tdata,
  input   [63:0]       s_axis_adap_rx_250mhz_tkeep,
  input                s_axis_adap_rx_250mhz_tlast,
  input   [15:0]       s_axis_adap_rx_250mhz_tuser_size,
  //input   [15:0]       s_axis_adap_rx_250mhz_tuser_src,
  //input   [15:0]       s_axis_adap_rx_250mhz_tuser_dst,
  output               s_axis_adap_rx_250mhz_tready,

  input                     mod_rstn,
  output                    mod_rst_done,

  input                     axil_aclk,
  input                     axis_aclk
);

  wire axil_aresetn;   // synchronous to axil_aclk
  wire axis_aresetn;   // synchronous to axis_aclk

  generic_reset #(
    .NUM_INPUT_CLK  (1),
    .RESET_DURATION (100)
  ) axil_reset_inst (
    .mod_rstn     (mod_rstn),
    .mod_rst_done (mod_rst_done),
    .clk          (axil_aclk),
    .rstn         (axil_aresetn)
  );

  xpm_cdc_async_rst #(
    .DEST_SYNC_FF(4),
    .RST_ACTIVE_HIGH(0)
  ) axis_rstn_cdc (
    .src_arst(axil_aresetn),
    .dest_clk(axis_aclk),
    .dest_arst(axis_aresetn)
  );

  wire [32:0] ingress_metadata_in;
  wire [58:0] egress_metadata_in;

  // Ingress classifier to ingress checksum calculator
  wire [511:0] axis_signal_tdata;
  wire [63:0]  axis_signal_tkeep;
  wire         axis_signal_tlast;
  wire         axis_signal_tvalid;
  wire         axis_signal_tready;
  wire [32:0]  metadata_signal_out;
  wire         metadata_signal_valid;

  //pipeline register between Ingress classifier and ingress checksum calculator
  wire [511:0] axis_signal_pipe_tdata;
  wire [63:0]  axis_signal_pipe_tkeep;
  wire         axis_signal_pipe_tlast;
  wire         axis_signal_pipe_tvalid;
  wire         axis_signal_pipe_tready;
  logic [32:0] metadata_signal_pipe_out;
  logic        metadata_signal_pipe_valid;

  // Ingress checksum calculator to ingress translator
  wire [511:0] axis_Checksum_0_tdata;
  wire [63:0]  axis_Checksum_0_tkeep;
  wire         axis_Checksum_0_tlast;
  wire         axis_Checksum_0_tvalid;
  wire         axis_Checksum_0_tready;
  wire [38:0]  metadata_Checksum_0_out;
  wire         metadata_Checksum_0_valid;

 //pipeline register between Ingress checksum calculator and ingress translator
  wire [511:0] axis_Checksum_0_pipe_tdata;
  wire [63:0]  axis_Checksum_0_pipe_tkeep;
  wire         axis_Checksum_0_pipe_tlast;
  wire         axis_Checksum_0_pipe_tvalid;
  wire         axis_Checksum_0_pipe_tready;
  logic [38:0] metadata_Checksum_0_pipe_out;
  logic        metadata_Checksum_0_pipe_valid;

  // Ingress translator to FIFO 0
  wire [511:0] axis_ingress_tdata;
  wire [63:0]  axis_ingress_tkeep;
  wire         axis_ingress_tlast;
  wire         axis_ingress_tvalid;
  wire         axis_ingress_tready;
  wire [38:0]  metadata_ingress_out;
  wire         metadata_ingress_valid;

  // Egress translator to AXIS switch
  wire [511:0] axis_egress_tdata;
  wire [63:0]  axis_egress_tkeep;
  wire         axis_egress_tlast;
  wire         axis_egress_tvalid;
  wire         axis_egress_tready;
  wire         axis_egress_tdest;
  wire [58:0]  metadata_egress_out;
  wire         metadata_egress_valid;

  //Pipeline registers between egress translator and axis switch
  wire [511:0] axis_egress_pipe_tdata;
  wire [63:0]  axis_egress_pipe_tkeep;
  wire         axis_egress_pipe_tlast;
  wire         axis_egress_pipe_tvalid;
  wire         axis_egress_pipe_tready;
  logic [58:0] metadata_egress_pipe_out;

  // Egress checksum calculator to egress checksum P4
  wire [511:0] axis_Checksum_1_tdata;
  wire [63:0]  axis_Checksum_1_tkeep;
  wire         axis_Checksum_1_tlast;
  wire         axis_Checksum_1_tvalid;
  wire         axis_Checksum_1_tready;
  wire [15:0]  metadata_Checksum_1_out;
  wire         metadata_Checksum_1_valid;

  // AXIS switch M0 to egress checksum calculator
  wire [511:0] axis_switch_1_pipe_tdata;
  wire [63:0]  axis_switch_1_pipe_tkeep;
  wire         axis_switch_1_pipe_tlast;
  wire         axis_switch_1_pipe_tvalid;
  wire         axis_switch_1_pipe_tready;
  logic [9:0]  axis_switch_1_pipe_tuser;
  logic        axis_switch_1_pipe_tuser_valid;

  // AXIS switch outputs, {M1, M0}
  wire [1023:0] egress_switch_1_tdata;
  wire [127:0]  egress_switch_1_tkeep;
  wire [1:0]    egress_switch_1_tlast;
  wire [51:0]   egress_switch_1_tuser;   // per master: {payload_offset[25:16], tuser_size[15:0]}

  //fifo 0 to arbiter
  wire [511:0] axis_fifo_0_tdata;
  wire [63:0]  axis_fifo_0_tkeep;
  wire         axis_fifo_0_tlast;
  wire         axis_fifo_0_tvalid;
  wire         axis_fifo_0_tready;
  wire [15:0]  axis_fifo_0_tuser;

  //fifo 1 to arbiter
  wire [511:0] axis_fifo_1_tdata;
  wire [63:0]  axis_fifo_1_tkeep;
  wire         axis_fifo_1_tlast;
  wire         axis_fifo_1_tvalid;
  wire         axis_fifo_1_tready;
  wire [15:0]  axis_fifo_1_tuser;

  //pipeline register between fifo 0 and arbiter
  wire [511:0] axis_fifo_0_pipe_tdata;
  wire [63:0]  axis_fifo_0_pipe_tkeep;
  wire         axis_fifo_0_pipe_tlast;
  wire         axis_fifo_0_pipe_tvalid;
  wire         axis_fifo_0_pipe_tready;
  wire [15:0]  axis_fifo_0_pipe_tuser;

  //pipeline register between fifo 1 and arbiter
  wire [511:0] axis_fifo_1_pipe_tdata;
  wire [63:0]  axis_fifo_1_pipe_tkeep;
  wire         axis_fifo_1_pipe_tlast;
  wire         axis_fifo_1_pipe_tvalid;
  wire         axis_fifo_1_pipe_tready;
  wire [15:0]  axis_fifo_1_pipe_tuser;

  // AXIS switch M0 (tdest 0): to the egress path
  wire [511:0] axis_switch_0_tdata;
  wire [63:0]  axis_switch_0_tkeep;
  wire         axis_switch_0_tlast;
  wire         axis_switch_0_tvalid;
  wire         axis_switch_0_tready;
  wire [9:0]   axis_switch_0_tuser;     // payload_offset

  // AXIS switch M1 (tdest 1): back to the host(QDMA)
  wire [511:0] axis_switch_1_tdata;
  wire [63:0]  axis_switch_1_tkeep;
  wire         axis_switch_1_tlast;
  wire         axis_switch_1_tvalid;
  wire         axis_switch_1_tready;
  wire [15:0]  axis_switch_1_tuser;     // tuser_size

  // Arbiter -> QDMA
  wire [511:0] m_axis_arbiter_pipe_tdata;
  wire [63:0]  m_axis_arbiter_pipe_tkeep;
  wire         m_axis_arbiter_pipe_tlast;
  wire         m_axis_arbiter_pipe_tvalid;
  wire         m_axis_arbiter_pipe_tready;
  wire [15:0]  m_axis_arbiter_pipe_tuser;

  assign axis_switch_0_tdata = egress_switch_1_tdata[511:0];
  assign axis_switch_0_tkeep = egress_switch_1_tkeep[63:0];
  assign axis_switch_0_tlast = egress_switch_1_tlast[0];
  assign axis_switch_0_tuser = egress_switch_1_tuser[25:16];

  assign axis_switch_1_tdata = egress_switch_1_tdata[1023:512];
  assign axis_switch_1_tkeep = egress_switch_1_tkeep[127:64];
  assign axis_switch_1_tlast = egress_switch_1_tlast[1];
  assign axis_switch_1_tuser = egress_switch_1_tuser[41:26];

  // is_scion, hop_fields and payload_offset are set by the classifier
  assign ingress_metadata_in = {s_axis_adap_rx_250mhz_tuser_size, 17'b0};

  // l4_src_port / l4_dst_port are internal to the egress translator
  assign egress_metadata_in  = {1'b0, s_axis_qdma_h2c_tuser_size, 10'b0, 16'b0, 16'b0};

  // TX sideband to packet_adapter_tx. tuser_dst bit 6 selects CMAC 0;
  // packet_adapter_tx drops packets without it.
  // With tuser_size = 0 the adapter uses the last-beat tkeep as is.
  assign m_axis_adap_tx_250mhz_tuser_size = 16'h0000;
  assign m_axis_adap_tx_250mhz_tuser_src  = 16'h0001;
  assign m_axis_adap_tx_250mhz_tuser_dst  = 16'h0040;

  generate for (genvar i = 0; i < NUM_INTF; i++) begin

    if (i==0) begin     // ingress classifier
      vitis_net_p4_0 ingress_classifier_p4 (
        .s_axis_aclk     (axis_aclk),
        .s_axis_aresetn  (axis_aresetn),
        .s_axi_aclk      (axil_aclk),
        .s_axi_aresetn   (axil_aresetn),
        .cam_mem_aclk    (axis_aclk),
        .cam_mem_aresetn (axis_aresetn),

        .s_axis_tdata            (s_axis_adap_rx_250mhz_tdata),
        .s_axis_tkeep            (s_axis_adap_rx_250mhz_tkeep),
        .s_axis_tlast            (s_axis_adap_rx_250mhz_tlast),
        .s_axis_tvalid           (s_axis_adap_rx_250mhz_tvalid),
        .s_axis_tready           (s_axis_adap_rx_250mhz_tready),
        .user_metadata_in        (ingress_metadata_in),
        .user_metadata_in_valid  (s_axis_adap_rx_250mhz_tvalid),

        .m_axis_tdata            (axis_signal_tdata),
        .m_axis_tkeep            (axis_signal_tkeep),
        .m_axis_tlast            (axis_signal_tlast),
        .m_axis_tvalid           (axis_signal_tvalid),
        .m_axis_tready           (axis_signal_tready),
        .user_metadata_out       (metadata_signal_out),
        .user_metadata_out_valid (metadata_signal_valid),

        .s_axi_araddr    (s_axil_araddr),
        .s_axi_arready   (s_axil_arready),
        .s_axi_arvalid   (s_axil_arvalid),
        .s_axi_awaddr    (s_axil_awaddr),
        .s_axi_awready   (s_axil_awready),
        .s_axi_awvalid   (s_axil_awvalid),
        .s_axi_bready    (s_axil_bready),
        .s_axi_bresp     (s_axil_bresp),
        .s_axi_bvalid    (s_axil_bvalid),
        .s_axi_rdata     (s_axil_rdata),
        .s_axi_rready    (s_axil_rready),
        .s_axi_rresp     (s_axil_rresp),
        .s_axi_rvalid    (s_axil_rvalid),
        .s_axi_wdata     (s_axil_wdata),
        .s_axi_wready    (s_axil_wready),
        .s_axi_wstrb     (4'b1111),
        .s_axi_wvalid    (s_axil_wvalid)
      );

      //pipeline register bewteen classifier and checksum calculator
      axis_register_slice_pipeline reg_slice_classifier_to_checksum (
        .aclk          (axis_aclk),
        .aresetn       (axis_aresetn),
        .s_axis_tdata  (axis_signal_tdata),
        .s_axis_tkeep  (axis_signal_tkeep),
        .s_axis_tlast  (axis_signal_tlast),
        .s_axis_tvalid (axis_signal_tvalid),
        .s_axis_tready (axis_signal_tready),
        .m_axis_tdata  (axis_signal_pipe_tdata),
        .m_axis_tkeep  (axis_signal_pipe_tkeep),
        .m_axis_tlast  (axis_signal_pipe_tlast),
        .m_axis_tvalid (axis_signal_pipe_tvalid),
        .m_axis_tready (axis_signal_pipe_tready)
      );

      // metadata follows the register slice
      always @(posedge axis_aclk or negedge axis_aresetn) begin
        if (!axis_aresetn) begin
          metadata_signal_pipe_out   <= 33'b0;
          metadata_signal_pipe_valid <= 1'b0;
        end else begin
          if (axis_signal_tvalid && axis_signal_tready) begin
            metadata_signal_pipe_out   <= metadata_signal_out;
            metadata_signal_pipe_valid <= metadata_signal_valid;
          end else if (!axis_signal_pipe_tvalid || axis_signal_pipe_tready) begin
            metadata_signal_pipe_valid <= 1'b0;
          end
        end
      end

    end if (i==1) begin       // ingress translator

      vitis_net_p4_1 ingress_translator_p4 (
        .s_axis_aclk     (axis_aclk),
        .s_axis_aresetn  (axis_aresetn),
        .s_axi_aclk      (axil_aclk),
        .s_axi_aresetn   (axil_aresetn),
        .cam_mem_aclk    (axis_aclk),
        .cam_mem_aresetn (axis_aresetn),

        .s_axis_tdata            (axis_Checksum_0_pipe_tdata),
        .s_axis_tkeep            (axis_Checksum_0_pipe_tkeep),
        .s_axis_tlast            (axis_Checksum_0_pipe_tlast),
        .s_axis_tvalid           (axis_Checksum_0_pipe_tvalid),
        .s_axis_tready           (axis_Checksum_0_pipe_tready),
        .user_metadata_in        (metadata_Checksum_0_pipe_out),
        .user_metadata_in_valid  (metadata_Checksum_0_pipe_valid),

        .m_axis_tdata            (axis_ingress_tdata),
        .m_axis_tkeep            (axis_ingress_tkeep),
        .m_axis_tlast            (axis_ingress_tlast),
        .m_axis_tvalid           (axis_ingress_tvalid),
        .m_axis_tready           (axis_ingress_tready),
        .user_metadata_out       (metadata_ingress_out),
        .user_metadata_out_valid (metadata_ingress_valid),

        .s_axi_araddr    (s_axil_new_araddr),
        .s_axi_arready   (s_axil_new_arready),
        .s_axi_arvalid   (s_axil_new_arvalid),
        .s_axi_awaddr    (s_axil_new_awaddr),
        .s_axi_awready   (s_axil_new_awready),
        .s_axi_awvalid   (s_axil_new_awvalid),
        .s_axi_bready    (s_axil_new_bready),
        .s_axi_bresp     (s_axil_new_bresp),
        .s_axi_bvalid    (s_axil_new_bvalid),
        .s_axi_rdata     (s_axil_new_rdata),
        .s_axi_rready    (s_axil_new_rready),
        .s_axi_rresp     (s_axil_new_rresp),
        .s_axi_rvalid    (s_axil_new_rvalid),
        .s_axi_wdata     (s_axil_new_wdata),
        .s_axi_wready    (s_axil_new_wready),
        .s_axi_wstrb     (4'b1111),
        .s_axi_wvalid    (s_axil_new_wvalid)
      );

    end if (i==2) begin       // egress translator

      vitis_net_p4_2 egress_translator_p4 (
        .s_axis_aclk     (axis_aclk),
        .s_axis_aresetn  (axis_aresetn),
        .s_axi_aclk      (axil_aclk),
        .s_axi_aresetn   (axil_aresetn),
        .cam_mem_aclk    (axis_aclk),
        .cam_mem_aresetn (axis_aresetn),

        .s_axis_tdata            (s_axis_qdma_h2c_tdata),
        .s_axis_tkeep            (s_axis_qdma_h2c_tkeep),
        .s_axis_tlast            (s_axis_qdma_h2c_tlast),
        .s_axis_tvalid           (s_axis_qdma_h2c_tvalid),
        .s_axis_tready           (s_axis_qdma_h2c_tready),
        .s_axis_tdest            (1'b0),
        .user_metadata_in        (egress_metadata_in),
        .user_metadata_in_valid  (s_axis_qdma_h2c_tvalid),

        .m_axis_tdata            (axis_egress_tdata),
        .m_axis_tkeep            (axis_egress_tkeep),
        .m_axis_tlast            (axis_egress_tlast),
        .m_axis_tvalid           (axis_egress_tvalid),
        .m_axis_tready           (axis_egress_tready),
        .m_axis_tdest            (axis_egress_tdest),
        .user_metadata_out       (metadata_egress_out),
        .user_metadata_out_valid (metadata_egress_valid),

        .s_axi_araddr    (s_axil_egress_araddr),
        .s_axi_arready   (s_axil_egress_arready),
        .s_axi_arvalid   (s_axil_egress_arvalid),
        .s_axi_awaddr    (s_axil_egress_awaddr),
        .s_axi_awready   (s_axil_egress_awready),
        .s_axi_awvalid   (s_axil_egress_awvalid),
        .s_axi_bready    (s_axil_egress_bready),
        .s_axi_bresp     (s_axil_egress_bresp),
        .s_axi_bvalid    (s_axil_egress_bvalid),
        .s_axi_rdata     (s_axil_egress_rdata),
        .s_axi_rready    (s_axil_egress_rready),
        .s_axi_rresp     (s_axil_egress_rresp),
        .s_axi_rvalid    (s_axil_egress_rvalid),
        .s_axi_wdata     (s_axil_egress_wdata),
        .s_axi_wready    (s_axil_egress_wready),
        .s_axi_wstrb     (4'b1111),
        .s_axi_wvalid    (s_axil_egress_wvalid)
      );

      //pipeline register bewteen egress translator and axis switch
      axis_register_slice_pipeline reg_slice_egress_to_switch (
        .aclk          (axis_aclk),
        .aresetn       (axis_aresetn),
        .s_axis_tdata  (axis_egress_tdata),
        .s_axis_tkeep  (axis_egress_tkeep),
        .s_axis_tlast  (axis_egress_tlast),
        .s_axis_tvalid (axis_egress_tvalid),
        .s_axis_tready (axis_egress_tready),
        .m_axis_tdata  (axis_egress_pipe_tdata),
        .m_axis_tkeep  (axis_egress_pipe_tkeep),
        .m_axis_tlast  (axis_egress_pipe_tlast),
        .m_axis_tvalid (axis_egress_pipe_tvalid),
        .m_axis_tready (axis_egress_pipe_tready)
      );

      // The P4 metadata is only valid on the first beat; hold it for the
      // rest of the packet so tdest/tuser stay constant at the switch.
      logic [58:0] egress_meta_hold;
      wire  [58:0] egress_meta_cur = metadata_egress_valid ? metadata_egress_out : egress_meta_hold;

      always @(posedge axis_aclk or negedge axis_aresetn) begin
        if (!axis_aresetn)
          egress_meta_hold <= 59'b0;
        else if (metadata_egress_valid)
          egress_meta_hold <= metadata_egress_out;
      end

      always @(posedge axis_aclk or negedge axis_aresetn) begin
        if (!axis_aresetn)
          metadata_egress_pipe_out <= 59'b0;
        else if (axis_egress_tvalid && axis_egress_tready)
          metadata_egress_pipe_out <= egress_meta_cur;
      end

    end if (i==3) begin       // egress checksum p4

      vitis_net_p4_3 egress_checksum_p4 (
        .s_axis_aclk     (axis_aclk),
        .s_axis_aresetn  (axis_aresetn),

        .s_axis_tdata            (axis_Checksum_1_tdata),
        .s_axis_tkeep            (axis_Checksum_1_tkeep),
        .s_axis_tlast            (axis_Checksum_1_tlast),
        .s_axis_tvalid           (axis_Checksum_1_tvalid),
        .s_axis_tready           (axis_Checksum_1_tready),
        .user_metadata_in        (metadata_Checksum_1_out),
        .user_metadata_in_valid  (metadata_Checksum_1_valid),

        .m_axis_tdata            (m_axis_adap_tx_250mhz_tdata),
        .m_axis_tkeep            (m_axis_adap_tx_250mhz_tkeep),
        .m_axis_tlast            (m_axis_adap_tx_250mhz_tlast),
        .m_axis_tvalid           (m_axis_adap_tx_250mhz_tvalid),
        .m_axis_tready           (m_axis_adap_tx_250mhz_tready),
        .user_metadata_out       (),
        .user_metadata_out_valid ()
      );

    end
  end
  endgenerate

  // Switch sideband: {payload_offset, tuser_size}. payload_offset is used on
  // M0 by the egress checksum, tuser_size on M1 for the C2H descriptor.
  wire [25:0] egress_switch_tuser_in = {metadata_egress_pipe_out[41:32],
                                        metadata_egress_pipe_out[57:42]};

 //axis switch
  axis_switch_0 axis_switch_inst_0 (
    .aclk          (axis_aclk),
    .aresetn       (axis_aresetn),

    .s_axis_tdata  (axis_egress_pipe_tdata),
    .s_axis_tkeep  (axis_egress_pipe_tkeep),
    .s_axis_tlast  (axis_egress_pipe_tlast),
    .s_axis_tvalid (axis_egress_pipe_tvalid),
    .s_axis_tready (axis_egress_pipe_tready),
    .s_axis_tdest  (metadata_egress_pipe_out[58]),
    .s_axis_tuser  (egress_switch_tuser_in),

    .m_axis_tdata  (egress_switch_1_tdata),
    .m_axis_tkeep  (egress_switch_1_tkeep),
    .m_axis_tlast  (egress_switch_1_tlast),
    .m_axis_tvalid ({axis_switch_1_tvalid, axis_switch_0_tvalid}),
    .m_axis_tready ({axis_switch_1_tready, axis_switch_0_tready}),
    .m_axis_tuser  (egress_switch_1_tuser)
  );

  //pipeline register bewteen axis switch to egress checksum calculator
  axis_register_slice_pipeline reg_slice_switch_to_checksum (
    .aclk          (axis_aclk),
    .aresetn       (axis_aresetn),
    .s_axis_tdata  (axis_switch_0_tdata),
    .s_axis_tkeep  (axis_switch_0_tkeep),
    .s_axis_tlast  (axis_switch_0_tlast),
    .s_axis_tvalid (axis_switch_0_tvalid),
    .s_axis_tready (axis_switch_0_tready),
    .m_axis_tdata  (axis_switch_1_pipe_tdata),
    .m_axis_tkeep  (axis_switch_1_pipe_tkeep),
    .m_axis_tlast  (axis_switch_1_pipe_tlast),
    .m_axis_tvalid (axis_switch_1_pipe_tvalid),
    .m_axis_tready (axis_switch_1_pipe_tready)
  );

  always @(posedge axis_aclk or negedge axis_aresetn) begin
    if (!axis_aresetn) begin
      axis_switch_1_pipe_tuser       <= 10'b0;
      axis_switch_1_pipe_tuser_valid <= 1'b0;
    end else begin
      if (axis_switch_0_tvalid && axis_switch_0_tready) begin
        axis_switch_1_pipe_tuser       <= axis_switch_0_tuser;
        axis_switch_1_pipe_tuser_valid <= axis_switch_0_tvalid;
      end else if (!axis_switch_1_pipe_tvalid || axis_switch_1_pipe_tready) begin
        axis_switch_1_pipe_tuser_valid <= 1'b0;
      end
    end
  end

  //Egress checksum calculator
  calculator_UDP_chksm_egress #(
    .Max_frag_count(25)
  ) chksm_calc_egress_inst (
    .clk                     (axis_aclk),
    .rst                     (axis_aresetn),

    .s_axis_tdata            (axis_switch_1_pipe_tdata),
    .s_axis_tkeep            (axis_switch_1_pipe_tkeep),
    .s_axis_tlast            (axis_switch_1_pipe_tlast),
    .s_axis_tready           (axis_switch_1_pipe_tready),
    .s_axis_tvalid           (axis_switch_1_pipe_tvalid),
    .user_metadata_in        (axis_switch_1_pipe_tuser),
    .user_metadata_in_valid  (axis_switch_1_pipe_tuser_valid),

    .m_axis_tdata            (axis_Checksum_1_tdata),
    .m_axis_tkeep            (axis_Checksum_1_tkeep),
    .m_axis_tlast            (axis_Checksum_1_tlast),
    .m_axis_tready           (axis_Checksum_1_tready),
    .m_axis_tvalid           (axis_Checksum_1_tvalid),
    .user_metadata_out       (metadata_Checksum_1_out),
    .user_metadata_out_valid (metadata_Checksum_1_valid)
  );

  //ingress checksum calculator
  ingress_checksum_calculator #(
    .Max_frag_count(25)
  ) ingress_checksum_calc_inst (
    .clk                     (axis_aclk),
    .rst                     (axis_aresetn),

    .s_axis_tdata            (axis_signal_pipe_tdata),
    .s_axis_tkeep            (axis_signal_pipe_tkeep),
    .s_axis_tlast            (axis_signal_pipe_tlast),
    .s_axis_tready           (axis_signal_pipe_tready),
    .s_axis_tvalid           (axis_signal_pipe_tvalid),
    .user_metadata_in        (metadata_signal_pipe_out),
    .user_metadata_in_valid  (metadata_signal_pipe_valid),

    .m_axis_tdata            (axis_Checksum_0_tdata),
    .m_axis_tkeep            (axis_Checksum_0_tkeep),
    .m_axis_tlast            (axis_Checksum_0_tlast),
    .m_axis_tready           (axis_Checksum_0_tready),
    .m_axis_tvalid           (axis_Checksum_0_tvalid),
    .user_metadata_out       (metadata_Checksum_0_out),
    .user_metadata_out_valid (metadata_Checksum_0_valid)
  );

  //pipeline register between ingress checksum calculator and ingress translator
  axis_register_slice_pipeline reg_slice_checksum_to_translator (
    .aclk          (axis_aclk),
    .aresetn       (axis_aresetn),
    .s_axis_tdata  (axis_Checksum_0_tdata),
    .s_axis_tkeep  (axis_Checksum_0_tkeep),
    .s_axis_tlast  (axis_Checksum_0_tlast),
    .s_axis_tvalid (axis_Checksum_0_tvalid),
    .s_axis_tready (axis_Checksum_0_tready),
    .m_axis_tdata  (axis_Checksum_0_pipe_tdata),
    .m_axis_tkeep  (axis_Checksum_0_pipe_tkeep),
    .m_axis_tlast  (axis_Checksum_0_pipe_tlast),
    .m_axis_tvalid (axis_Checksum_0_pipe_tvalid),
    .m_axis_tready (axis_Checksum_0_pipe_tready)
  );

  always @(posedge axis_aclk or negedge axis_aresetn) begin
    if (!axis_aresetn) begin
      metadata_Checksum_0_pipe_out   <= 39'b0;
      metadata_Checksum_0_pipe_valid <= 1'b0;
    end else begin
      if (axis_Checksum_0_tvalid && axis_Checksum_0_tready) begin
        metadata_Checksum_0_pipe_out   <= metadata_Checksum_0_out;
        metadata_Checksum_0_pipe_valid <= metadata_Checksum_0_valid;
      end else if (!axis_Checksum_0_pipe_tvalid || axis_Checksum_0_pipe_tready) begin
        metadata_Checksum_0_pipe_valid <= 1'b0;
      end
    end
  end

  // tuser_size is taken on the first beat and held until the end of the
  // packet, so every beat into the FIFO carries the packet size.
  logic [15:0] ingress_tuser_size_hold;
  wire  [15:0] ingress_tuser_size = metadata_ingress_valid ? metadata_ingress_out[38:23]
                                                           : ingress_tuser_size_hold;

  always @(posedge axis_aclk or negedge axis_aresetn) begin
    if (!axis_aresetn)
      ingress_tuser_size_hold <= 16'b0;
    else if (metadata_ingress_valid)
      ingress_tuser_size_hold <= metadata_ingress_out[38:23];
  end

  //fifo 0
  axis_data_fifo_0 axis_fifo_0 (
    .s_axis_aclk    (axis_aclk),
    .s_axis_aresetn (axis_aresetn),
    .s_axis_tdata   (axis_ingress_tdata),
    .s_axis_tkeep   (axis_ingress_tkeep),
    .s_axis_tlast   (axis_ingress_tlast),
    .s_axis_tvalid  (axis_ingress_tvalid),
    .s_axis_tready  (axis_ingress_tready),
    .s_axis_tuser   (ingress_tuser_size),
    .m_axis_tdata   (axis_fifo_0_tdata),
    .m_axis_tkeep   (axis_fifo_0_tkeep),
    .m_axis_tlast   (axis_fifo_0_tlast),
    .m_axis_tvalid  (axis_fifo_0_tvalid),
    .m_axis_tready  (axis_fifo_0_tready),
    .m_axis_tuser   (axis_fifo_0_tuser)
  );

  //pipeline register bewteen fifo 0 and arbiter
  axis_register_slice_pipeline #(.TUSER_W(16)) reg_slice_fifo_0 (
    .aclk          (axis_aclk),
    .aresetn       (axis_aresetn),
    .s_axis_tdata  (axis_fifo_0_tdata),
    .s_axis_tkeep  (axis_fifo_0_tkeep),
    .s_axis_tlast  (axis_fifo_0_tlast),
    .s_axis_tvalid (axis_fifo_0_tvalid),
    .s_axis_tready (axis_fifo_0_tready),
    .s_axis_tuser  (axis_fifo_0_tuser),
    .m_axis_tdata  (axis_fifo_0_pipe_tdata),
    .m_axis_tkeep  (axis_fifo_0_pipe_tkeep),
    .m_axis_tlast  (axis_fifo_0_pipe_tlast),
    .m_axis_tvalid (axis_fifo_0_pipe_tvalid),
    .m_axis_tready (axis_fifo_0_pipe_tready),
    .m_axis_tuser  (axis_fifo_0_pipe_tuser)
  );

  //fifo 1
  axis_data_fifo_1 axis_fifo_1 (
    .s_axis_aclk    (axis_aclk),
    .s_axis_aresetn (axis_aresetn),
    .s_axis_tdata   (axis_switch_1_tdata),
    .s_axis_tkeep   (axis_switch_1_tkeep),
    .s_axis_tlast   (axis_switch_1_tlast),
    .s_axis_tvalid  (axis_switch_1_tvalid),
    .s_axis_tready  (axis_switch_1_tready),
    .s_axis_tuser   (axis_switch_1_tuser),
    .m_axis_tdata   (axis_fifo_1_tdata),
    .m_axis_tkeep   (axis_fifo_1_tkeep),
    .m_axis_tlast   (axis_fifo_1_tlast),
    .m_axis_tvalid  (axis_fifo_1_tvalid),
    .m_axis_tready  (axis_fifo_1_tready),
    .m_axis_tuser   (axis_fifo_1_tuser)
  );

  //pipeline register bewteen fifo 1 and arbiter
  axis_register_slice_pipeline #(.TUSER_W(16)) reg_slice_fifo_1 (
    .aclk          (axis_aclk),
    .aresetn       (axis_aresetn),
    .s_axis_tdata  (axis_fifo_1_tdata),
    .s_axis_tkeep  (axis_fifo_1_tkeep),
    .s_axis_tlast  (axis_fifo_1_tlast),
    .s_axis_tvalid (axis_fifo_1_tvalid),
    .s_axis_tready (axis_fifo_1_tready),
    .s_axis_tuser  (axis_fifo_1_tuser),
    .m_axis_tdata  (axis_fifo_1_pipe_tdata),
    .m_axis_tkeep  (axis_fifo_1_pipe_tkeep),
    .m_axis_tlast  (axis_fifo_1_pipe_tlast),
    .m_axis_tvalid (axis_fifo_1_pipe_tvalid),
    .m_axis_tready (axis_fifo_1_pipe_tready),
    .m_axis_tuser  (axis_fifo_1_pipe_tuser)
  );

  //axis arbiter
  axi_stream_arbiter arbiter_inst (
    .clk           (axis_aclk),
    .rst_n         (axis_aresetn),

    .s_axis_tdata  ({axis_fifo_1_pipe_tdata,  axis_fifo_0_pipe_tdata}),
    .s_axis_tkeep  ({axis_fifo_1_pipe_tkeep,  axis_fifo_0_pipe_tkeep}),
    .s_axis_tvalid ({axis_fifo_1_pipe_tvalid, axis_fifo_0_pipe_tvalid}),
    .s_axis_tready ({axis_fifo_1_pipe_tready, axis_fifo_0_pipe_tready}),
    .s_axis_tlast  ({axis_fifo_1_pipe_tlast,  axis_fifo_0_pipe_tlast}),
    .s_axis_tuser  ({axis_fifo_1_pipe_tuser,  axis_fifo_0_pipe_tuser}),

    .m_axis_tdata  (m_axis_arbiter_pipe_tdata),
    .m_axis_tkeep  (m_axis_arbiter_pipe_tkeep),
    .m_axis_tvalid (m_axis_arbiter_pipe_tvalid),
    .m_axis_tready (m_axis_arbiter_pipe_tready),
    .m_axis_tlast  (m_axis_arbiter_pipe_tlast),
    .m_axis_tuser  (m_axis_arbiter_pipe_tuser)
  );

  //pipeline register bewteen arbiter and qdma
  axis_register_slice_pipeline #(.TUSER_W(16)) reg_slice_arbiter_to_qdma (
    .aclk          (axis_aclk),
    .aresetn       (axis_aresetn),
    .s_axis_tdata  (m_axis_arbiter_pipe_tdata),
    .s_axis_tkeep  (m_axis_arbiter_pipe_tkeep),
    .s_axis_tlast  (m_axis_arbiter_pipe_tlast),
    .s_axis_tvalid (m_axis_arbiter_pipe_tvalid),
    .s_axis_tready (m_axis_arbiter_pipe_tready),
    .s_axis_tuser  (m_axis_arbiter_pipe_tuser),
    .m_axis_tdata  (m_axis_qdma_c2h_tdata),
    .m_axis_tkeep  (m_axis_qdma_c2h_tkeep),
    .m_axis_tlast  (m_axis_qdma_c2h_tlast),
    .m_axis_tvalid (m_axis_qdma_c2h_tvalid),
    .m_axis_tready (m_axis_qdma_c2h_tready),
    .m_axis_tuser  (m_axis_qdma_c2h_tuser_size)
  );

endmodule: p2p_250mhz


// Single-stage AXI-Stream register slice.
module axis_register_slice_pipeline #(
  parameter int TUSER_W = 1
) (
  input  wire               aclk,
  input  wire               aresetn,

  input  wire [511:0]       s_axis_tdata,
  input  wire [63:0]        s_axis_tkeep,
  input  wire               s_axis_tlast,
  input  wire               s_axis_tvalid,
  input  wire [TUSER_W-1:0] s_axis_tuser,
  output wire               s_axis_tready,

  output wire [511:0]       m_axis_tdata,
  output wire [63:0]        m_axis_tkeep,
  output wire               m_axis_tlast,
  output wire               m_axis_tvalid,
  output wire [TUSER_W-1:0] m_axis_tuser,
  input  wire               m_axis_tready
);

  reg [511:0]       tdata_reg;
  reg [63:0]        tkeep_reg;
  reg               tlast_reg;
  reg [TUSER_W-1:0] tuser_reg;
  reg               valid_reg;

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      tdata_reg <= 512'b0;
      tkeep_reg <= 64'b0;
      tlast_reg <= 1'b0;
      tuser_reg <= '0;
      valid_reg <= 1'b0;
    end else if (s_axis_tready) begin
      tdata_reg <= s_axis_tdata;
      tkeep_reg <= s_axis_tkeep;
      tlast_reg <= s_axis_tlast;
      tuser_reg <= s_axis_tuser;
      valid_reg <= s_axis_tvalid;
    end
  end

  assign s_axis_tready = !valid_reg || m_axis_tready;

  assign m_axis_tdata  = tdata_reg;
  assign m_axis_tkeep  = tkeep_reg;
  assign m_axis_tlast  = tlast_reg;
  assign m_axis_tuser  = tuser_reg;
  assign m_axis_tvalid = valid_reg;

endmodule
