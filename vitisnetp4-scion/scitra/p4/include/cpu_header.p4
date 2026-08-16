// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef _CPU_HEADER_GUARD
#define _CPU_HEADER_GUARD

#define CPU_PORT 13666
#define CPU_HDR_SIZE_BYTES 4

typedef bit<8> to_cpu_reason_t;
const to_cpu_reason_t TO_CPU_REASON_SCMP = 0;
const to_cpu_reason_t TO_CPU_REASON_ICMP = 1;
const to_cpu_reason_t TO_CPU_REASON_NEW_FLOW = 2;

header cpu_h
{
    to_cpu_reason_t reason;
    bit<24>         reserved;
};

#endif // _CPU_HEADER_GUARD
