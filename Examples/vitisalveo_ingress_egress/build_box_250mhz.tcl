# *************************************************************************
#
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



# Set P4 directory and source file
set p4_dir [file normalize .]
set p4_src0 ingress-classifier.p4
set p4_src1 ingress-translator.p4
set p4_src2 egress-translator.p4
set p4_src3 egress_checksum.p4

# Define base addresses for AXI crossbar configuration
# Base address for dummy
set BASE_ADDR 0x4000
# Base address for the first instance
set BASE_ADDR_0 0x8000
# Base address for the second instance
set BASE_ADDR_1 0xC000
# Base address for the third instance
set BASE_ADDR_2 0x10000
 # Address width (14 bits corresponds to 16 KB range)
set ADDR_WIDTH 14

# Read Verilog source
read_verilog -quiet -sv p2p_250mhz.sv
read_verilog -quiet -sv ingress_checksum_calculator.sv  ;
read_verilog -quiet -sv calculator_UDP_chksm_egress.sv  ;
read_verilog -quiet -sv axi_stream_arbiter.sv  ;

# Create and configure the first VitisNetP4 IP instance
create_ip -name vitis_net_p4 -vendor xilinx.com -library ip -module_name vitis_net_p4_0
set_property -dict [list CONFIG.P4_FILE "$p4_dir/$p4_src0"] [get_ips vitis_net_p4_0]
generate_target all [get_ips vitis_net_p4_0]

# Create and configure the second VitisNetP4 IP instance
create_ip -name vitis_net_p4 -vendor xilinx.com -library ip -module_name vitis_net_p4_1
set_property -dict [list CONFIG.P4_FILE "$p4_dir/$p4_src1"] [get_ips vitis_net_p4_1]
generate_target all [get_ips vitis_net_p4_1]

# Create and configure the third VitisNetP4 IP instance
create_ip -name vitis_net_p4 -vendor xilinx.com -library ip -module_name vitis_net_p4_2
set_property -dict [list CONFIG.P4_FILE "$p4_dir/$p4_src2"] [get_ips vitis_net_p4_2]
generate_target all [get_ips vitis_net_p4_2]

# Create and configure the third VitisNetP4 IP instance
create_ip -name vitis_net_p4 -vendor xilinx.com -library ip -module_name vitis_net_p4_3
set_property -dict [list CONFIG.P4_FILE "$p4_dir/$p4_src3"] [get_ips vitis_net_p4_3]
generate_target all [get_ips vitis_net_p4_3]

#Create and configure axi stream switch ip 0
create_ip -name axis_switch -vendor xilinx.com -library ip -module_name axis_switch_0

set_property -dict [list \
    CONFIG.NUM_SI {1} \
    CONFIG.NUM_MI {2} \
    CONFIG.ARB_ALGORITHM {0} \
    CONFIG.TDATA_NUM_BYTES {64} \
    CONFIG.ROUTING_MODE {1} \
    CONFIG.DECODER_REG {1} \
    CONFIG.DECODER_REG {1} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.TUSER_WIDTH {27} \
] [get_ips axis_switch_0]

generate_target all [get_ips axis_switch_0]

#Create and configure axi stream switch ip 1
#create_ip -name axis_switch -vendor xilinx.com -library ip -module_name axis_switch_1

#set_property -dict [list \
#    CONFIG.NUM_SI {2} \
#    CONFIG.NUM_MI {1} \
#    CONFIG.ARB_ALGORITHM {1} \
#    CONFIG.TDATA_NUM_BYTES {64} \
#    CONFIG.ROUTING_MODE {0} \
#    CONFIG.DECODER_REG {1} \
#    CONFIG.HAS_TKEEP {1} \
#    CONFIG.HAS_TLAST {1} \
#] [get_ips axis_switch_1]

#generate_target all [get_ips axis_switch_1]

# Create the AXI Stream FIFO IP core
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_0

# Configure the FIFO
set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES {64} \
    CONFIG.FIFO_DEPTH {512} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TREADY {1} \
    CONFIG.HAS_TSTRB {0} \
    CONFIG.TUSER_WIDTH {0} \
] [get_ips axis_data_fifo_0]

# Generate the IP core
generate_target all [get_ips axis_data_fifo_0]
synth_ip [get_ips axis_data_fifo_0]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_1

# Configure the FIFO
set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES {64} \
    CONFIG.FIFO_DEPTH {512} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TREADY {1} \
    CONFIG.HAS_TSTRB {0} \
    CONFIG.TUSER_WIDTH {0} \
] [get_ips axis_data_fifo_1]

# Generate the IP core
generate_target all [get_ips axis_data_fifo_1]
synth_ip [get_ips axis_data_fifo_1]


# Configure AXI crossbar for the first VitisNetP4 instance (M00)
set_property -dict [list CONFIG.M00_A00_ADDR_WIDTH "$ADDR_WIDTH" CONFIG.M00_A00_BASE_ADDR "$BASE_ADDR_0"] [get_ips box_250mhz_axi_crossbar]

# Configure AXI crossbar for the second VitisNetP4 instance (M02)
set_property -dict [list CONFIG.M02_A00_ADDR_WIDTH "$ADDR_WIDTH" CONFIG.M02_A00_BASE_ADDR "$BASE_ADDR_1"] [get_ips box_250mhz_axi_crossbar]

# Configure AXI crossbar for the second VitisNetP4 instance (M04)
set_property -dict [list CONFIG.M04_A00_ADDR_WIDTH "$ADDR_WIDTH" CONFIG.M02_A00_BASE_ADDR "$BASE_ADDR_2"] [get_ips box_250mhz_axi_crossbar]

# Set generic for width
set cur_generic [get_property generic [current_fileset]]
lappend cur_generic "C_DUMMY_BASE_ADDR=$BASE_ADDR"
set_property -name generic -value $cur_generic -object [current_fileset]
set ccur_generic [get_property generic [current_fileset]]
