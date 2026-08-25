# *************************************************************************
#FIN-OVGU Magdeburg
# Copyright 2020 Xilinx, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# *************************************************************************

# Set P4 directory and source files
set p4_dir [file normalize .]
set p4_src0 ingress-classifier.p4
set p4_src1 ingress-translator.p4
set p4_src2 egress-translator.p4
set p4_src3 egress_checksum.p4


# These MUST stay in sync with box_250mhz_address_map.v's
# C_*_BASE_ADDR localparams and box_250mhz_axi_crossbar.tcl's
# M0X_A00_BASE_ADDR/M0X_A00_ADDR_WIDTH values -- all three files encode the
# same address map independently;
set BASE_ADDR_EGRESS_TRANSLATOR   0x00000000
set WIDTH_EGRESS_TRANSLATOR       19

set BASE_ADDR_CLASSIFIER          0x00080000
set WIDTH_CLASSIFIER              18

set BASE_ADDR_INGRESS_TRANSLATOR  0x000C0000
set WIDTH_INGRESS_TRANSLATOR      17

set BASE_ADDR_DUMMY               0x000E0000
set WIDTH_DUMMY                   12

# Read Verilog source
read_verilog -quiet -sv p2p_250mhz.sv
read_verilog -quiet -sv ingress_checksum_calculator.sv
read_verilog -quiet -sv calculator_UDP_chksm_egress.sv
read_verilog -quiet -sv axi_stream_arbiter.sv

# Create and configure the VitisNetP4 IP instances
create_ip -name vitis_net_p4 -vendor xilinx.com -library ip -module_name vitis_net_p4_0
set_property -dict [list CONFIG.P4_FILE "$p4_dir/$p4_src0"] [get_ips vitis_net_p4_0]
generate_target all [get_ips vitis_net_p4_0]

create_ip -name vitis_net_p4 -vendor xilinx.com -library ip -module_name vitis_net_p4_1
set_property -dict [list CONFIG.P4_FILE "$p4_dir/$p4_src1"] [get_ips vitis_net_p4_1]
generate_target all [get_ips vitis_net_p4_1]

create_ip -name vitis_net_p4 -vendor xilinx.com -library ip -module_name vitis_net_p4_2
set_property -dict [list CONFIG.P4_FILE "$p4_dir/$p4_src2"] [get_ips vitis_net_p4_2]
generate_target all [get_ips vitis_net_p4_2]

create_ip -name vitis_net_p4 -vendor xilinx.com -library ip -module_name vitis_net_p4_3
set_property -dict [list CONFIG.P4_FILE "$p4_dir/$p4_src3"] [get_ips vitis_net_p4_3]
generate_target all [get_ips vitis_net_p4_3]

# Create and configure axi stream switch ip 0
create_ip -name axis_switch -vendor xilinx.com -library ip -module_name axis_switch_0

set_property -dict [list \
    CONFIG.NUM_SI {1} \
    CONFIG.NUM_MI {2} \
    CONFIG.ARB_ALGORITHM {0} \
    CONFIG.TDATA_NUM_BYTES {64} \
    CONFIG.ROUTING_MODE {0} \
    CONFIG.DECODER_REG {1} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.TUSER_WIDTH {27} \
] [get_ips axis_switch_0]

generate_target all [get_ips axis_switch_0]

# Create the AXI Stream FIFO IP cores
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_0
set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES {64} \
    CONFIG.FIFO_DEPTH {512} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TREADY {1} \
    CONFIG.HAS_TSTRB {0} \
    CONFIG.TUSER_WIDTH {0} \
] [get_ips axis_data_fifo_0]
generate_target all [get_ips axis_data_fifo_0]
synth_ip [get_ips axis_data_fifo_0]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_1
set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES {64} \
    CONFIG.FIFO_DEPTH {512} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TREADY {1} \
    CONFIG.HAS_TSTRB {0} \
    CONFIG.TUSER_WIDTH {0} \
] [get_ips axis_data_fifo_1]
generate_target all [get_ips axis_data_fifo_1]
synth_ip [get_ips axis_data_fifo_1]

# Configure AXI crossbar (indices match box_250mhz_address_map.v exactly:
# M00=egress translator, M01=classifier, M02=ingress translator, M03=dummy)
set_property -dict [list CONFIG.M00_A00_ADDR_WIDTH "$WIDTH_EGRESS_TRANSLATOR" CONFIG.M00_A00_BASE_ADDR "$BASE_ADDR_EGRESS_TRANSLATOR"] [get_ips box_250mhz_axi_crossbar]
set_property -dict [list CONFIG.M01_A00_ADDR_WIDTH "$WIDTH_CLASSIFIER" CONFIG.M01_A00_BASE_ADDR "$BASE_ADDR_CLASSIFIER"] [get_ips box_250mhz_axi_crossbar]
set_property -dict [list CONFIG.M02_A00_ADDR_WIDTH "$WIDTH_INGRESS_TRANSLATOR" CONFIG.M02_A00_BASE_ADDR "$BASE_ADDR_INGRESS_TRANSLATOR"] [get_ips box_250mhz_axi_crossbar]
set_property -dict [list CONFIG.M03_A00_ADDR_WIDTH "$WIDTH_DUMMY" CONFIG.M03_A00_BASE_ADDR "$BASE_ADDR_DUMMY"] [get_ips box_250mhz_axi_crossbar]

# Set generic for dummy's base address (must match box_250mhz_address_map.v's
# C_DUMMY_BASE_ADDR default parameter)
set cur_generic [get_property generic [current_fileset]]
lappend cur_generic "C_DUMMY_BASE_ADDR=$BASE_ADDR_DUMMY"
set_property -name generic -value $cur_generic -object [current_fileset]
