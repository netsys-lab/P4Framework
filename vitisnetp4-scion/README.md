Vitis-compatible P4 Code for SCION
==================================

These projects are intended for use in the AMD OpenNIC Shell.

Contains git submodules, clone recursively.

Currently contains:
- [SCION-IP Address Translation](./scitra)
- TODO: FPGA-assisted BR

## Python dependencies
Requires at least Python 3.12.

The simulation tests use Python and Scapy. It's recommended to install everything
in a virtual environment.
```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -e ./scapy-scion-int[extras]
pip install psutil
```

## P4C and Behavioral Model in Vivado/Vitis 2023.1 (tested on Ubuntu 24.04 LTS)
Xilinx fork of the compiler and behavioral model are closed-source and require
a license check (make sure the license server is reachable).
