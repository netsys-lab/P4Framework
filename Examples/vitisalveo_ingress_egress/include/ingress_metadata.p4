// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef _SCITRA_INGRESS_METADATA_GUARD
#define _SCITRA_INGRESS_METADATA_GUARD

struct metadata_t
{
    bit is_scion;
    bit<10> payload_offset;
}

#endif // _SCITRA_INGRESS_METADATA_GUARD
