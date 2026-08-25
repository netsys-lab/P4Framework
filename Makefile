.PHONY: all clean
EXAMPLE_OBJ=vitisalveo_ingress_egress
QSPI=false
SHELL := /bin/bash
VIVADO_TARGET_VER=2023.1
VIVADO_VER=$(shell vivado -version | grep -oP 'v\K[0-9]+\.[0-9]+')
DIST_DIR=dist
# Define default implement arguments and default values
TCL_ARGS_LIST=board tag build_timestamp impl synth_ip post_impl user_plugin user_build_dir num_cmac_port num_phys_func
SYN_ARGS_LIST=impl synth_ip post_impl
if_synth=1
board=au55c
build_timestamp=$(shell date +%y%m%d%H%M)
num_cmac_port=1
num_phys_func=4
# user_build_dir must be full path. Use build_dir to give the relative path
build_dir=build
cur_dir=$(shell pwd)
user_build_dir=$(cur_dir)/$(build_dir)
all: $(EXAMPLE_OBJ)
$(EXAMPLE_OBJ): CHECK_VIVADO_VER
	$(eval tag=$@_$(build_timestamp))
	$(eval user_plugin=../../Examples/$@)
	$(eval DIST_APP_DIR=$(DIST_DIR)/$(board)_$(tag)_dist)
	$(eval post_impl=$(if_synth))
	$(foreach arg, $(SYN_ARGS_LIST), $(eval $(arg)=$(if_synth)))
	$(eval TCL_ARGS=$(foreach arg, $(TCL_ARGS_LIST), -$(arg) $($(arg))))
	$(info TCL_ARGS=$(TCL_ARGS))
	# FastCompile removed -- was trading timing QoR for build speed
	# $(eval TCL_ARGS += -compile_mode FastCompile)
	$(eval TCL_ARGS += -jobs 8)
	@[ -d '$(user_build_dir)' ] || mkdir $(user_build_dir)
	cd open-nic-shell/script && vivado -mode batch -source build.tcl -tclargs $(TCL_ARGS) | tee $(cur_dir)/build_$(tag).log
shell: CHECK_VIVADO_VER
	$(eval tag=$@_$(build_timestamp))
	$(eval DIST_APP_DIR=$(DIST_DIR)/$(board)_$(tag)_dist)
	$(if $(strip $(custom_plugin)),$(eval user_plugin=$(cur_dir)/$(custom_plugin)))
	$(eval TCL_ARGS=$(foreach arg, $(TCL_ARGS_LIST), $(if $(strip $($(arg))), -$(arg) $($(arg)))))
	$(info TCL_ARGS=$(TCL_ARGS))
	$(eval TCL_ARGS += -compile_mode FastCompile)
	@[ -d '$(user_build_dir)' ] || mkdir $(user_build_dir)
	cd open-nic-shell/script && vivado -mode batch -source build.tcl -tclargs $(TCL_ARGS) | tee $(cur_dir)/build_$(tag).log
CHECK_VIVADO_VER:
ifeq ($(VIVADO_VER), $(VIVADO_TARGET_VER))
	@echo "Current Vivado Verion is $(VIVADO_VER)"
else
	@echo "This Makefile requires VIVADO_VER as 2021.2"
	@echo "Please make sure your have source your VIVADO_ROOT/settings64.sh"
	exit 1;
endif
clean:
	rm -rf $(build_dir)
	rm -rf $(DIST_DIR)
	rm -rf *.log
