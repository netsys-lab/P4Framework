// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef _SCITRA_ADDR_MAPPING_GUARD
#define _SCITRA_ADDR_MAPPING_GUARD

#define MAPPED_ISD_BITS 12
#define MAPPED_AS_BITS 20
#define SCION_PREFIX 8w0xfc

#define extract_prefix(ip) ip[127:120]
#define extract_isd(ip) ip[119:108]
#define extract_asn(ip) ip[107:88]
#define extract_network(ip) ip[87:64]
#define extract_host_prefix(ip) ip[63:32]
#define extract_host_v4(ip) ip[31:0]
#define extract_host_v6(ip) ip[63:0]

#endif // _SCITRA_ADDR_MAPPING_GUARD
