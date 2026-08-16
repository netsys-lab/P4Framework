SCION-IP Address Translation in Vitis P4
========================================

P4 code for Scitra-Alveo (SCION-IP address translator) data plane.

Scitra-Alveo uses four instances of the VitisNetP4 IP. Two for packets that are
received from the network, and two for packets from the host to the network.

OpenNIC Shell:
```
    -----  -----------------------------------------------
    |   |  |            System Configuration             |
    |   |  -----------------------------------------------
    |   |     |         |         |         |         |  AXI-lite 125MHz
    |   |     V         V         V         V         V
    |   |  -------   -------   -------   -------   -------
    |   |  |     |   |     |   |     |   |     |   |     |
    | P |  |  Q  |==>| Box |==>|  A  |==>| Box |==>|  C  |
    | C |  |  D  |   |  @  |   |  D  |   |  @  |   |  M  |
    | I |  |  M  |   | 250 |   |  A  |   | 322 |   |  A  |
    | E |  |  A  |<==| MHz |<==|  P  |<==| MHz |<==|  C  |
    |   |  |     | | |     | | |     | | |     | | |     |
    -----  ------- | ------- | ------- | ------- | -------
                   |         |         |         |
                   -----------         -----------
                 AXI-stream 250MHz   AXI-stream 322MHz
```

User-defined box with checksum unit:
```
----------------------------------------------------------------------------------------
|                        AXI-light System Configuration                                |
----------------------------------------------------------------------------------------
   |                |    |                                     |    |               |
---V---   ----------|----|-------------------------------------|----|---------   ---V---
|     |   | --------V-------------       -------       --------V------------ |   |     |
|     |   | |                    |<=Meta=|     |<=Meta=|                   | |   |     |
|     |<==|=|  Ingr. Translator  |<=AXIS=| CHK |<=AXIS=| Ingr. Classifier  |=|===|     |
|  Q  |   | |     (Vitis P4)     |       | SUM |       |    (Vitis P4)     | |   |  A  |
|  D  |   | ----------------------       -------       --------------------- |   |  D  |
|  M  |   |              |                                          |        |   |  A  |
|  A  |   | -------------V--------       -------       -------------V------- |   |  P  |
|     |   | |                    |=Meta=>|     |=Meta=>|                   | |   |     |
|     |===|=|  Egr. Translator   |=AXIS=>| CHK |=AXIS=>| Egr. Post-Process |=|==>|     |
|     |   | |    (Vitis P4)      |       | SUM |       |     (Vitis P4)    | |   |     |
|     |   | ----------------------       -------       --------------------- |   |     |
-------   --------------------------------------------------------------------   -------
                                      Box @ 250 MHz
```

Behavioral Model Tests
----------------------

Requires Vivado 2023.1 an license for Vitis Networking P4.
Vivado and Vitis system variables have to be set up in the environment, e.g.,
by executing `source /opt/Xilinx/Vitis/2023.1/settings64.sh`.

Building:
```bash
make all
```

Run BM-vitisnetp4 simulation:
```bash
make sim
```
