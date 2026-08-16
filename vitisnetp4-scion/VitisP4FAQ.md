## Compilation
### How P4C is invoked
Call stack (top to bottom):
```
/opt/Xilinx/Vivado/2023.1/bin/p4c-vitisnet
/opt/Xilinx/Vitis/2023.1/bin/xtclsh
/opt/Xilinx/Vitis/2023.1/bin/loader
/opt/Xilinx/Vivado/2023.1/bin/unwrapped/lnx64.o/p4c-vitisnet.tcl
```

- Set `export RDI_VERBOSE=True` in xtclsh to get debug output from loader.
- loader sets up library dirs for the binary that will eventually be loaded.
- p4c-vitisnet.tcl loads a shared object into the TCL interpreter ([load]).
- P4C is in `/opt/Xilinx/Vivado/2023.1/data/ip/xilinx/vitis_net_p4_v1_3/bin/libp4c.so`

[load]: https://www.tcl.tk/man/tcl8.4/TclCmd/load.htm

#### FAQ
How to fix
```
couldn't load file "/opt/Xilinx/Vivado/2023.1/data/ip/xilinx/vitis_net_p4_v1_3/bin/libp4c.so": /opt/Xilinx/Vitis/2023.1/lib/lnx64.o/Ubuntu/libstdc++.so.6: version `GLIBCXX_3.4.32' not found (required by /lib/x86_64-linux-gnu/libgmpxx.so.4)
```
Explanation: The system's loader is picking up to system version instead of `libgmpxx.so.4` instead of the one shipped with Vivado/Vitis.
Make sure `/opt/Xilinx/Vivado/2023.1/lib/lnx64.o/Ubuntu` is in LD_LIBRARY_PATH or copy the files over from Vivado to Vitis:
```
cp --update=none -r /opt/Xilinx/Vivado/2023.1/lib/lnx64.o/Ubuntu/* /opt/Xilinx/Vitis/2023.1/lib/lnx64.o/Ubuntu/
```

## Simulation
Simulation is carried out with the p4bm-vitisnet and p4bm-vitisnet-cli applications.

### How p4bm-vitisnet is invoked
Call stack (top to bottom):
```
/opt/Xilinx/Vivado/2023.1/bin/p4bm-vitisnet
/opt/Xilinx/Vivado/2023.1/bin/loader
/opt/Xilinx/Vivado/2023.1/bin/unwrapped/lnx64.o/p4bm-vitisnet
```

#### FAQ
Hot to fix
```
error while loading shared libraries: libthrift-0.11.0.so: cannot open shared object file: No such file or directory
```
```
cp --update=none /opt/Xilinx/Vivado/2023.1/lib/lnx64.o/Ubuntu/20/libthrift-0.11.0.so /opt/Xilinx/Vivado/2023.1/lib/lnx64.o/Ubuntu/
```
How to fix
```
error while loading shared libraries: libssl.so.1.1: cannot open shared object file: No such file or directory
```
```
cp --update=none /opt/Xilinx/Vitis_HLS/2023.1/vcxx/third-party/python-linux/user/3.10.10/lib/*so* /opt/Xilinx/Vivado/2023.1/lib/lnx64.o/Ubuntu/
```

### How p4bm-vitisnet-cli is invoked
Call stack (top to bottom):
```
/opt/Xilinx/Vivado/2023.1/bin/p4bm-vitisnet-cli // shell script
/opt/Xilinx/Vivado/2023.1/bin/loader // shell script
/opt/Xilinx/Vivado/2023.1/bin/unwrapped/lnx64.o/p4bm-vitisnet-cli // Python script
/opt/Xilinx/Vivado/2023.1/tps/lib/python3.8/bm_vitisnetp4_cli.py // Python CLI implementation
```

#### FAQ
How to fix
```
ModuleNotFoundError: No module named 'six.moves'
```
Comment out `from six.moves import zip` in `/opt/Xilinx/Vivado/2023.1/tps/lib/python3.8/thrift/protocol/TProtocol.py`.
