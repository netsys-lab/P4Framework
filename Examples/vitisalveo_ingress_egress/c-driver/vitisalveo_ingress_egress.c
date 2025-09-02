/*
-- (c) Copyright 2019 Xilinx, Inc. All rights reserved.
--
-- This file contains confidential and proprietary information
-- of Xilinx, Inc. and is protected under U.S. and
-- international copyright and other intellectual property
-- laws.
--
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- Xilinx, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) Xilinx shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or Xilinx had been advised of the
-- possibility of the same.
*/

#include "include/vitis_net_p4_0_defs.h"
#include "include/vitisnetp4_common.h"
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/types.h>
//#include "xil_vitis_net_p4.h"

#define EXAMPLE_NUM_TABLE_ENTRIES (4)
#define DISPLAY_ERROR(ErrorCode) printf("Error Code is value %s\n", XilVitisNetP4ReturnTypeToString(ErrorCode))
#define CONVERT_BITS_TO_BYTES(NumBits) ((NumBits/8) + ((NumBits % 8) ? 1 : 0))

/* System file path for PCIe device */
char sysfile_path[] = "/sys/devices/pci0000:3a/0000:3a:00.0/0000:3b:00.0/resource2";
int sysfile;

/* Hardware-specific addresses */
#define C_P2P_BASE_ADDR          0x8000  // Ingress Classifier base address
#define C_NEW_BASE_ADDR          0xC000  // Ingress Translator base address
#define C_EGRESS_BASE_ADDR       0x10000 // Egress Translator base address

#define SCMP_DestUnreach      1
#define SCMP_PacketTooBig     2
#define SCMP_EchoRequest      128
#define ICMP6_TYPE_PacketTooBig 2
#define ICMP6_TYPE_EchoRequest 128

#ifndef XIL_VITIS_NET_P4_ACTION_ID_NO_ACTION
#define XIL_VITIS_NET_P4_ACTION_ID_NO_ACTION 0
#endif

/* User context structure */
typedef struct ExampleUserContext {
    XilVitisNetP4AddressType VitisNetP4Address;
} ExampleUserContext;

/* Counter indices matching P4 programs */
// Replace all const bit<N> declarations with uint8_t or appropriate types:

// Ingress Classifier counters
const uint8_t CNT_DROPPED = 0;
const uint8_t CNT_OTHER = 1;
const uint8_t CNT_TOTAL_IPV4 = 2;
const uint8_t CNT_TOTAL_IPV6 = 3;
const uint8_t CNT_SCION_IPV4 = 4;
const uint8_t CNT_SCION_IPV6 = 5;

// Ingress Translator counters
const uint8_t CNT_DROP_PARSER = 0;
const uint8_t CNT_DROP_CHKSUM = 1;
const uint8_t CNT_DROP_SRC_ADDR = 2;
const uint8_t CNT_DROP_DST_ADDR = 3;

const uint8_t CNT_NOT_TRANSLATED = 0;
const uint8_t CNT_TO_CPU = 1;
const uint8_t CNT_SCMP = 2;
const uint8_t CNT_UDP = 3;
const uint8_t CNT_TCP = 4;

// Egress Translator counters
const uint8_t CNT_EGRESS_DROP_PARSER = 0;
const uint8_t CNT_EGRESS_DROP_MTU_EXCEEDED = 1;

/* Key and Response arrays for all tables */
uint8_t LocalIPv4KeyArray[EXAMPLE_NUM_TABLE_ENTRIES][4] = {
    {0xC0, 0xA8, 0x01, 0x01}, // 192.168.1.1
    {0xC0, 0xA8, 0x01, 0x02}, // 192.168.1.2
    {0xC0, 0xA8, 0x01, 0x03}, // 192.168.1.3
    {0xC0, 0xA8, 0x01, 0x04}  // 192.168.1.4
};

uint8_t StaticPortsIPv4KeyArray[EXAMPLE_NUM_TABLE_ENTRIES][2] = {
    {0x79, 0x18}, // Port 31000
    {0x79, 0x19}, // Port 31001
    {0x79, 0x1A}, // Port 31002
    {0x79, 0x1B}  // Port 31003
};

uint8_t DynamicPortsIPv4KeyArray[EXAMPLE_NUM_TABLE_ENTRIES][8] = {
    // src_ip(4) | src_port(2) | dst_port(2)
    {0xC0, 0xA8, 0x01, 0x01, 0x79, 0x18, 0x79, 0x18},
    {0xC0, 0xA8, 0x01, 0x02, 0x79, 0x19, 0x79, 0x19},
    {0xC0, 0xA8, 0x01, 0x03, 0x79, 0x1A, 0x79, 0x1A},
    {0xC0, 0xA8, 0x01, 0x04, 0x79, 0x1B, 0x79, 0x1B}
};

/* IPv6 Addresses (16 bytes each) */
uint8_t LocalIPv6KeyArray[EXAMPLE_NUM_TABLE_ENTRIES][16] = {
    {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,1}, // 2001:db8::1
    {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,2}, // 2001:db8::2
    {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,3}, // 2001:db8::3
    {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,4}  // 2001:db8::4
};

/* IPv6 Dynamic Ports keys (16+2+2 = 20 bytes each) */
uint8_t DynamicPortsIPv6KeyArray[EXAMPLE_NUM_TABLE_ENTRIES][20] = {
    // src_ip(16) | src_port(2) | dst_port(2)
    {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,1, 0x79,0x18, 0x79,0x18},
    {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,2, 0x79,0x19, 0x79,0x19},
    {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,3, 0x79,0x1A, 0x79,0x1A},
    {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,4, 0x79,0x1B, 0x79,0x1B}
};

uint8_t DynamicPortsActionParamsArray[EXAMPLE_NUM_TABLE_ENTRIES][2] = {
    {0x00, 0x00}, // Index 0
    {0x00, 0x01}, // Index 1
    {0x00, 0x02}, // Index 2
    {0x00, 0x03}  // Index 3
};

/* Function prototypes */
static void DisplayVitisNetP4Versions(XilVitisNetP4TargetCtx *CtxPtr);
XilVitisNetP4ReturnType example_log_info(XilVitisNetP4EnvIf *EnvIfPtr, const char *MessagePtr);
int device_open(char *file_name);
int device_close();
void device_write(uint32_t address, uint32_t data);
uint32_t device_read(uint32_t address, uint32_t *data);
XilVitisNetP4ReturnType env_write(XilVitisNetP4EnvIf *EnvIfPtr, XilVitisNetP4AddressType Address, uint32_t WriteValue);
XilVitisNetP4ReturnType env_read(XilVitisNetP4EnvIf *EnvIfPtr, XilVitisNetP4AddressType Address, uint32_t *ReadValuePtr);
XilVitisNetP4ReturnType update_counter(XilVitisNetP4TargetCtx *CtxPtr, const char *counter_name, uint32_t index, uint32_t value);

int main(void) {
    XilVitisNetP4EnvIf EnvIf;
    XilVitisNetP4TargetCtx TargetCtx;
    XilVitisNetP4ReturnType Result;
    uint32_t Index;
    uint32_t IPv4ActionId, IPv6ActionId;

    /* Table contexts for all three P4 programs */
    // Ingress Classifier tables
    XilVitisNetP4TableCtx *LocalIPv4TableCtxPtr;
    XilVitisNetP4TableCtx *StaticPortsIPv4TableCtxPtr;
    XilVitisNetP4TableCtx *DynamicPortsIPv4TableCtxPtr;
    XilVitisNetP4TableCtx *LocalIPv6TableCtxPtr;
    XilVitisNetP4TableCtx *StaticPortsIPv6TableCtxPtr;
    XilVitisNetP4TableCtx *DynamicPortsIPv6TableCtxPtr;

    // Ingress Translator tables
    XilVitisNetP4TableCtx *DestIATableCtxPtr;
    XilVitisNetP4TableCtx *SourceTranslation46TableCtxPtr;
    XilVitisNetP4TableCtx *DestTranslation46TableCtxPtr;
    XilVitisNetP4TableCtx *SCMPTableCtxPtr;

    // Egress Translator tables
    XilVitisNetP4TableCtx *PathMetaTableCtxPtr;
    XilVitisNetP4TableCtx *Inf0TableCtxPtr;
    XilVitisNetP4TableCtx *Inf1TableCtxPtr;
    XilVitisNetP4TableCtx *Inf2TableCtxPtr;
    XilVitisNetP4TableCtx *HopField0TableCtxPtr;
    XilVitisNetP4TableCtx *SrcAddrTableCtxPtr;
    XilVitisNetP4TableCtx *DstHostTableCtxPtr;
    XilVitisNetP4TableCtx *ClassifierStage1TableCtxPtr;
    XilVitisNetP4TableCtx *ClassifierStage2TableCtxPtr;
    XilVitisNetP4TableCtx *PathTableCtxPtr;
    XilVitisNetP4TableCtx *NextHopTableCtxPtr;
    XilVitisNetP4TableCtx *ICMPTableCtxPtr;

    XilVitisNetP4EnvIf *EnvIfPtr = &EnvIf;
    XilVitisNetP4TargetCtx *TargetCtxPtr = &TargetCtx;

    /* Initialize environment interface */
    EnvIfPtr->WordWrite32 = env_write;
    EnvIfPtr->WordRead32 = env_read;
    EnvIfPtr->LogError = example_log_info;
    EnvIfPtr->LogInfo = example_log_info;
    EnvIfPtr->UserCtx = (XilVitisNetP4UserCtxType)calloc(1, sizeof(ExampleUserContext));
    if (EnvIfPtr->UserCtx == NULL) {
        printf("ERROR: Failed to allocate memory\n\r");
        return -1;
    }
    ((ExampleUserContext *)EnvIfPtr->UserCtx)->VitisNetP4Address = C_P2P_BASE_ADDR;

    /* Open device */
    printf("Opening pcimem device\n\r");
    if (device_open(sysfile_path)) {
        printf("Failed to open device\n");
        free(EnvIfPtr->UserCtx);
        return -1;
    }
    sleep(1);

    /* ================= Initialize Ingress Classifier ================= */
    printf("\n=== Initializing Ingress Classifier ===\n\r");
    ((ExampleUserContext *)EnvIfPtr->UserCtx)->VitisNetP4Address = C_P2P_BASE_ADDR;

    /* Initialize the target driver for classifier */
    printf("Initialize the Target Driver for Classifier\n\r");
    Result = XilVitisNetP4TargetInit(TargetCtxPtr, EnvIfPtr, &XilVitisNetP4TargetConfig_vitis_net_p4_0);

    if (Result == XIL_VITIS_NET_P4_TARGET_ERR_INCOMPATIBLE_SW_HW) {
        printf("Found IP and SW version differences:\n\r");
        DisplayVitisNetP4Versions(TargetCtxPtr);
        goto exit_example;
    }
    else if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto exit_example;
    }

    /* Get IPv4 table handles */
    printf("Get IPv4 Table Handles\n\r");
    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_local_addr_ipv4", &LocalIPv4TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_static_ports_ipv4", &StaticPortsIPv4TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_dynamic_ports_ipv4", &DynamicPortsIPv4TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    /* Get IPv6 table handles */
    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_local_addr_ipv6", &LocalIPv6TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_static_ports_ipv6", &StaticPortsIPv6TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_dynamic_ports_ipv6", &DynamicPortsIPv6TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    /* Get IPv4 action IDs */
    printf("Get IPv4 Action IDs\n\r");
    Result = XilVitisNetP4TableGetActionId(StaticPortsIPv4TableCtxPtr, "static_ipv4_is_scion", &IPv4ActionId);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    /* Get IPv6 action IDs */
    Result = XilVitisNetP4TableGetActionId(StaticPortsIPv6TableCtxPtr, "static_ipv6_is_scion", &IPv6ActionId);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    /* Insert entries into IPv4 tables */
    printf("\nInsert Local IPv4 Table Entries\n\r");
    for (Index = 0; Index < EXAMPLE_NUM_TABLE_ENTRIES; Index++) {
        printf("Inserting entry %d: %d.%d.%d.%d\n", Index,
               LocalIPv4KeyArray[Index][0], LocalIPv4KeyArray[Index][1],
               LocalIPv4KeyArray[Index][2], LocalIPv4KeyArray[Index][3]);

        Result = XilVitisNetP4TableInsert(LocalIPv4TableCtxPtr,
                                     LocalIPv4KeyArray[Index],
                                     NULL,
                                     0x0,
                                     XIL_VITIS_NET_P4_ACTION_ID_NO_ACTION,
                                     NULL);
        if (Result != XIL_VITIS_NET_P4_SUCCESS) {
            DISPLAY_ERROR(Result);
            goto target_exit;
        }
    }

    printf("\nInsert Static Ports IPv4 Table Entries\n\r");
    for (Index = 0; Index < EXAMPLE_NUM_TABLE_ENTRIES; Index++) {
        printf("Inserting entry %d: Port %d\n", Index,
               (StaticPortsIPv4KeyArray[Index][0] << 8) | StaticPortsIPv4KeyArray[Index][1]);

        Result = XilVitisNetP4TableInsert(StaticPortsIPv4TableCtxPtr,
                                     StaticPortsIPv4KeyArray[Index],
                                     NULL,
                                     0x0,
                                     IPv4ActionId,
                                     NULL);
        if (Result != XIL_VITIS_NET_P4_SUCCESS) {
            DISPLAY_ERROR(Result);
            goto target_exit;
        }
    }

    printf("\nInsert Dynamic Ports IPv4 Table Entries\n\r");
    for (Index = 0; Index < EXAMPLE_NUM_TABLE_ENTRIES; Index++) {
        printf("Inserting entry %d: Src %d.%d.%d.%d:%d, Dst Port %d\n", Index,
               DynamicPortsIPv4KeyArray[Index][0], DynamicPortsIPv4KeyArray[Index][1],
               DynamicPortsIPv4KeyArray[Index][2], DynamicPortsIPv4KeyArray[Index][3],
               (DynamicPortsIPv4KeyArray[Index][4] << 8) | DynamicPortsIPv4KeyArray[Index][5],
               (DynamicPortsIPv4KeyArray[Index][6] << 8) | DynamicPortsIPv4KeyArray[Index][7]);

        Result = XilVitisNetP4TableInsert(DynamicPortsIPv4TableCtxPtr,
                                     DynamicPortsIPv4KeyArray[Index],
                                     NULL,
                                     0x0,
                                     IPv4ActionId,
                                     DynamicPortsActionParamsArray[Index]);
        if (Result != XIL_VITIS_NET_P4_SUCCESS) {
            DISPLAY_ERROR(Result);
            goto target_exit;
        }
    }

    /* Insert entries into IPv6 tables */
    printf("\nInsert Local IPv6 Table Entries\n\r");
    for (Index = 0; Index < EXAMPLE_NUM_TABLE_ENTRIES; Index++) {
        printf("Inserting entry %d\n", Index);

        Result = XilVitisNetP4TableInsert(LocalIPv6TableCtxPtr,
                                     LocalIPv6KeyArray[Index],
                                     NULL,
                                     0x0,
                                     XIL_VITIS_NET_P4_ACTION_ID_NO_ACTION,
                                     NULL);
        if (Result != XIL_VITIS_NET_P4_SUCCESS) {
            DISPLAY_ERROR(Result);
            goto target_exit;
        }
    }

    printf("\nInsert Static Ports IPv6 Table Entries\n\r");
    for (Index = 0; Index < EXAMPLE_NUM_TABLE_ENTRIES; Index++) {
        printf("Inserting entry %d: Port %d\n", Index,
               (StaticPortsIPv4KeyArray[Index][0] << 8) | StaticPortsIPv4KeyArray[Index][1]);

        Result = XilVitisNetP4TableInsert(StaticPortsIPv6TableCtxPtr,
                                     StaticPortsIPv4KeyArray[Index], // Same port numbers
                                     NULL,
                                     0x0,
                                     IPv6ActionId,
                                     NULL);
        if (Result != XIL_VITIS_NET_P4_SUCCESS) {
            DISPLAY_ERROR(Result);
            goto target_exit;
        }
    }

    printf("\nInsert Dynamic Ports IPv6 Table Entries\n\r");
    for (Index = 0; Index < EXAMPLE_NUM_TABLE_ENTRIES; Index++) {
        printf("Inserting entry %d\n", Index);

        Result = XilVitisNetP4TableInsert(DynamicPortsIPv6TableCtxPtr,
                                     DynamicPortsIPv6KeyArray[Index],
                                     NULL,
                                     0x0,
                                     IPv6ActionId,
                                     DynamicPortsActionParamsArray[Index]);
        if (Result != XIL_VITIS_NET_P4_SUCCESS) {
            DISPLAY_ERROR(Result);
            goto target_exit;
        }
    }

    /* ================= Initialize Ingress Translator ================= */
    printf("\n=== Initializing Ingress Translator ===\n\r");
    ((ExampleUserContext *)EnvIfPtr->UserCtx)->VitisNetP4Address = C_NEW_BASE_ADDR;

    /* Get Ingress Translator table handles */
    printf("Get Ingress Translator Table Handles\n\r");
    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_dest_ia", &DestIATableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_source_translation_46", &SourceTranslation46TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_dest_translation_46", &DestTranslation46TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_scmp", &SCMPTableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    /* Insert entries into Ingress Translator tables */
    printf("\nInsert Destination IA Table Entries\n\r");
    // Example entries for destination ISD-ASN validation
    uint8_t destIAKey1[6] = {0x00, 0x01, 0x00, 0x00, 0x00, 0x01}; // ISD 1, AS 1
    uint8_t destIAKey2[6] = {0x00, 0x01, 0x00, 0x00, 0x00, 0x02}; // ISD 1, AS 2

    Result = XilVitisNetP4TableInsert(DestIATableCtxPtr, destIAKey1, NULL, 0x0, XIL_VITIS_NET_P4_ACTION_ID_NO_ACTION, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TableInsert(DestIATableCtxPtr, destIAKey2, NULL, 0x0, XIL_VITIS_NET_P4_ACTION_ID_NO_ACTION, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    printf("\nInsert Source Translation Table Entries\n\r");
    // Example entries for source address translation
    uint8_t sourceTransKey1[2] = {0x00, 0x00}; // BGP-style ASNs
    uint8_t sourceTransKey2[2] = {0x00, 0x20}; // SCION-style ASNs

    Result = XilVitisNetP4TableInsert(SourceTranslation46TableCtxPtr, sourceTransKey1, NULL, 0x0, 0, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TableInsert(SourceTranslation46TableCtxPtr, sourceTransKey2, NULL, 0x0, 1, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    printf("\nInsert Destination Translation Table Entries\n\r");
    // Example entries for destination address translation
    uint8_t destTransKey1[2] = {0x00, 0x00}; // BGP-style ASNs
    uint8_t destTransKey2[2] = {0x00, 0x20}; // SCION-style ASNs

    Result = XilVitisNetP4TableInsert(DestTranslation46TableCtxPtr, destTransKey1, NULL, 0x0, 0, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TableInsert(DestTranslation46TableCtxPtr, destTransKey2, NULL, 0x0, 1, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    printf("\nInsert SCMP Translation Table Entries\n\r");
    // Example entries for SCMP translation
    uint8_t scmpKey1[1] = {SCMP_DestUnreach}; // Destination Unreachable
    uint8_t scmpKey2[1] = {SCMP_PacketTooBig}; // Packet Too Big
    uint8_t scmpKey3[1] = {SCMP_EchoRequest};  // Echo Request

    Result = XilVitisNetP4TableInsert(SCMPTableCtxPtr, scmpKey1, NULL, 0x0, 0, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TableInsert(SCMPTableCtxPtr, scmpKey2, NULL, 0x0, 0, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TableInsert(SCMPTableCtxPtr, scmpKey3, NULL, 0x0, 1, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    /* ================= Initialize Egress Translator ================= */
    printf("\n=== Initializing Egress Translator ===\n\r");
    ((ExampleUserContext *)EnvIfPtr->UserCtx)->VitisNetP4Address = C_EGRESS_BASE_ADDR;

    /* Get Egress Translator table handles */
    printf("Get Egress Translator Table Handles\n\r");
    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_path_meta", &PathMetaTableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_inf_0", &Inf0TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_inf_1", &Inf1TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_inf_2", &Inf2TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_hf_0", &HopField0TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_src_addr", &SrcAddrTableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_dst_host", &DstHostTableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_classifier_stage1", &ClassifierStage1TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_classifier_stage2", &ClassifierStage2TableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_path", &PathTableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_next_hop", &NextHopTableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TargetGetTableByName(TargetCtxPtr, "tab_icmp", &ICMPTableCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    /* Insert entries into Egress Translator tables */
    printf("\nInsert Path Meta Table Entries\n\r");
    // Example path meta entries
    uint8_t pathMetaKey1[2] = {0x00, 0x01}; // Path ID 1
    uint8_t pathMetaParams1[5] = {0x00, 0x00, 0x01, 0x00, 0x00}; // curr_inf=0, curr_hf=0, seg0_len=1

    Result = XilVitisNetP4TableInsert(PathMetaTableCtxPtr, pathMetaKey1, NULL, 0x0, 0, pathMetaParams1);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    printf("\nInsert Info Field Table Entries\n\r");
    // Example info field entries
    uint8_t inf0Key1[2] = {0x00, 0x01}; // Path ID 1
    uint64_t inf0Data1 = 0x0000000100000000; // seg_id=1, tstamp=0

    Result = XilVitisNetP4TableInsert(Inf0TableCtxPtr, inf0Key1, NULL, 0x0, 1, (uint8_t*)&inf0Data1);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    printf("\nInsert Hop Field Table Entries\n\r");
    // Example hop field entries
    uint8_t hf0Key1[2] = {0x00, 0x01}; // Path ID 1
    uint8_t hf0Data1[12] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00}; // ig_if=1, eg_if=2

    Result = XilVitisNetP4TableInsert(HopField0TableCtxPtr, hf0Key1, NULL, 0x0, 1, hf0Data1);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    printf("\nInsert Source Address Table Entries\n\r");
    // Example source address entries
    uint8_t srcAddrKey1[16] = {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,1}; // 2001:db8::1
    uint8_t srcAddrParams1[10] = {0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x20,0x01,0x0d,0xb8}; // ISD 1, AS 1, IP 2001:db8::1

    Result = XilVitisNetP4TableInsert(SrcAddrTableCtxPtr, srcAddrKey1, NULL, 0x0, 0, srcAddrParams1);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    printf("\nInsert Destination Host Table Entries\n\r");
    // Example destination host entries
    uint8_t dstHostKey1[16] = {0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,2}; // 2001:db8::2
    uint8_t dstHostParams1[10] = {0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x20,0x01,0x0d,0xb8}; // ISD 1, AS 2, IP 2001:db8::2

    Result = XilVitisNetP4TableInsert(DstHostTableCtxPtr, dstHostKey1, NULL, 0x0, 0, dstHostParams1);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    printf("\nInsert Path Table Entries\n\r");
    // Example path entries
    uint8_t pathKey1[10] = {0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00}; // ISD 1, AS 2, traffic_class=0
    uint8_t pathParams1[6] = {0x00, 0x01, 0x00, 0x05, 0x04, 0xD2}; // path_index=1, next_hop=0, path_len=5, mps=1234

    Result = XilVitisNetP4TableInsert(PathTableCtxPtr, pathKey1, NULL, 0x0, 0, pathParams1);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    printf("\nInsert Next Hop Table Entries\n\r");
    // Example next hop entries
    uint8_t nextHopKey1[1] = {0x00}; // Next hop ID 0
    uint8_t nextHopParams1[22] = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55, // MAC
                                  0xC0, 0xA8, 0x01, 0x01,             // src IP 192.168.1.1
                                  0xC0, 0xA8, 0x01, 0x02,             // dst IP 192.168.1.2
                                  0x79, 0x18};                        // port 31000

    Result = XilVitisNetP4TableInsert(NextHopTableCtxPtr, nextHopKey1, NULL, 0x0, 0, nextHopParams1);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    printf("\nInsert ICMP Translation Table Entries\n\r");
    // Example ICMP translation entries
    uint8_t icmpKey1[2] = {0x00, ICMP6_TYPE_PacketTooBig}; // Packet Too Big
    uint8_t icmpKey2[2] = {0x00, ICMP6_TYPE_EchoRequest};  // Echo Request

    Result = XilVitisNetP4TableInsert(ICMPTableCtxPtr, icmpKey1, NULL, 0x0, 0, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    Result = XilVitisNetP4TableInsert(ICMPTableCtxPtr, icmpKey2, NULL, 0x0, 1, NULL);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        DISPLAY_ERROR(Result);
        goto target_exit;
    }

    /* ================= Counters ================= */
    printf("\n=== Counter Initialization ===\n\r");
    printf("Updating packet counters...\n");

    // Ingress Classifier counters
    ((ExampleUserContext *)EnvIfPtr->UserCtx)->VitisNetP4Address = C_P2P_BASE_ADDR;
    update_counter(TargetCtxPtr, "cnt_packets", CNT_SCION_IPV4, 100);
    update_counter(TargetCtxPtr, "cnt_packets", CNT_SCION_IPV6, 50);
    update_counter(TargetCtxPtr, "cnt_dynamic_ipv4_hit", 0, 1);
    update_counter(TargetCtxPtr, "cnt_dynamic_ipv6_hit", 0, 1);

    // Ingress Translator counters
    ((ExampleUserContext *)EnvIfPtr->UserCtx)->VitisNetP4Address = C_NEW_BASE_ADDR;
    update_counter(TargetCtxPtr, "cntDropped", CNT_DROP_PARSER, 10);
    update_counter(TargetCtxPtr, "cntTranslated", CNT_SCMP, 5);

    // Egress Translator counters
    ((ExampleUserContext *)EnvIfPtr->UserCtx)->VitisNetP4Address = C_EGRESS_BASE_ADDR;
    update_counter(TargetCtxPtr, "cnt_dropped", CNT_EGRESS_DROP_PARSER, 3);
    update_counter(TargetCtxPtr, "cnt_tdest", 0, 1000);

    printf("\n=== Table Verification ===\n\r");
    /* Example query of a table entry */
    uint32_t ReadPriority;
    uint32_t ReadActionId;
    uint8_t ReadParamActionsBuffer[2];

    printf("\nQuerying Static Ports IPv4 Table...\n\r");
    ((ExampleUserContext *)EnvIfPtr->UserCtx)->VitisNetP4Address = C_P2P_BASE_ADDR;
    for (Index = 0; Index < EXAMPLE_NUM_TABLE_ENTRIES; Index++) {
        Result = XilVitisNetP4TableGetByKey(StaticPortsIPv4TableCtxPtr,
                                        StaticPortsIPv4KeyArray[Index],
                                        NULL,
                                        &ReadPriority,
                                        &ReadActionId,
                                        ReadParamActionsBuffer);
        if (Result == XIL_VITIS_NET_P4_SUCCESS) {
            printf("Entry %d: ActionId=%d\n", Index, ReadActionId);
        } else {
            printf("Failed to query entry %d\n", Index);
            DISPLAY_ERROR(Result);
        }
    }

    printf("\nQuerying SCMP Translation Table...\n\r");
    ((ExampleUserContext *)EnvIfPtr->UserCtx)->VitisNetP4Address = C_NEW_BASE_ADDR;
    uint8_t scmpQueryKey[1] = {SCMP_EchoRequest};
    Result = XilVitisNetP4TableGetByKey(SCMPTableCtxPtr,
                                    scmpQueryKey,
                                    NULL,
                                    &ReadPriority,
                                    &ReadActionId,
                                    ReadParamActionsBuffer);
    if (Result == XIL_VITIS_NET_P4_SUCCESS) {
        printf("SCMP EchoRequest: ActionId=%d\n", ReadActionId);
    } else {
        printf("Failed to query SCMP table\n");
        DISPLAY_ERROR(Result);
    }

    printf("\nQuerying Path Table...\n\r");
    ((ExampleUserContext *)EnvIfPtr->UserCtx)->VitisNetP4Address = C_EGRESS_BASE_ADDR;
    uint8_t pathQueryKey[10] = {0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00};
    Result = XilVitisNetP4TableGetByKey(PathTableCtxPtr,
                                    pathQueryKey,
                                    NULL,
                                    &ReadPriority,
                                    &ReadActionId,
                                    ReadParamActionsBuffer);
    if (Result == XIL_VITIS_NET_P4_SUCCESS) {
        printf("Path to ISD 1 AS 2: ActionId=%d\n", ReadActionId);
    } else {
        printf("Failed to query Path table\n");
        DISPLAY_ERROR(Result);
    }

    printf("\nInitialization Complete\n\r");

target_exit:
    printf("Closing pcimem device\n");
    device_close();
    Result = XilVitisNetP4TargetExit(TargetCtxPtr);

exit_example:
    free(EnvIfPtr->UserCtx);
    return Result;
}

/* Counter function implementation */
XilVitisNetP4ReturnType update_counter(
    XilVitisNetP4TargetCtx *CtxPtr,
    const char *counter_name,
    uint32_t index,
    uint32_t value) {

    XilVitisNetP4CounterCtx *counterCtx;
    XilVitisNetP4ReturnType Result;

    Result = XilVitisNetP4TargetGetCounterByName(CtxPtr, counter_name, &counterCtx);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        printf("Failed to get counter %s: %s\n", counter_name, XilVitisNetP4ReturnTypeToString(Result));
        return Result;
    }

    Result = XilVitisNetP4CounterWrite(counterCtx, index, value);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) {
        printf("Failed to update counter %s at index %d: %s\n",
               counter_name, index, XilVitisNetP4ReturnTypeToString(Result));
    } else {
        printf("Updated counter %s[%d] = %d\n", counter_name, index, value);
    }

    return Result;
}

/* Helper function implementations */
static void DisplayVitisNetP4Versions(XilVitisNetP4TargetCtx *CtxPtr) {
    XilVitisNetP4ReturnType Result;
    XilVitisNetP4Version SwVersion;
    XilVitisNetP4Version IpVersion;
    XilVitisNetP4TargetBuildInfoCtx *BuildInfoCtxPtr;

    Result = XilVitisNetP4TargetGetSwVersion(CtxPtr, &SwVersion);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) return;

    Result = XilVitisNetP4TargetGetBuildInfoDrv(CtxPtr, &BuildInfoCtxPtr);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) return;

    Result = XilVitisNetP4TargetBuildInfoGetIpVersion(BuildInfoCtxPtr, &IpVersion);
    if (Result != XIL_VITIS_NET_P4_SUCCESS) return;

    printf("----VitisNetP4Runtime Software Version\n");
    printf("\t\t Major = %d\n", SwVersion.Major);
    printf("\t\t Minor = %d\n", SwVersion.Minor);
    printf("\n");

    printf("----VitisNetP4IP Version\n");
    printf("\t\t Major = %d\n", IpVersion.Major);
    printf("\t\t Minor = %d\n", IpVersion.Minor);
}

XilVitisNetP4ReturnType example_log_info(XilVitisNetP4EnvIf *EnvIfPtr, const char *MessagePtr) {
    if (EnvIfPtr == NULL || MessagePtr == NULL) {
        return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;
    }
    printf("%s", MessagePtr);
    return XIL_VITIS_NET_P4_SUCCESS;
}

int device_open(char *file_name) {
    if ((sysfile = open(file_name, O_RDWR | O_SYNC)) < 0) {
        fprintf(stderr, "Error opening sysfile: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

int device_close() {
    return close(sysfile);
}

void device_write(uint32_t address, uint32_t data) {
    void *region;
    void *virtual;
    off_t addr = (off_t)address;
    off_t offset = addr & (-4096);
    off_t rem = addr & 0xFFF;
    size_t length = 4096;

    region = mmap(0, length, PROT_WRITE, MAP_SHARED, sysfile, offset);
    if (region == MAP_FAILED) {
        fprintf(stderr, "Error calling mmap: mapping failed\n");
        exit(-1);
    }
    virtual = region + rem;
    *((uint32_t *)virtual) = data;

    if(munmap(region, length) < 0) {
        fprintf(stderr, "Error calling munmap: %s\n", strerror(errno));
        exit(-1);
    }
}

uint32_t device_read(uint32_t address, uint32_t *data) {
    void *region;
    void *virtual;
    off_t addr = (off_t)address;
    off_t offset = addr & (-4096);
    off_t rem = addr & 0xFFF;
    size_t length = 4096;

    region = mmap(0, length, PROT_READ, MAP_SHARED, sysfile, offset);
    if (region == MAP_FAILED) {
        fprintf(stderr, "Error calling mmap: mapping failed\n");
        exit(-1);
    }
    virtual = region + rem;
    *data = *((uint32_t *)virtual);

    if(munmap(region, length) < 0) {
        fprintf(stderr, "Error calling munmap: %s\n", strerror(errno));
        exit(-1);
    }
    return 0;
}

XilVitisNetP4ReturnType env_write(XilVitisNetP4EnvIf *EnvIfPtr, XilVitisNetP4AddressType Address, uint32_t WriteValue) {
    ExampleUserContext *UserCtxPtr;
    if (EnvIfPtr == NULL || EnvIfPtr->UserCtx == NULL) {
        return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;
    }
    UserCtxPtr = (ExampleUserContext *)EnvIfPtr->UserCtx;

    void *region;
    void *virtual;
    off_t addr = (off_t)UserCtxPtr->VitisNetP4Address + Address;
    off_t offset = addr & (-4096);
    off_t rem = addr & 0xFFF;
    size_t length = 4096;

    region = mmap(0, length, PROT_WRITE, MAP_SHARED, sysfile, offset);
    if (region == MAP_FAILED) {
        fprintf(stderr, "Error calling mmap: mapping failed\n");
        exit(-1);
    }
    virtual = region + rem;
    *((uint32_t *)virtual) = WriteValue;

    if(munmap(region, length) < 0) {
        fprintf(stderr, "Error calling munmap: %s\n", strerror(errno));
        exit(-1);
    }

    return XIL_VITIS_NET_P4_SUCCESS;
}

XilVitisNetP4ReturnType env_read(XilVitisNetP4EnvIf *EnvIfPtr, XilVitisNetP4AddressType Address, uint32_t *ReadValuePtr) {
    ExampleUserContext *UserCtxPtr;
    if (EnvIfPtr == NULL || ReadValuePtr == NULL || EnvIfPtr->UserCtx == NULL) {
        return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;
    }
    UserCtxPtr = (ExampleUserContext *)EnvIfPtr->UserCtx;

    void *region;
    void *virtual;
    off_t addr = (off_t)UserCtxPtr->VitisNetP4Address + Address;
    off_t offset = addr & (-4096);
    off_t rem = addr & 0xFFF;
    size_t length = 4096;

    region = mmap(0, length, PROT_READ, MAP_SHARED, sysfile, offset);
    if (region == MAP_FAILED) {
        fprintf(stderr, "Error calling mmap: mapping failed\n");
        exit(-1);
    }
    virtual = region + rem;
    *ReadValuePtr = *((uint32_t *)virtual);

    if(munmap(region, length) < 0) {
        fprintf(stderr, "Error calling munmap: %s\n", strerror(errno));
        exit(-1);
    }
    return XIL_VITIS_NET_P4_SUCCESS;
}
