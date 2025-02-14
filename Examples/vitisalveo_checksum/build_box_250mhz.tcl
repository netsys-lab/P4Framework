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

# Define base addresses for AXI crossbar configuration
# Base address for the first instance
set BASE_ADDR 0x4000
# Base address for the first instance
set BASE_ADDR_0 0x8000
# Base address for the second instance
set BASE_ADDR_1 0xC000
 # Address width (14 bits corresponds to 16 KB range)
set ADDR_WIDTH 14

# Read Verilog source
read_verilog -quiet -sv p2p_250mhz.sv
read_verilog -quiet -sv ingress_checksum_calculator.sv  ;

# Create and configure the first VitisNetP4 IP instance
create_ip -name vitis_net_p4 -vendor xilinx.com -library ip -module_name vitis_net_p4_0
set_property -dict [list CONFIG.P4_FILE "$p4_dir/$p4_src0"] [get_ips vitis_net_p4_0]
generate_target all [get_ips vitis_net_p4_0]

# Create and configure the second VitisNetP4 IP instance
create_ip -name vitis_net_p4 -vendor xilinx.com -library ip -module_name vitis_net_p4_1
set_property -dict [list CONFIG.P4_FILE "$p4_dir/$p4_src1"] [get_ips vitis_net_p4_1]
generate_target all [get_ips vitis_net_p4_1]

# Configure AXI crossbar for the first VitisNetP4 instance (M00)
set_property -dict [list CONFIG.M00_A00_ADDR_WIDTH "$ADDR_WIDTH" CONFIG.M00_A00_BASE_ADDR "$BASE_ADDR_0"] [get_ips box_250mhz_axi_crossbar]

# Configure AXI crossbar for the second VitisNetP4 instance (M02)
set_property -dict [list CONFIG.M02_A00_ADDR_WIDTH "$ADDR_WIDTH" CONFIG.M02_A00_BASE_ADDR "$BASE_ADDR_1"] [get_ips box_250mhz_axi_crossbar]

# Set generic for width
set cur_generic [get_property generic [current_fileset]]
lappend cur_generic "C_DUMMY_BASE_ADDR=$BASE_ADDR"
set_property -name generic -value $cur_generic -object [current_fileset]
set ccur_generic [get_property generic [current_fileset]]
