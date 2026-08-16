# SPDX-License-Identifier: AGPL-3.0-or-later

from scapy.fields import BitField, ByteField
from scapy.packet import Packet, bind_layers
from scapy_scion.layers.scion import UDP

CPU_PORT = 13666
TO_CPU_REASON_SCMP = 0
TO_CPU_REASON_ICMP = 1
TO_CPU_REASON_NO_PATH = 2


class CPUMetadata(Packet):
    """Metadata for CPU"""

    name = "CPU Metadata"

    fields_desc = [
        ByteField("reason", default=TO_CPU_REASON_SCMP),
        BitField("reserved", size=24, default=0),
    ]


bind_layers(UDP, CPUMetadata, dport=CPU_PORT)
