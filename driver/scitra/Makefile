CC=gcc

build_dir=build
board=au55c
ifndef tag
$(error tag is not set)
endif
source_dir=../../$(build_dir)/$(board)_$(tag)/open_nic_shell/open_nic_shell.gen/sources_1/ip
driver_install=drivers/install/
driver_lib=$(driver_install)/lib/libvitisnetp4drv.a

LIBS=-lm -lreadline
OBJ=src/main.c src/device.c src/p4_target.c $(driver_lib)
TARGET=vitis_p4_driver
CC_FLAGS=-I$(driver_install)
CC_REL_FLAGS=-O2

TARGET_DBG=vitis_p4_driver_debug
CC_DBG_FLAGS=-O0 -g -D_DEBUG

.PHONY: release debug
release: $(TARGET)
debug: $(TARGET_DBG)

$(TARGET): $(OBJ)
	$(CC) $^ $(LIBS) $(CC_FLAGS) $(CC_REL_FLAGS) -o $@

$(TARGET_DBG): $(OBJ)
	$(CC) $^ $(LIBS) $(CC_FLAGS) $(CC_DBG_FLAGS) -o $@

$(driver_lib) : $(source_dir)
	cp -r $(source_dir)/vitis_net_p4_0/src/sw/drivers .
	cp $(source_dir)/vitis_net_p4_1/src/sw/drivers/target/inc/vitis_net_p4_*_defs.h drivers/target/inc
	cp $(source_dir)/vitis_net_p4_1/src/sw/drivers/target/src/vitis_net_p4_*_defs.c drivers/target/src
	cp $(source_dir)/vitis_net_p4_2/src/sw/drivers/target/inc/vitis_net_p4_*_defs.h drivers/target/inc
	cp $(source_dir)/vitis_net_p4_2/src/sw/drivers/target/src/vitis_net_p4_*_defs.c drivers/target/src
	cp $(source_dir)/vitis_net_p4_3/src/sw/drivers/target/inc/vitis_net_p4_*_defs.h drivers/target/inc
	cp $(source_dir)/vitis_net_p4_3/src/sw/drivers/target/src/vitis_net_p4_*_defs.c drivers/target/src
	$(MAKE) -C drivers

.PHONY: clean
clean:
	rm -f $(TARGET) $(TARGET_DBG)
	rm -r ./drivers
