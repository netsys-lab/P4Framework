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
`include "open_nic_shell_macros.vh"
`timescale 1ns/1ps
module p2p_250mhz #(
  parameter int NUM_INTF = 4
) (

//axi lite input from crossbar to vitis ip 1:ingress classifier
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


  //axi lite input from crossbar to vitis ip 2:ingress translator
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

  //axi lite input from crossbar to vitis ip 3:egress translator
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

  //output from QDMA to egress translator
  input                s_axis_qdma_h2c_tvalid,
  input  [511:0]       s_axis_qdma_h2c_tdata,
  input   [63:0]       s_axis_qdma_h2c_tkeep,
  input                s_axis_qdma_h2c_tlast,
  input   [15:0]       s_axis_qdma_h2c_tuser_size,
  input   [15:0]       s_axis_qdma_h2c_tuser_src,
  input   [15:0]       s_axis_qdma_h2c_tuser_dst,
  output               s_axis_qdma_h2c_tready,

  //output from axi stream axi arbeiter input to QDMA
  output               m_axis_qdma_c2h_tvalid,
  output [511:0]       m_axis_qdma_c2h_tdata,
  output  [63:0]       m_axis_qdma_c2h_tkeep,
  output               m_axis_qdma_c2h_tlast,
  //output  [15:0]       m_axis_qdma_c2h_tuser_size,
  //output  [15:0]       m_axis_qdma_c2h_tuser_src,
  //output  [15:0]       m_axis_qdma_c2h_tuser_dst,
  input                m_axis_qdma_c2h_tready,

  //output from axi_stream_pipeline to packet adapter
  output               m_axis_adap_tx_250mhz_tvalid,
  output [511:0]       m_axis_adap_tx_250mhz_tdata,
  output  [63:0]       m_axis_adap_tx_250mhz_tkeep,
  output               m_axis_adap_tx_250mhz_tlast,
  //output  [15:0]       m_axis_adap_tx_250mhz_tuser_size,
  //output  [15:0]       m_axis_adap_tx_250mhz_tuser_src,
  //output  [15:0]       m_axis_adap_tx_250mhz_tuser_dst,
  input                m_axis_adap_tx_250mhz_tready,

  //input from packet adapter to ingress classifier ip
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

  // Reset signals with proper synchronization
  wire axil_aresetn; // Reset is clocked by the 125MHz AXI-Lite clock
  wire axis_aresetn; // Reset is clocked by the 250MHz AXI-Lite clock

  // RESTORED: Proper reset synchronization
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

  // REMOVED: Simple reset assignments
  // assign axil_aresetn = mod_rstn;
  // assign axis_aresetn = mod_rstn;

  wire [32:0] ingress_metadata_in;
  wire [58:0] egress_metadata_in;

  //output from ingress classifier- input to ingress checksum calculator
  wire [511:0] axis_signal_tdata;
  wire [63:0]  axis_signal_tkeep;
  wire         axis_signal_tlast;
  wire         axis_signal_tvalid;
  wire         axis_signal_tready;
  wire [63:0]  axis_signal_tuser;
  wire [32:0]  metadata_signal_out;   //bit 0: is_scion, [6:1] hop fields, [16:7] payload offset
  wire         metadata_signal_valid;

  // ADDED: Pipeline registers between classifier and checksum calculator
  wire [511:0] axis_signal_pipe_tdata;
  wire [63:0]  axis_signal_pipe_tkeep;
  wire         axis_signal_pipe_tlast;
  wire         axis_signal_pipe_tvalid;
  wire         axis_signal_pipe_tready;
  logic [32:0]  metadata_signal_pipe_out;
  logic         metadata_signal_pipe_valid;

  //output from ingress checksum calculator instance 0- input to ingress translator
  wire [511:0] axis_Checksum_0_tdata;
  wire [63:0]  axis_Checksum_0_tkeep;
  wire         axis_Checksum_0_tlast;
  wire         axis_Checksum_0_tvalid;
  wire         axis_Checksum_0_tready;
  wire [22:0]  metadata_Checksum_0_out;  //bit 0: is_scion, [6:1] hop fields, [22:7] udp checksum
  wire         metadata_Checksum_0_valid;

  // ADDED: Pipeline registers between checksum calculator and ingress translator
  wire [511:0] axis_Checksum_0_pipe_tdata;
  wire [63:0]  axis_Checksum_0_pipe_tkeep;
  wire         axis_Checksum_0_pipe_tlast;
  wire         axis_Checksum_0_pipe_tvalid;
  wire         axis_Checksum_0_pipe_tready;
  logic [22:0]  metadata_Checksum_0_pipe_out;
  logic         metadata_Checksum_0_pipe_valid;

  //output from ingress translator- input to axi stream switch 1(slave 1-higher priority)
  wire [511:0] axis_ingress_tdata;
  wire [63:0]  axis_ingress_tkeep;
  wire         axis_ingress_tlast;
  wire         axis_ingress_tvalid;
  wire         axis_ingress_tready;

  //output from egress translator- input to  axis stream switch 0
  wire [511:0] axis_egress_tdata;
  wire [63:0]  axis_egress_tkeep;
  wire         axis_egress_tlast;
  wire         axis_egress_tvalid;
  wire         axis_egress_tready;
  wire         axis_egress_tdest;
  wire [10:0]  axis_egress_tuser;
  wire [58:0]  metadata_egress_out;
  wire         metadata_egress_valid;

  // ADDED: Pipeline registers between egress translator and axis switch
  wire [511:0] axis_egress_pipe_tdata;
  wire [63:0]  axis_egress_pipe_tkeep;
  wire         axis_egress_pipe_tlast;
  wire         axis_egress_pipe_tvalid;
  wire         axis_egress_pipe_tready;
  wire         axis_egress_pipe_tdest;
  wire [10:0]  axis_egress_pipe_tuser;
  logic [58:0]  metadata_egress_pipe_out;
  logic         metadata_egress_pipe_valid;

  //output from egress checksum calculator - input to vitis checksum IP
  wire [511:0] axis_Checksum_1_tdata;
  wire [63:0]  axis_Checksum_1_tkeep;
  wire         axis_Checksum_1_tlast;
  wire         axis_Checksum_1_tvalid;
  wire         axis_Checksum_1_tready;
  wire [16:0]  metadata_Checksum_1_out;
  wire         metadata_Checksum_1_valid;

  // ADDED: Pipeline registers between axis switch and egress checksum calculator
  wire [511:0] axis_switch_1_pipe_tdata;
  wire [63:0]  axis_switch_1_pipe_tkeep;
  wire         axis_switch_1_pipe_tlast;
  wire         axis_switch_1_pipe_tvalid;
  wire         axis_switch_1_pipe_tready;
  logic [26:0]  axis_switch_1_pipe_tuser;
  logic         axis_switch_1_pipe_tuser_valid;

//     //output from to axi stream switch 0
  wire [1023:0]   egress_switch_1_tdata;
  wire [127:0]    egress_switch_1_tkeep;
  wire [1:0]      egress_switch_1_tlast;
  wire [1:0]      egress_switch_1_tvalid;
  wire [1:0]      egress_switch_1_tready;
  wire [53:0]     egress_switch_1_tuser;

//     //input to to axi stream switch 1
  wire [1023:0]   ingress_switch_0_tdata;
  wire [127:0]    ingress_switch_0_tkeep;
  wire [1:0]      ingress_switch_0_tlast;
  wire [1:0]      ingress_switch_0_tvalid;
  wire [1:0]      ingress_switch_0_tready;

  //  output from fifo 0
  wire [511:0]   axis_fifo_0_tdata;
  wire [63:0]    axis_fifo_0_tkeep;
  wire           axis_fifo_0_tlast;
  wire           axis_fifo_0_tvalid;
  wire           axis_fifo_0_tready;

  //  output from fifo 0
  wire [511:0]   axis_fifo_1_tdata;
  wire [63:0]    axis_fifo_1_tkeep;
  wire           axis_fifo_1_tlast;
  wire           axis_fifo_1_tvalid;
  wire           axis_fifo_1_tready;

  // ADDED: Pipeline registers after FIFO outputs
  wire [511:0]   axis_fifo_0_pipe_tdata;
  wire [63:0]    axis_fifo_0_pipe_tkeep;
  wire           axis_fifo_0_pipe_tlast;
  wire           axis_fifo_0_pipe_tvalid;
  wire           axis_fifo_0_pipe_tready;

  wire [511:0]   axis_fifo_1_pipe_tdata;
  wire [63:0]    axis_fifo_1_pipe_tkeep;
  wire           axis_fifo_1_pipe_tlast;
  wire           axis_fifo_1_pipe_tvalid;
  wire           axis_fifo_1_pipe_tready;

  //output from axi stream switch 0 to axi stream switch 1(slave 2-lower priority)
  wire [511:0] axis_switch_0_tdata;
  wire [63:0]  axis_switch_0_tkeep;
  wire         axis_switch_0_tlast;
  wire         axis_switch_0_tvalid;
  wire         axis_switch_0_tready;
  wire [26:0]  axis_switch_0_tuser;


  //output from axi stream switch 0 to egress checksum calculator
  wire [511:0] axis_switch_1_tdata;
  wire [63:0]  axis_switch_1_tkeep;
  wire         axis_switch_1_tlast;
  wire         axis_switch_1_tvalid;
  wire         axis_switch_1_tready;
  wire [26:0]  axis_switch_1_tuser;


  //output from axi stream pipeline
  wire [511:0] m_axis_pipeline_tdata;
  wire [63:0]  m_axis_pipeline_tkeep;
  wire         m_axis_pipeline_tlast;
  wire         m_axis_pipeline_tvalid;
  wire         m_axis_pipeline_tready;
  wire [10:0]  m_axis_pipeline_tuser;

  // ADDED: Pipeline registers after arbiter
  wire [511:0] m_axis_arbiter_pipe_tdata;
  wire [63:0]  m_axis_arbiter_pipe_tkeep;
  wire         m_axis_arbiter_pipe_tlast;
  wire         m_axis_arbiter_pipe_tvalid;
  wire         m_axis_arbiter_pipe_tready;

  //wire [63:0]  qdma_tkeep_in;

  //assign m_axis_qdma_c2h_tkeep    =   qdma_tkeep_in ;  //debug

  //    //output from axi stream switch 0 - input to FiFO(AXI arbeiter)
  assign axis_switch_0_tdata    =   egress_switch_1_tdata[511:0];
  assign axis_switch_0_tkeep    =   egress_switch_1_tkeep[63:0];
  assign axis_switch_0_tlast    =   egress_switch_1_tlast[0:0];
  assign axis_switch_0_tvalid   =   egress_switch_1_tvalid[0:0];
  assign axis_switch_0_tready   =   egress_switch_1_tready[0:0];
  assign axis_switch_0_tuser    =   egress_switch_1_tuser[26:0];

  //output from axi stream switch 0 - input to egress checksum calculator
  assign axis_switch_1_tdata  =   egress_switch_1_tdata[1023:512];
  assign axis_switch_1_tkeep  =   egress_switch_1_tkeep[127:64];
  assign axis_switch_1_tlast  =   egress_switch_1_tlast[1:1];
  assign axis_switch_1_tvalid =   egress_switch_1_tvalid[1:1];
  assign axis_switch_1_tready =   egress_switch_1_tready[1:1];
  assign axis_switch_1_tuser  =   egress_switch_1_tuser[53:27];

  //input to axi stream switch 1
//    assign ingress_switch_0_tdata[511:0]   =    axis_ingress_tdata;
//    assign ingress_switch_0_tkeep[63:0]    =    axis_ingress_tkeep;
//    assign ingress_switch_0_tlast[0:0]     =    axis_ingress_tlast;
//    assign ingress_switch_0_tvalid[0:0]    =    axis_ingress_tvalid;
//    assign ingress_switch_0_tready[0:0]    =    axis_ingress_tready;

//    assign ingress_switch_0_tdata[1023:512]   =    axis_switch_0_tdata;
//    assign ingress_switch_0_tkeep[127:64]     =    axis_switch_0_tkeep;
//    assign ingress_switch_0_tlast[1:1]        =    axis_switch_0_tlast;
//    assign ingress_switch_0_tvalid[1:1]       =    axis_switch_0_tvalid;
//    assign ingress_switch_0_tready[1:1]       =    axis_switch_0_tready;

  assign ingress_metadata_in = {17'b0, s_axis_adap_rx_250mhz_tuser_size};
  assign egress_metadata_in  = {s_axis_qdma_h2c_tuser_dst, s_axis_qdma_h2c_tuser_src, 10'b0, s_axis_qdma_h2c_tuser_size, 1'b0};  //58 bits

  generate for (genvar i = 0; i < NUM_INTF; i++) begin

    if (i==0) begin     //vitis ip instance 0: ingress classifier
      vitis_net_p4_0 ingress_classifier_p4 (
        .s_axis_aclk     (axis_aclk),                                   // input wire s_axis_aclk
        .s_axis_aresetn  (axis_aresetn),                                // input wire s_axis_aresetn
        .s_axi_aclk      (axil_aclk),                                   // input wire s_axi_aclk
        .s_axi_aresetn   (axil_aresetn),                                // input wire s_axi_aresetn
        .cam_mem_aclk    (axis_aclk),                                   // input wire cam_mem_aclk
        .cam_mem_aresetn (axis_aresetn),                                // input wire cam_mem_aresetn

        .s_axis_tdata    (s_axis_adap_rx_250mhz_tdata),                 // input wire [511 : 0] s_axis_tdata
        .s_axis_tkeep    (s_axis_adap_rx_250mhz_tkeep),                 // input wire [63 : 0] s_axis_tkeep
        .s_axis_tlast    (s_axis_adap_rx_250mhz_tlast),                 // input wire s_axis_tlast
        .s_axis_tvalid   (s_axis_adap_rx_250mhz_tvalid),                // input wire s_axis_tvalid
        .s_axis_tready   (s_axis_adap_rx_250mhz_tready),                // output wire s_axis_tready
        .user_metadata_in (ingress_metadata_in),            // input wire [15 : 0] user_metadata_in
        .user_metadata_in_valid (s_axis_adap_rx_250mhz_tvalid),          // input wire user_metadata_in_valid

        .m_axis_tdata            (axis_signal_tdata),                    // output wire [511 : 0] m_axis_tdata to checksum calculator
        .m_axis_tkeep            (axis_signal_tkeep),                    // output wire [63 : 0] m_axis_tkeep to checksum calculator
        .m_axis_tlast            (axis_signal_tlast),                    // output wire m_axis_tlast to checksum calculator
        .m_axis_tvalid           (axis_signal_tvalid),                   // output wire m_axis_tvalid to checksum calculator
        .m_axis_tready           (axis_signal_tready),                   // input wire m_axis_tready from checksum calculator
        .user_metadata_out       (metadata_signal_out),
        .user_metadata_out_valid (metadata_signal_valid),

        .s_axi_araddr    (s_axil_araddr),                                // input wire [12 : 0] s_axi_araddr
        .s_axi_arready   (s_axil_arready),                               // output wire s_axi_arready
        .s_axi_arvalid   (s_axil_arvalid),                               // input wire s_axi_arvalid
        .s_axi_awaddr    (s_axil_awaddr),                                // input wire [12 : 0] s_axi_awaddr
        .s_axi_awready   (s_axil_awready),                               // output wire s_axi_awready
        .s_axi_awvalid   (s_axil_awvalid),                               // input wire s_axi_awvalid
        .s_axi_bready    (s_axil_bready),                                // input wire s_axi_bready
        .s_axi_bresp     (s_axil_bresp),                                 // output wire [1 : 0] s_axi_bresp
        .s_axi_bvalid    (s_axil_bvalid),                                // output wire s_axi_bvalid
        .s_axi_rdata     (s_axil_rdata),                                 // output wire [31 : 0] s_axi_rdata
        .s_axi_rready    (s_axil_rready),                                // input wire s_axi_rready
        .s_axi_rresp     (s_axil_rresp),                                 // output wire [1 : 0] s_axi_rresp
        .s_axi_rvalid    (s_axil_rvalid),                                // output wire s_axi_rvalid
        .s_axi_wdata     (s_axil_wdata),                                 // input wire [31 : 0] s_axi_wdata
        .s_axi_wready    (s_axil_wready),                                // output wire s_axi_wready
        .s_axi_wstrb     (4'b1111),                                      // input wire [3 : 0] s_axi_wstrb
        .s_axi_wvalid    (s_axil_wvalid)                                 // input wire s_axi_wvalid
      );

      // ADDED: Pipeline register after ingress classifier
      axis_register_slice_pipeline reg_slice_classifier_to_checksum (
        .aclk(axis_aclk),
        .aresetn(axis_aresetn),

        // Input from classifier
        .s_axis_tdata(axis_signal_tdata),
        .s_axis_tkeep(axis_signal_tkeep),
        .s_axis_tlast(axis_signal_tlast),
        .s_axis_tvalid(axis_signal_tvalid),
        .s_axis_tready(axis_signal_tready),

        // Output to checksum calculator
        .m_axis_tdata(axis_signal_pipe_tdata),
        .m_axis_tkeep(axis_signal_pipe_tkeep),
        .m_axis_tlast(axis_signal_pipe_tlast),
        .m_axis_tvalid(axis_signal_pipe_tvalid),
        .m_axis_tready(axis_signal_pipe_tready)
      );

      // ADDED: Simple register for metadata
      always @(posedge axis_aclk or negedge axis_aresetn) begin
        if (!axis_aresetn) begin
          metadata_signal_pipe_out <= 33'b0;
          metadata_signal_pipe_valid <= 1'b0;
        end else begin
          if (axis_signal_tvalid && axis_signal_tready) begin
            metadata_signal_pipe_out <= metadata_signal_out;
            metadata_signal_pipe_valid <= metadata_signal_valid;
          end else if (!axis_signal_pipe_tvalid || axis_signal_pipe_tready) begin
            metadata_signal_pipe_valid <= 1'b0;
          end
        end
      end

    end if (i==1) begin       //vitis ip instance 1:ingress translator

      vitis_net_p4_1 ingress_translator_p4 (
        .s_axis_aclk     (axis_aclk),                                   // input wire s_axis_aclk
        .s_axis_aresetn  (axis_aresetn),                                // input wire s_axis_aresetn
        .s_axi_aclk      (axil_aclk),                                   // input wire s_axi_aclk
        .s_axi_aresetn   (axil_aresetn),                                // input wire s_axi_aresetn
        .cam_mem_aclk    (axis_aclk),                                   // input wire cam_mem_aclk
        .cam_mem_aresetn (axis_aresetn),                                // input wire cam_mem_aresetn

        .s_axis_tdata           (axis_Checksum_0_pipe_tdata),           // input wire [511 : 0] s_axis_tdata
        .s_axis_tkeep           (axis_Checksum_0_pipe_tkeep),           // input wire [63 : 0] s_axis_tkeep
        .s_axis_tlast           (axis_Checksum_0_pipe_tlast),           // input wire s_axis_tlast
        .s_axis_tvalid          (axis_Checksum_0_pipe_tvalid),          // input wire s_axis_tvalid
        .s_axis_tready          (axis_Checksum_0_pipe_tready),          // output wire s_axis_tready
        .user_metadata_in       (metadata_Checksum_0_pipe_out),         // packet size
        .user_metadata_in_valid (metadata_Checksum_0_pipe_valid),       // input wire user_metadata_in_valid

        .m_axis_tdata    (axis_ingress_tdata),                         // output wire [511 : 0] m_axis_tdata
        .m_axis_tkeep    (axis_ingress_tkeep),                         // output wire [63 : 0] m_axis_tkeep
        .m_axis_tlast    (axis_ingress_tlast),                         // output wire m_axis_tlast
        .m_axis_tvalid   (axis_ingress_tvalid),                        // output wire m_axis_tvalid
        .m_axis_tready   (axis_ingress_tready),                        // input wire m_axis_tready
        .user_metadata_out(),                                         // output wire [47 : 0] user_metadata_out
        .user_metadata_out_valid(),                                   // output wire user_metadata_out_valid

        .s_axi_araddr    (s_axil_new_araddr),                         // input wire [12 : 0] s_axi_araddr
        .s_axi_arready   (s_axil_new_arready),                        // output wire s_axi_arready
        .s_axi_arvalid   (s_axil_new_arvalid),                        // input wire s_axi_arvalid
        .s_axi_awaddr    (s_axil_new_awaddr),                         // input wire [12 : 0] s_axi_awaddr
        .s_axi_awready   (s_axil_new_awready),                        // output wire s_axi_awready
        .s_axi_awvalid   (s_axil_new_awvalid),                        // input wire s_axi_awvalid
        .s_axi_bready    (s_axil_new_bready),                         // input wire s_axi_bready
        .s_axi_bresp     (s_axil_new_bresp),                          // output wire [1 : 0] s_axi_bresp
        .s_axi_bvalid    (s_axil_new_bvalid),                         // output wire s_axi_bvalid
        .s_axi_rdata     (s_axil_new_rdata),                          // output wire [31 : 0] s_axi_rdata
        .s_axi_rready    (s_axil_new_rready),                         // input wire s_axi_rready
        .s_axi_rresp     (s_axil_new_rresp),                          // output wire [1 : 0] s_axi_rresp
        .s_axi_rvalid    (s_axil_new_rvalid),                         // output wire s_axi_rvalid
        .s_axi_wdata     (s_axil_new_wdata),                          // input wire [31 : 0] s_axi_wdata
        .s_axi_wready    (s_axil_new_wready),                         // output wire s_axi_wready
        .s_axi_wstrb     (4'b1111),                                   // input wire [3 : 0] s_axi_wstrb
        .s_axi_wvalid    (s_axil_new_wvalid)                          // input wire s_axi_wvalid
      );

      end if (i==2) begin                                             //vitis ip instance 2: egress translaor

      vitis_net_p4_2 egress_translator_p4 (
        .s_axis_aclk     (axis_aclk),                                 // input wire s_axis_aclk
        .s_axis_aresetn  (axis_aresetn),                              // input wire s_axis_aresetn
        .s_axi_aclk      (axil_aclk),                                 // input wire s_axi_aclk
        .s_axi_aresetn   (axil_aresetn),                              // input wire s_axi_aresetn
        .cam_mem_aclk    (axis_aclk),                                 // input wire cam_mem_aclk
        .cam_mem_aresetn (axis_aresetn),                              // input wire cam_mem_aresetn

        .s_axis_tdata    (s_axis_qdma_h2c_tdata),                       // input wire [511 : 0] s_axis_tdata
        .s_axis_tkeep    (s_axis_qdma_h2c_tkeep),                       // input wire [63 : 0] s_axis_tkeep
        .s_axis_tlast    (s_axis_qdma_h2c_tlast),                       // input wire s_axis_tlast
        .s_axis_tvalid   (s_axis_qdma_h2c_tvalid),                      // input wire s_axis_tvalid
        .s_axis_tready   (s_axis_qdma_h2c_tready),                      // output wire s_axis_tready
        .user_metadata_in (egress_metadata_in),
        .s_axis_tdest      (1'b0),
        .user_metadata_in_valid(s_axis_qdma_h2c_tvalid),       // input wire user_metadata_in_valid

        .m_axis_tdata      (axis_egress_tdata),                       // output wire [511 : 0] m_axis_tdata
        .m_axis_tkeep      (axis_egress_tkeep),                       // output wire [63 : 0] m_axis_tkeep
        .m_axis_tlast      (axis_egress_tlast),                       // output wire m_axis_tlast
        .m_axis_tvalid     (axis_egress_tvalid),                      // output wire m_axis_tvalid
        .m_axis_tready     (axis_egress_tready),                      // input wire m_axis_tready
        .m_axis_tdest      (axis_egress_tdest),
        .user_metadata_out (metadata_egress_out),
        //.user_metadata_out_valid (metadata_valid_egress),

        .s_axi_araddr    (s_axil_egress_araddr),                      // input wire [12 : 0] s_axi_araddr
        .s_axi_arready   (s_axil_egress_arready),                     // output wire s_axi_arready
        .s_axi_arvalid   (s_axil_egress_arvalid),                     // input wire s_axi_arvalid
        .s_axi_awaddr    (s_axil_egress_awaddr),                      // input wire [12 : 0] s_axi_awaddr
        .s_axi_awready   (s_axil_egress_awready),                     // output wire s_axi_awready
        .s_axi_awvalid   (s_axil_egress_awvalid),                     // input wire s_axi_awvalid
        .s_axi_bready    (s_axil_egress_bready),                      // input wire s_axi_bready
        .s_axi_bresp     (s_axil_egress_bresp),                       // output wire [1 : 0] s_axi_bresp
        .s_axi_bvalid    (s_axil_egress_bvalid),                      // output wire s_axi_bvalid
        .s_axi_rdata     (s_axil_egress_rdata),                       // output wire [31 : 0] s_axi_rdata
        .s_axi_rready    (s_axil_egress_rready),                      // input wire s_axi_rready
        .s_axi_rresp     (s_axil_egress_rresp),                       // output wire [1 : 0] s_axi_rresp
        .s_axi_rvalid    (s_axil_egress_rvalid),                      // output wire s_axi_rvalid
        .s_axi_wdata     (s_axil_egress_wdata),                       // input wire [31 : 0] s_axi_wdata
        .s_axi_wready    (s_axil_egress_wready),                      // output wire s_axi_wready
        .s_axi_wstrb     (4'b1111),                                   // input wire [3 : 0] s_axi_wstrb
        .s_axi_wvalid    (s_axil_egress_wvalid)                       // input wire s_axi_wvalid
      );

      // ADDED: Pipeline register after egress translator
      axis_register_slice_pipeline reg_slice_egress_to_switch (
        .aclk(axis_aclk),
        .aresetn(axis_aresetn),

        // Input from egress translator
        .s_axis_tdata(axis_egress_tdata),
        .s_axis_tkeep(axis_egress_tkeep),
        .s_axis_tlast(axis_egress_tlast),
        .s_axis_tvalid(axis_egress_tvalid),
        .s_axis_tready(axis_egress_tready),
        .s_axis_tdest(axis_egress_tdest),

        // Output to axis switch
        .m_axis_tdata(axis_egress_pipe_tdata),
        .m_axis_tkeep(axis_egress_pipe_tkeep),
        .m_axis_tlast(axis_egress_pipe_tlast),
        .m_axis_tvalid(axis_egress_pipe_tvalid),
        .m_axis_tready(axis_egress_pipe_tready),
        .m_axis_tdest(axis_egress_pipe_tdest)
      );

      // ADDED: Simple register for metadata
      always @(posedge axis_aclk or negedge axis_aresetn) begin
        if (!axis_aresetn) begin
          metadata_egress_pipe_out <= 59'b0;
          metadata_egress_pipe_valid <= 1'b0;
        end else begin
          if (axis_egress_tvalid && axis_egress_tready) begin
            metadata_egress_pipe_out <= metadata_egress_out;
            metadata_egress_pipe_valid <= axis_egress_tvalid;
          end else if (!axis_egress_pipe_tvalid || axis_egress_pipe_tready) begin
            metadata_egress_pipe_valid <= 1'b0;
          end
        end
      end

      end if (i==3) begin                                            //vitis ip instance 3: egress checksum

      vitis_net_p4_3 egress_checksum_p4 (
        .s_axis_aclk     (axis_aclk),                               // input wire s_axis_aclk
        .s_axis_aresetn  (axis_aresetn),                            // input wire s_axis_aresetn

        .s_axis_tdata           (axis_Checksum_1_tdata),            // input wire [511 : 0] s_axis_tdata
        .s_axis_tkeep           (axis_Checksum_1_tkeep),            // input wire [63 : 0] s_axis_tkeep
        .s_axis_tlast           (axis_Checksum_1_tlast),            // input wire s_axis_tlast
        .s_axis_tvalid          (axis_Checksum_1_tvalid),           // input wire s_axis_tvalid
        .s_axis_tready          (axis_Checksum_1_tready),           // output wire s_axis_tready
        .user_metadata_in       (metadata_Checksum_1_out),
        .user_metadata_in_valid (metadata_Checksum_1_valid),

        .m_axis_tdata    (m_axis_adap_tx_250mhz_tdata),             // output wire [511 : 0] m_axis_tdata
        .m_axis_tkeep    (m_axis_adap_tx_250mhz_tkeep),             // output wire [63 : 0] m_axis_tkeep
        .m_axis_tlast    (m_axis_adap_tx_250mhz_tlast),             // output wire m_axis_tlast
        .m_axis_tvalid   (m_axis_adap_tx_250mhz_tvalid),            // output wire m_axis_tvalid
        .m_axis_tready   (m_axis_adap_tx_250mhz_tready),             // input wire m_axis_tready
        .user_metadata_out(),                                       // output wire metadata out
        .user_metadata_out_valid()                                 // output wire user_metadata_out_valid

      );

    end
  end
  endgenerate


  //axi stream switch instances

  axis_switch_0 axis_switch_inst_0(
    .aclk     (axis_aclk),
    .aresetn  (axis_aresetn),

    .s_axis_tdata  (axis_egress_pipe_tdata),
    .s_axis_tkeep  (axis_egress_pipe_tkeep),
    .s_axis_tlast  (axis_egress_pipe_tlast),
    .s_axis_tvalid (axis_egress_pipe_tvalid),
    .s_axis_tready (axis_egress_pipe_tready),
    .s_axis_tdest  (axis_egress_pipe_tdest),
    .s_axis_tuser  (metadata_egress_pipe_out[26:0]),

    .m_axis_tdata  (egress_switch_1_tdata  ),
    .m_axis_tkeep  (egress_switch_1_tkeep  ),
    .m_axis_tlast  (egress_switch_1_tlast  ),
    .m_axis_tvalid ({axis_switch_1_tvalid, axis_switch_0_tvalid} ),
    .m_axis_tready ({axis_switch_1_tready, axis_switch_0_tready} ),
    .m_axis_tuser  (egress_switch_1_tuser  )
  );

  // ADDED: Pipeline register after axis switch output
  axis_register_slice_pipeline reg_slice_switch_to_checksum (
    .aclk(axis_aclk),
    .aresetn(axis_aresetn),

    // Input from axis switch
    .s_axis_tdata(axis_switch_0_tdata),
    .s_axis_tkeep(axis_switch_0_tkeep),
    .s_axis_tlast(axis_switch_0_tlast),
    .s_axis_tvalid(axis_switch_0_tvalid),
    .s_axis_tready(axis_switch_0_tready),

    // Output to checksum calculator
    .m_axis_tdata(axis_switch_1_pipe_tdata),
    .m_axis_tkeep(axis_switch_1_pipe_tkeep),
    .m_axis_tlast(axis_switch_1_pipe_tlast),
    .m_axis_tvalid(axis_switch_1_pipe_tvalid),
    .m_axis_tready(axis_switch_1_pipe_tready)
  );

  // ADDED: Simple register for tuser
  always @(posedge axis_aclk or negedge axis_aresetn) begin
    if (!axis_aresetn) begin
      axis_switch_1_pipe_tuser <= 27'b0;
      axis_switch_1_pipe_tuser_valid <= 1'b0;
    end else begin
      if (axis_switch_0_tvalid && axis_switch_0_tready) begin
        axis_switch_1_pipe_tuser <= axis_switch_0_tuser;
        axis_switch_1_pipe_tuser_valid <= axis_switch_0_tvalid;
      end else if (!axis_switch_1_pipe_tvalid || axis_switch_1_pipe_tready) begin
        axis_switch_1_pipe_tuser_valid <= 1'b0;
      end
    end
  end

  //generate UDP checksum calculator IPs

  calculator_UDP_chksm_egress#(
    .Max_frag_count(25)
  ) chksm_calc_egress_inst (       //UDP checksum calculator instance at egress

    .s_axis_tdata        (axis_switch_1_pipe_tdata ),              //tdata input from ingress classifier
    .s_axis_tkeep        (axis_switch_1_pipe_tkeep ),              //tkeep input from ingress classifier
    .s_axis_tlast        (axis_switch_1_pipe_tlast ),              //tlast input from ingress classifier
    .s_axis_tready       (axis_switch_1_pipe_tready),             //tready input from ingress classifier
    .s_axis_tvalid       (axis_switch_1_pipe_tvalid ),             //tvalid input from ingress classifier
    .user_metadata_in    (axis_switch_1_pipe_tuser),              //metadata input from ingress classifier
    .user_metadata_in_valid   (axis_switch_1_pipe_tuser_valid),      //metadata valid input from ingress classifier

    .m_axis_tdata            (axis_Checksum_1_tdata),        //tdata output to ingress translator
    .m_axis_tkeep            (axis_Checksum_1_tkeep),        //tkeep output to ingress translator
    .m_axis_tlast            (axis_Checksum_1_tlast),        //tlast output to ingress translator
    .m_axis_tready           (axis_Checksum_1_tready),       //tready output to ingress translator
    .m_axis_tvalid           (axis_Checksum_1_tvalid),       //tvalid output to ingress translator
    .user_metadata_out       (metadata_Checksum_1_out),      //metadata output to ingress translator
    .user_metadata_out_valid (metadata_Checksum_1_valid),     //metadata valid to ingress translator

    .clk(axis_aclk),
    .rst(axis_aresetn)
  );

  ingress_checksum_calculator  #(
    .Max_frag_count(25)
  ) ingress_checksum_calc_inst (            //UDP checksum calculator instance at ingress
    .clk(axis_aclk),
    .rst(axis_aresetn),

    .s_axis_tdata           (axis_signal_pipe_tdata),               //tdata input from ingress classifier
    .s_axis_tkeep           (axis_signal_pipe_tkeep),              //tkeep input from ingress classifier
    .s_axis_tlast           (axis_signal_pipe_tlast),              //tlast input from ingress classifier
    .s_axis_tready          (axis_signal_pipe_tready),             //tready output to ingress classifier
    .s_axis_tvalid          (axis_signal_pipe_tvalid),             //tvalid input from ingress classifier
    .user_metadata_in       (metadata_signal_pipe_out),            //metadata input from ingress classifier
    .user_metadata_in_valid (metadata_signal_pipe_valid),          //metadata valid input from ingress classifier

    .m_axis_tdata            (axis_Checksum_0_tdata),         //tdata output to ingress translator
    .m_axis_tkeep            (axis_Checksum_0_tkeep),        //tkeep output to ingress translator
    .m_axis_tlast            (axis_Checksum_0_tlast),        //tlast output to ingress translator
    .m_axis_tready           (axis_Checksum_0_tready),       //tready input from ingress translator
    .m_axis_tvalid           (axis_Checksum_0_tvalid),       //tvalid output to ingress translator
    .user_metadata_out       (metadata_Checksum_0_out),      //metadata output to ingress translator
    .user_metadata_out_valid (metadata_Checksum_0_valid)     //metadata valid to ingress translator
  );

  // ADDED: Pipeline register after ingress checksum calculator
  axis_register_slice_pipeline reg_slice_checksum_to_translator (
    .aclk(axis_aclk),
    .aresetn(axis_aresetn),

    // Input from checksum calculator
    .s_axis_tdata(axis_Checksum_0_tdata),
    .s_axis_tkeep(axis_Checksum_0_tkeep),
    .s_axis_tlast(axis_Checksum_0_tlast),
    .s_axis_tvalid(axis_Checksum_0_tvalid),
    .s_axis_tready(axis_Checksum_0_tready),

    // Output to ingress translator
    .m_axis_tdata(axis_Checksum_0_pipe_tdata),
    .m_axis_tkeep(axis_Checksum_0_pipe_tkeep),
    .m_axis_tlast(axis_Checksum_0_pipe_tlast),
    .m_axis_tvalid(axis_Checksum_0_pipe_tvalid),
    .m_axis_tready(axis_Checksum_0_pipe_tready)
  );

  // ADDED: Simple register for metadata
  always @(posedge axis_aclk or negedge axis_aresetn) begin
    if (!axis_aresetn) begin
      metadata_Checksum_0_pipe_out <= 23'b0;
      metadata_Checksum_0_pipe_valid <= 1'b0;
    end else begin
      if (axis_Checksum_0_tvalid && axis_Checksum_0_tready) begin
        metadata_Checksum_0_pipe_out <= metadata_Checksum_0_out;
        metadata_Checksum_0_pipe_valid <= metadata_Checksum_0_valid;
      end else if (!axis_Checksum_0_pipe_tvalid || axis_Checksum_0_pipe_tready) begin
        metadata_Checksum_0_pipe_valid <= 1'b0;
      end
    end
  end

  // Instantiate the AXI Stream FIFO
  axis_data_fifo_0 axis_fifo_0 (
    .s_axis_aclk(axis_aclk),
    .s_axis_aresetn(axis_aresetn),

    .s_axis_tdata(axis_ingress_tdata),
    .s_axis_tkeep(axis_ingress_tkeep),
    .s_axis_tlast(axis_ingress_tlast),
    .s_axis_tvalid(axis_ingress_tvalid),
    .s_axis_tready(axis_ingress_tready),

    .m_axis_tdata(axis_fifo_0_tdata),
    .m_axis_tkeep(axis_fifo_0_tkeep),
    .m_axis_tlast(axis_fifo_0_tlast),
    .m_axis_tvalid(axis_fifo_0_tvalid),
    .m_axis_tready(axis_fifo_0_tready)
  );

  // ADDED: Pipeline register after FIFO 0
  axis_register_slice_pipeline reg_slice_fifo_0 (
    .aclk(axis_aclk),
    .aresetn(axis_aresetn),

    // Input from FIFO 0
    .s_axis_tdata(axis_fifo_0_tdata),
    .s_axis_tkeep(axis_fifo_0_tkeep),
    .s_axis_tlast(axis_fifo_0_tlast),
    .s_axis_tvalid(axis_fifo_0_tvalid),
    .s_axis_tready(axis_fifo_0_tready),

    // Output to arbiter
    .m_axis_tdata(axis_fifo_0_pipe_tdata),
    .m_axis_tkeep(axis_fifo_0_pipe_tkeep),
    .m_axis_tlast(axis_fifo_0_pipe_tlast),
    .m_axis_tvalid(axis_fifo_0_pipe_tvalid),
    .m_axis_tready(axis_fifo_0_pipe_tready)
  );

  // Instantiate the AXI Stream FIFO
  axis_data_fifo_1 axis_fifo_1 (
    .s_axis_aclk(axis_aclk),
    .s_axis_aresetn(axis_aresetn),

    .s_axis_tdata(axis_switch_1_tdata),
    .s_axis_tkeep(axis_switch_1_tkeep),
    .s_axis_tlast(axis_switch_1_tlast),
    .s_axis_tvalid(axis_switch_1_tvalid),
    .s_axis_tready(axis_switch_1_tready),

    .m_axis_tdata(axis_fifo_1_tdata),
    .m_axis_tkeep(axis_fifo_1_tkeep),
    .m_axis_tlast(axis_fifo_1_tlast),
    .m_axis_tvalid(axis_fifo_1_tvalid),
    .m_axis_tready(axis_fifo_1_tready)
  );

  // ADDED: Pipeline register after FIFO 1
  axis_register_slice_pipeline reg_slice_fifo_1 (
    .aclk(axis_aclk),
    .aresetn(axis_aresetn),

    // Input from FIFO 1
    .s_axis_tdata(axis_fifo_1_tdata),
    .s_axis_tkeep(axis_fifo_1_tkeep),
    .s_axis_tlast(axis_fifo_1_tlast),
    .s_axis_tvalid(axis_fifo_1_tvalid),
    .s_axis_tready(axis_fifo_1_tready),

    // Output to arbiter
    .m_axis_tdata(axis_fifo_1_pipe_tdata),
    .m_axis_tkeep(axis_fifo_1_pipe_tkeep),
    .m_axis_tlast(axis_fifo_1_pipe_tlast),
    .m_axis_tvalid(axis_fifo_1_pipe_tvalid),
    .m_axis_tready(axis_fifo_1_pipe_tready)
  );

  // Instantiate the axi_stream_arbiter module
  // REMOVED: dont_touch attribute to allow synthesis optimization
  axi_stream_arbiter arbiter_inst (
    .clk(axis_aclk),
    .rst_n(axis_aresetn),

    // AXI Stream inputs
    .s_axis_tdata({axis_fifo_1_pipe_tdata, axis_fifo_0_pipe_tdata }),
    .s_axis_tkeep({axis_fifo_1_pipe_tkeep, axis_fifo_0_pipe_tkeep}),
    .s_axis_tvalid({axis_fifo_1_pipe_tvalid, axis_fifo_0_pipe_tvalid}),
    .s_axis_tready({axis_fifo_1_pipe_tready, axis_fifo_0_pipe_tready}),
    .s_axis_tlast({axis_fifo_1_pipe_tlast, axis_fifo_0_pipe_tlast}),

    // AXI Stream Master Interface
    .m_axis_tdata(m_axis_arbiter_pipe_tdata),
    .m_axis_tkeep(m_axis_arbiter_pipe_tkeep),
    .m_axis_tvalid(m_axis_arbiter_pipe_tvalid),
    .m_axis_tready(m_axis_arbiter_pipe_tready),
    .m_axis_tlast(m_axis_arbiter_pipe_tlast)
  );

  // ADDED: Pipeline register after arbiter
  axis_register_slice_pipeline reg_slice_arbiter_to_qdma (
    .aclk(axis_aclk),
    .aresetn(axis_aresetn),

    // Input from arbiter
    .s_axis_tdata(m_axis_arbiter_pipe_tdata),
    .s_axis_tkeep(m_axis_arbiter_pipe_tkeep),
    .s_axis_tlast(m_axis_arbiter_pipe_tlast),
    .s_axis_tvalid(m_axis_arbiter_pipe_tvalid),
    .s_axis_tready(m_axis_arbiter_pipe_tready),

    // Output to QDMA
    .m_axis_tdata(m_axis_qdma_c2h_tdata),
    .m_axis_tkeep(m_axis_qdma_c2h_tkeep),
    .m_axis_tlast(m_axis_qdma_c2h_tlast),
    .m_axis_tvalid(m_axis_qdma_c2h_tvalid),
    .m_axis_tready(m_axis_qdma_c2h_tready)
  );

endmodule: p2p_250mhz

// ADDED: Simple AXI Stream pipeline register module
module axis_register_slice_pipeline (
  input wire        aclk,
  input wire        aresetn,

  // Slave interface
  input wire [511:0] s_axis_tdata,
  input wire [63:0]  s_axis_tkeep,
  input wire         s_axis_tlast,
  input wire         s_axis_tvalid,
  input wire         s_axis_tdest,
  output reg         s_axis_tready,

  // Master interface
  output reg [511:0] m_axis_tdata,
  output reg [63:0]  m_axis_tkeep,
  output reg         m_axis_tlast,
  output reg         m_axis_tvalid,
  output reg         m_axis_tdest,
  input wire         m_axis_tready
);

  // Internal storage
  reg [511:0] tdata_reg;
  reg [63:0]  tkeep_reg;
  reg         tlast_reg;
  reg         tdest_reg;
  reg         valid_reg;

  // Control logic
  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      tdata_reg <= 512'b0;
      tkeep_reg <= 64'b0;
      tlast_reg <= 1'b0;
      tdest_reg <= 1'b0;
      valid_reg <= 1'b0;
    end else begin
      if (s_axis_tready) begin
        tdata_reg <= s_axis_tdata;
        tkeep_reg <= s_axis_tkeep;
        tlast_reg <= s_axis_tlast;
        tdest_reg <= s_axis_tdest;
        valid_reg <= s_axis_tvalid;
      end
    end
  end

  // Output assignments with flow control
  always @(*) begin
    // Default outputs
    m_axis_tdata = tdata_reg;
    m_axis_tkeep = tkeep_reg;
    m_axis_tlast = tlast_reg;
    m_axis_tdest = tdest_reg;
    m_axis_tvalid = valid_reg;

    // Backpressure handling
    if (!valid_reg || m_axis_tready) begin
      s_axis_tready = 1'b1;
    end else begin
      s_axis_tready = 1'b0;
    end

    // If downstream is ready and we have valid data, update registers
    if (m_axis_tready && valid_reg) begin
      m_axis_tdata = tdata_reg;
      m_axis_tkeep = tkeep_reg;
      m_axis_tlast = tlast_reg;
      m_axis_tdest = tdest_reg;
      m_axis_tvalid = valid_reg;
    end
  end

endmodule
