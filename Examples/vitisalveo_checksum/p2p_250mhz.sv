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
  parameter int NUM_INTF = 2
) (

//input from crossbar to vitis ip 1
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


  //input from crossbar to vitis ip 2
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

//output from QDMA to axi_stream_pipeline
  input                s_axis_qdma_h2c_tvalid,
  input  [511:0]       s_axis_qdma_h2c_tdata,
  input   [63:0]       s_axis_qdma_h2c_tkeep,
  input                s_axis_qdma_h2c_tlast,
  input   [15:0]       s_axis_qdma_h2c_tuser_size,
  input   [15:0]       s_axis_qdma_h2c_tuser_src,
  input   [15:0]       s_axis_qdma_h2c_tuser_dst,
  output               s_axis_qdma_h2c_tready,

  //input from ip to QDMA

  output               m_axis_qdma_c2h_tvalid,
  output [511:0]       m_axis_qdma_c2h_tdata,
  output  [63:0]       m_axis_qdma_c2h_tkeep,
  output               m_axis_qdma_c2h_tlast,
  output  [15:0]       m_axis_qdma_c2h_tuser_size,
  output  [15:0]       m_axis_qdma_c2h_tuser_src,
  output  [15:0]       m_axis_qdma_c2h_tuser_dst,
  input                m_axis_qdma_c2h_tready,

  //output from axi_stream_pipeline to packet adapter

  output               m_axis_adap_tx_250mhz_tvalid,
  output [511:0]       m_axis_adap_tx_250mhz_tdata,
  output  [63:0]       m_axis_adap_tx_250mhz_tkeep,
  output               m_axis_adap_tx_250mhz_tlast,
  output  [15:0]       m_axis_adap_tx_250mhz_tuser_size,
  output  [15:0]       m_axis_adap_tx_250mhz_tuser_src,
  output  [15:0]       m_axis_adap_tx_250mhz_tuser_dst,
  input                m_axis_adap_tx_250mhz_tready,

  //input from packet adapter to ip

  input                s_axis_adap_rx_250mhz_tvalid,
  input  [511:0]       s_axis_adap_rx_250mhz_tdata,
  input   [63:0]       s_axis_adap_rx_250mhz_tkeep,
  input                s_axis_adap_rx_250mhz_tlast,
  input   [15:0]       s_axis_adap_rx_250mhz_tuser_size,
  input   [15:0]       s_axis_adap_rx_250mhz_tuser_src,
  input   [15:0]       s_axis_adap_rx_250mhz_tuser_dst,
  output               s_axis_adap_rx_250mhz_tready,

  input                     mod_rstn,
  output                    mod_rst_done,

  input                     axil_aclk,
  input                     axis_aclk
);

  wire axil_aresetn; // Reset is clocked by the 125MHz AXI-Lite clock
  wire axis_aresetn; // Reset is clocked by the 250MHz AXI-Lite clock

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
  
    wire [10:0]  metadata_out_signal;
    wire         metadata_out_valid_signal;

    wire [511:0] m_axis_tdata_signal;
    wire [63:0]  m_axis_tkeep_signal;
    wire         m_axis_tlast_signal;
    wire         m_axis_tvalid_signal;
    wire         m_axis_tready_signal;

    wire [10:0]  metadata_out_Checksum;
    wire         metadata_out_valid_Checksum;

    wire [511:0] m_axis_tdata_Checksum;
    wire [63:0]  m_axis_tkeep_Checksum;
    wire         m_axis_tlast_Checksum;
    wire         m_axis_tvalid_Checksum;
    wire         m_axis_tready_Checksum;
  

  generate for (genvar i = 0; i < NUM_INTF; i++) begin
  
    wire [47:0] axis_qdma_h2c_tuser;
    wire [47:0] axis_qdma_c2h_tuser;
    wire [47:0] axis_adap_tx_250mhz_tuser;
    wire [47:0] axis_adap_rx_250mhz_tuser;

    assign axis_qdma_h2c_tuser[0+:16]                       =          s_axis_qdma_h2c_tuser_size;
    assign axis_qdma_h2c_tuser[16+:16]                      =          s_axis_qdma_h2c_tuser_src;
    assign axis_qdma_h2c_tuser[32+:16]                      =          s_axis_qdma_h2c_tuser_dst;

    assign axis_adap_rx_250mhz_tuser[0+:16]                 =          s_axis_adap_rx_250mhz_tuser_size;
    assign axis_adap_rx_250mhz_tuser[16+:16]                =          s_axis_adap_rx_250mhz_tuser_src;
    assign axis_adap_rx_250mhz_tuser[32+:16]                =          s_axis_adap_rx_250mhz_tuser_dst;

    assign m_axis_adap_tx_250mhz_tuser_size                 =          axis_adap_tx_250mhz_tuser[0+:16];
    assign m_axis_adap_tx_250mhz_tuser_src                  =          axis_adap_tx_250mhz_tuser[16+:16];
    assign m_axis_adap_tx_250mhz_tuser_dst                  =          axis_adap_tx_250mhz_tuser[32+:16];

    assign m_axis_qdma_c2h_tuser_size                       =          axis_qdma_c2h_tuser[0+:16];
    assign m_axis_qdma_c2h_tuser_src                        =          axis_qdma_c2h_tuser[16+:16];
    assign m_axis_qdma_c2h_tuser_dst                        =          axis_qdma_c2h_tuser[32+:16];






    if (i==0) begin
      vitis_net_p4_0 ingress_classifier_p4 (
        .s_axis_aclk     (axis_aclk),                         // input wire s_axis_aclk
        .s_axis_aresetn  (axis_aresetn),                      // input wire s_axis_aresetn
        .s_axi_aclk      (axil_aclk),                         // input wire s_axi_aclk
        .s_axi_aresetn   (axil_aresetn),                      // input wire s_axi_aresetn
        .cam_mem_aclk    (axis_aclk),                         // input wire cam_mem_aclk
        .cam_mem_aresetn (axis_aresetn),                      // input wire cam_mem_aresetn

        .user_metadata_in({s_axis_adap_rx_250mhz_tuser_size,      // can refer to the "vitis_net_p4_0_pkg.sv" to find the field indices
			   s_axis_adap_rx_250mhz_tuser_src,                   // and the order of each field within the metadata struct as used by the
			   s_axis_adap_rx_250mhz_tuser_dst                   // generated RTL implementation
			   }
                         ),                                                       // input wire [47 : 0] user_metadata_in
        .user_metadata_in_valid(s_axis_adap_rx_250mhz_tvalid),                    // input wire user_metadata_in_valid

        .user_metadata_out(metadata_out_signal),
        .user_metadata_out_valid(metadata_out_valid_signal),

        .s_axis_tdata    (s_axis_adap_rx_250mhz_tdata),                 // input wire [511 : 0] s_axis_tdata
        .s_axis_tkeep    (s_axis_adap_rx_250mhz_tkeep),                // input wire [63 : 0] s_axis_tkeep
        .s_axis_tlast    (s_axis_adap_rx_250mhz_tlast),                // input wire s_axis_tlast
        .s_axis_tvalid   (s_axis_adap_rx_250mhz_tvalid),               // input wire s_axis_tvalid
        .s_axis_tready   (s_axis_adap_rx_250mhz_tready),               // output wire s_axis_tready

        .m_axis_tdata    (m_axis_tdata_signal),               // output wire [511 : 0] m_axis_tdata
        .m_axis_tkeep    (m_axis_tkeep_signal),               // output wire [63 : 0] m_axis_tkeep
        .m_axis_tlast    (m_axis_tlast_signal),               // output wire m_axis_tlast
        .m_axis_tvalid   (m_axis_tvalid_signal),              // output wire m_axis_tvalid
        .m_axis_tready   (m_axis_tready_signal),              // input wire m_axis_tready

        .s_axi_araddr    (s_axil_araddr),                       // input wire [12 : 0] s_axi_araddr
        .s_axi_arready   (s_axil_arready),                      // output wire s_axi_arready
        .s_axi_arvalid   (s_axil_arvalid),                      // input wire s_axi_arvalid
        .s_axi_awaddr    (s_axil_awaddr),                       // input wire [12 : 0] s_axi_awaddr
        .s_axi_awready   (s_axil_awready),                      // output wire s_axi_awready
        .s_axi_awvalid   (s_axil_awvalid),                      // input wire s_axi_awvalid
        .s_axi_bready    (s_axil_bready),                       // input wire s_axi_bready
        .s_axi_bresp     (s_axil_bresp),                        // output wire [1 : 0] s_axi_bresp
        .s_axi_bvalid    (s_axil_bvalid),                       // output wire s_axi_bvalid
        .s_axi_rdata     (s_axil_rdata),                        // output wire [31 : 0] s_axi_rdata
        .s_axi_rready    (s_axil_rready),                       // input wire s_axi_rready
        .s_axi_rresp     (s_axil_rresp),                        // output wire [1 : 0] s_axi_rresp
        .s_axi_rvalid    (s_axil_rvalid),                       // output wire s_axi_rvalid
        .s_axi_wdata     (s_axil_wdata),                        // input wire [31 : 0] s_axi_wdata
        .s_axi_wready    (s_axil_wready),                       // output wire s_axi_wready
        .s_axi_wstrb     (4'b1111),                             // input wire [3 : 0] s_axi_wstrb
        .s_axi_wvalid    (s_axil_wvalid)                        // input wire s_axi_wvalid
      );



    end if (i==1) begin
    
      vitis_net_p4_1 ingress_translator_p4 (
        .s_axis_aclk     (axis_aclk),                         // input wire s_axis_aclk
        .s_axis_aresetn  (axis_aresetn),                      // input wire s_axis_aresetn
        .s_axi_aclk      (axil_aclk),                         // input wire s_axi_aclk
        .s_axi_aresetn   (axil_aresetn),                      // input wire s_axi_aresetn
        .cam_mem_aclk    (axis_aclk),                         // input wire cam_mem_aclk
        .cam_mem_aresetn (axis_aresetn),                      // input wire cam_mem_aresetn

        .user_metadata_in(metadata_out_Checksum),
        .user_metadata_in_valid(metadata_out_valid_Checksum),   // input wire user_metadata_in_valid

        .user_metadata_out({axis_qdma_c2h_tuser[15:0],        // can refer to the "vitis_net_p4_0_pkg.sv" to find the field indices
			    axis_qdma_c2h_tuser[31:16],                   // and the order of each field within the metadata struct as used
			    axis_qdma_c2h_tuser[47:32]                    // by the generated RTL implementation
                           }),                                // output wire [47 : 0] user_metadata_out
        .user_metadata_out_valid(user_metadata_out_valid),    // output wire user_metadata_out_valid

        .s_axis_tdata    (m_axis_tdata_Checksum),               // input wire [511 : 0] s_axis_tdata
        .s_axis_tkeep    (m_axis_tkeep_Checksum),               // input wire [63 : 0] s_axis_tkeep
        .s_axis_tlast    (m_axis_tlast_Checksum),                      // input wire s_axis_tlast
        .s_axis_tvalid   (m_axis_tvalid_Checksum),                     // input wire s_axis_tvalid
        .s_axis_tready   (m_axis_tready_Checksum),                     // output wire s_axis_tready

        .m_axis_tdata    (m_axis_qdma_c2h_tdata),                      // output wire [511 : 0] m_axis_tdata
        .m_axis_tkeep    (m_axis_qdma_c2h_tkeep),                      // output wire [63 : 0] m_axis_tkeep
        .m_axis_tlast    (m_axis_qdma_c2h_tlast),                      // output wire m_axis_tlast
        .m_axis_tvalid   (m_axis_qdma_c2h_tvalid),                     // output wire m_axis_tvalid
        .m_axis_tready   (m_axis_qdma_c2h_tready),                     // input wire m_axis_tready

        .s_axi_araddr    (s_axil_new_araddr),                       // input wire [12 : 0] s_axi_araddr
        .s_axi_arready   (s_axil_new_arready),                      // output wire s_axi_arready
        .s_axi_arvalid   (s_axil_new_arvalid),                      // input wire s_axi_arvalid
        .s_axi_awaddr    (s_axil_new_awaddr),                       // input wire [12 : 0] s_axi_awaddr
        .s_axi_awready   (s_axil_new_awready),                      // output wire s_axi_awready
        .s_axi_awvalid   (s_axil_new_awvalid),                      // input wire s_axi_awvalid
        .s_axi_bready    (s_axil_new_bready),                       // input wire s_axi_bready
        .s_axi_bresp     (s_axil_new_bresp),                        // output wire [1 : 0] s_axi_bresp
        .s_axi_bvalid    (s_axil_new_bvalid),                       // output wire s_axi_bvalid
        .s_axi_rdata     (s_axil_new_rdata),                        // output wire [31 : 0] s_axi_rdata
        .s_axi_rready    (s_axil_new_rready),                       // input wire s_axi_rready
        .s_axi_rresp     (s_axil_new_rresp),                        // output wire [1 : 0] s_axi_rresp
        .s_axi_rvalid    (s_axil_new_rvalid),                       // output wire s_axi_rvalid
        .s_axi_wdata     (s_axil_new_wdata),                        // input wire [31 : 0] s_axi_wdata
        .s_axi_wready    (s_axil_new_wready),                       // output wire s_axi_wready
        .s_axi_wstrb     (4'b1111),                                 // input wire [3 : 0] s_axi_wstrb
        .s_axi_wvalid    (s_axil_new_wvalid)                        // input wire s_axi_wvalid
      );


    end else begin                                                  //routing packets directly from packet adapter to QDMA when no VItis IP instance present
    axi_stream_pipeline rx_ppl_inst (
        .s_axis_tvalid (s_axis_adap_rx_250mhz_tvalid),
        .s_axis_tdata  (s_axis_adap_rx_250mhz_tdata),
        .s_axis_tkeep  (s_axis_adap_rx_250mhz_tkeep),
        .s_axis_tlast  (s_axis_adap_rx_250mhz_tlast),
        .s_axis_tuser  (axis_adap_rx_250mhz_tuser),
        .s_axis_tready (s_axis_adap_rx_250mhz_tready),

        .m_axis_tvalid (m_axis_qdma_c2h_tvalid),
        .m_axis_tdata  (m_axis_qdma_c2h_tdata),
        .m_axis_tkeep  (m_axis_qdma_c2h_tkeep),
        .m_axis_tlast  (m_axis_qdma_c2h_tlast),
        .m_axis_tuser  (axis_qdma_c2h_tuser),
        .m_axis_tready (m_axis_qdma_c2h_tready),

       .aclk          (axis_aclk),
        .aresetn       (axil_aresetn)
      );
  

    end
  end
  endgenerate

axi_stream_pipeline tx_ppl_inst (
      .s_axis_tvalid (s_axis_qdma_h2c_tvalid),
      .s_axis_tdata  (s_axis_qdma_h2c_tdata),
      .s_axis_tkeep  (s_axis_qdma_h2c_tkeep),
      .s_axis_tlast  (s_axis_qdma_h2c_tlast),
      .s_axis_tuser  (axis_qdma_h2c_tuser),
      .s_axis_tready (s_axis_qdma_h2c_tready),

      .m_axis_tvalid (m_axis_adap_tx_250mhz_tvalid),
      .m_axis_tdata  (m_axis_adap_tx_250mhz_tdata),
      .m_axis_tkeep  (m_axis_adap_tx_250mhz_tkeep),
      .m_axis_tlast  (m_axis_adap_tx_250mhz_tlast),
      .m_axis_tuser  (axis_adap_tx_250mhz_tuser),
      .m_axis_tready (m_axis_adap_tx_250mhz_tready),

      .aclk          (axis_aclk),
      .aresetn       (axil_aresetn)
    );
    

    // Instantiate ingress_checksum_calculator
    ingress_checksum_calculator checksum_inst (
        .clk(axis_aclk),
        .rst(axis_aresetn),

        // AXI Stream Input
        .s_axis_tdata(m_axis_tdata_signal),
        .s_axis_tkeep(m_axis_tkeep_signal),
        .s_axis_tlast(m_axis_tlast_signal),
        .s_axis_tready(m_axis_tready_signal),
        .s_axis_tvalid(m_axis_tvalid_signal),

        // Metadata Input
        .metadata_in(metadata_out_signal),
        .metadata_valid(metadata_out_valid_signal),

        // Metadata Output
        .metadata_out(metadata_out_Checksum),
        .metadata_valid_out(metadata_out_valid_Checksum),

        // AXI Stream Output
        .m_axis_tdata(m_axis_tdata_Checksum),
        .m_axis_tkeep(m_axis_tkeep_Checksum),
        .m_axis_tlast(m_axis_tlast_Checksum),
        .m_axis_tready(m_axis_tready_Checksum),
        .m_axis_tvalid(m_axis_tvalid_Checksum)
    );

endmodule: p2p_250mhz
