set_property SRC_FILE_INFO {cfile:/home/aneesh/ALveo_p4_2instances/Alveo_AU55C/build/au55c_vitisalveo_ingress_egress_2507302111/open_nic_shell/open_nic_shell.gen/sources_1/ip/axis_data_fifo_1/axis_data_fifo_1_ooc.xdc rfile:../../../../../build/au55c_vitisalveo_ingress_egress_2507302111/open_nic_shell/open_nic_shell.gen/sources_1/ip/axis_data_fifo_1/axis_data_fifo_1_ooc.xdc id:1 order:EARLY scoped_inst:inst} [current_design]
set_property SRC_FILE_INFO {cfile:/opt/xilinx/Vivado/2023.1/data/ip/xpm/xpm_cdc/tcl/xpm_cdc_sync_rst.tcl rfile:../../../../../../../../../opt/xilinx/Vivado/2023.1/data/ip/xpm/xpm_cdc/tcl/xpm_cdc_sync_rst.tcl id:2 order:LATE scoped_inst:inst/gen_fifo.xpm_fifo_axis_inst/gaxis_rst_sync.xpm_cdc_sync_rst_inst unmanaged:yes} [current_design]
set_property src_info {type:SCOPED_XDC file:1 line:55 export:INPUT save:INPUT read:FILTER_OUT_OF_CONTEXT} [current_design]
create_clock -period 10.000 -name s_axis_aclk [get_ports s_axis_aclk]
current_instance inst/gen_fifo.xpm_fifo_axis_inst/gaxis_rst_sync.xpm_cdc_sync_rst_inst
set_property src_info {type:SCOPED_XDC file:2 line:2 export:INPUT save:NONE read:READ} [current_design]
set_false_path -to [get_cells {syncstages_ff_reg[0]}]
current_instance
set_property src_info {type:TCL file:{} line:-1 export:INPUT save:INPUT read:READ} [current_design]
set_property KEEP_HIERARCHY SOFT [get_cells inst]
set_property src_info {type:TCL file:{} line:-1 export:INPUT save:INPUT read:READ} [current_design]
set_property KEEP_HIERARCHY SOFT [get_cells inst/gen_fifo.xpm_fifo_axis_inst/gaxis_rst_sync.xpm_cdc_sync_rst_inst]
set_property src_info {type:TCL file:{} line:-1 export:INPUT save:INPUT read:READ} [current_design]
set_property KEEP_HIERARCHY SOFT [get_cells inst/gen_fifo.xpm_fifo_axis_inst]
