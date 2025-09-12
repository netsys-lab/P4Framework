#include "device.h"
#include "p4_target.h"
#include "include/vitis_net_p4_0_defs.h"
#include "include/vitis_net_p4_1_defs.h"
#include "include/vitis_net_p4_2_defs.h"
#include "include/vitis_net_p4_3_defs.h"
#include "include/vitisnetp4_common.h"

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <getopt.h>
#include <readline/history.h>
#include <readline/readline.h>
#include <unistd.h>

int parse_args(int argc, char* argv[]);
void enable_port0(struct Device* dev);
void print_counters(struct P4Target* target);

#define TARGET_COUNT 3
#define TARGET_IG_CLASSIFIER 0
#define TARGET_IG_TRANSLATOR 1
#define TARGET_EG_TRANSLATOR 2
// #define TARGET_EG_CHECKSUM 3

const XilVitisNetP4AddressType BASE_ADDR_IG_CLASSIFIER = 0x100000;
const XilVitisNetP4AddressType BASE_ADDR_IG_TRANSLATOR = 0x200000;
const XilVitisNetP4AddressType BASE_ADDR_EG_TRANSLATOR = 0x300000;
// const XilVitisNetP4AddressType BASE_ADDR_EG_CHECKSUM   = 0x300000;

char* SYSFILE_PATH = "/sys/devices/pci0000:b2/0000:b2:00.0/0000:b3:00.0/resource2";

static const char* CLI_HELP =
    "Commands:\n"
    "exit, quit         Exit the program\n"
    "help               Show this text\n"
    "peek <addr>        Read a single word from configuration memory\n"
    "poke <addr> <word> Write a single word to configuration memory\n"
    "counters           Print all counter values";

//////////
// Main //
//////////

int main(int argc, char* argv[])
{
    XilVitisNetP4ReturnType result;
    struct P4Target targets[TARGET_COUNT] = {{0}};
    struct Device device = {0};

    int res = 0;
    if ((res = parse_args(argc, argv))) return res;

    printf("Open target device %s\n", SYSFILE_PATH);
    if (device_open(&device, SYSFILE_PATH))
        goto cleanup;
    sleep(1); // ?

    printf("Enable CMAC port 0\n");
    enable_port0(&device);

    printf("Initialize driver\n");
    printf("Ingress Classifier\n");
    result = init_target(&targets[TARGET_IG_CLASSIFIER], &device,
        BASE_ADDR_IG_CLASSIFIER, &XilVitisNetP4TargetConfig_vitis_net_p4_0);
    if (result) goto cleanup;
    printf("Ingress Translator\n");
    result = init_target(&targets[TARGET_IG_TRANSLATOR], &device,
        BASE_ADDR_IG_TRANSLATOR, &XilVitisNetP4TargetConfig_vitis_net_p4_1);
    if (result) goto cleanup;
    printf("Egress Translator\n");
    result = init_target(&targets[TARGET_EG_TRANSLATOR], &device,
        BASE_ADDR_EG_TRANSLATOR, &XilVitisNetP4TargetConfig_vitis_net_p4_2);
    if (result) goto cleanup;
    // printf("Egress Checksum\n");
    // result = init_target(&targets[TARGET_EG_CHECKSUM], &device,
    //     BASE_ADDR_EG_CHECKSUM, &XilVitisNetP4TargetConfig_vitis_net_p4_3);
    // if (result) goto cleanup;

    targets[TARGET_IG_CLASSIFIER].prog_name = "Ingress Classifier";
    targets[TARGET_IG_TRANSLATOR].prog_name = "Ingress Translator";
    targets[TARGET_EG_TRANSLATOR].prog_name = "Egress Translator";
    // targets[TARGET_EG_CHECKSUM].prog_name = "Egress Checksum";

    bool run = true;
    static const char* delim = " ";
    while (run)
    {
        char* line = readline("scitra> ");
        if (!line || line[0] == '\0') continue;
        add_history(line);
        char* tok = strtok(line, delim);
        if (tok) {
            if (strcmp(tok, "exit") == 0 || strcmp(tok, "quit") == 0)
            {
                run = false;
            }
            else if (strcmp(tok, "help") == 0)
            {
                puts(CLI_HELP);
            }
            else if (strcmp(tok, "peek") == 0)
            {
                tok = strtok(NULL, delim);
                if (!tok) { puts("syntax error"); continue; }
                uint32_t addr = strtol(tok, NULL, 16);
                if (addr & 0x03) { puts("alignment error"); continue; }
                printf("0x%08x\n", device_read32(&device, addr));
            }
            else if (strcmp(tok, "poke") == 0)
            {
                tok = strtok(NULL, delim);
                if (!tok) { puts("syntax error"); continue; }
                uint32_t addr = strtol(tok, NULL, 16);
                if (addr & 0x03) { puts("alignment error"); continue; }
                tok = strtok(NULL, delim);
                if (!tok) { puts("syntax error"); continue; }
                uint32_t data = strtol(tok, NULL, 16);
                device_write32(&device, addr, data);
            }
            else if (strcmp(tok, "counters") == 0)
            {
                for (size_t i = 0; i < TARGET_COUNT; ++i)
                    print_counters(&targets[i]);
            }
            else
            {
                puts("syntax error");
            }
        }
        free(line);
    }

cleanup:
    for (size_t i = 0; i < 4; ++i)
        exit_target(&targets[i]);
    device_close(&device);
    return 0;
}

int parse_args(int argc, char* argv[])
{
    int opt = 0;
    while ((opt = getopt(argc, argv, "hd:")) != -1)
    {
        switch (opt)
        {
        case 'd':
            SYSFILE_PATH = optarg;
            break;
        case 'h':
        default:
            printf("Usage: %s [-d <sysfile>]\n", argv[0]);
            return 1;
        }
    }
    return 0;
}

//////////
// CMAC //
//////////

void enable_port0(struct Device* dev)
{
    device_write32(dev, 0x8014, 0x1);
    device_write32(dev, 0x800c, 0x1);
    // why two reads?
    printf("Read 0x8294: 0x%08x\n", device_read32(dev, 0x8204));
    printf("Read 0x8294: 0x%08x\n", device_read32(dev, 0x8204));
    sleep(1); // ?
};

//////////////
// Counters //
//////////////

void print_counters(struct P4Target* target)
{
    XilVitisNetP4ReturnType result;
    printf("=== %s ===\n", target->prog_name);
    if (target->counters == NULL) return;
    for (uint32_t i = 0; i < target->config->CounterListSize; ++i)
    {
        printf("%s =", target->config->CounterListPtr[i]->NameStringPtr);
        uint32_t n = target->config->CounterListPtr[i]->Config.NumCounters;
        uint64_t* values = calloc(n, sizeof(uint64_t));
        result = XilVitisNetP4CounterCollectRead(&target->counters[i], 0, n, values);
        if (result == XIL_VITIS_NET_P4_SUCCESS)
        {
            for (uint32_t j = 0; j < n; ++j)
                printf(" %lu", values[j]);
            putchar('\n');
        }
        else
            puts(" error");
        free(values);
    }
}
