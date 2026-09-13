//OVGU_Magdeburg_FIN


#include "device.h"
#include "p4_target.h"
#include "include/vitis_net_p4_0_defs.h"
#include "include/vitis_net_p4_1_defs.h"
#include "include/vitis_net_p4_2_defs.h"
#include "include/vitisnetp4_common.h"

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdbool.h>

#include <getopt.h>
#include <readline/history.h>
#include <readline/readline.h>
#include <unistd.h>

int parse_args(int argc, char* argv[]);
void enable_port0(struct Device* dev);
void print_counters(struct P4Target* target);

static int hex_to_bytes(const char* hex, uint8_t* out, size_t max_len);
static void print_bytes(const uint8_t* buf, size_t len);
static XilVitisNetP4ReturnType cache_all_tables(struct P4Target* targets);
static XilVitisNetP4ReturnType table_insert_cmd(struct P4Target* targets, const char* table_name,
    const char* key_hex, const char* action_name, const char* param_hex);
static XilVitisNetP4ReturnType table_update_cmd(struct P4Target* targets, const char* table_name,
    const char* key_hex, const char* action_name, const char* param_hex);
static XilVitisNetP4ReturnType table_get_cmd(struct P4Target* targets, const char* table_name,
    const char* key_hex);
static XilVitisNetP4ReturnType table_delete_cmd(struct P4Target* targets, const char* table_name,
    const char* key_hex);
static XilVitisNetP4ReturnType table_mode_cmd(const char* table_name);
static void list_tables(void);

// Three targets -- vitis_net_p4_3 (egress_checksum_p4) has no AXIL interface
#define TARGET_COUNT 3
#define TARGET_CLASSIFIER 0
#define TARGET_INGRESS_TRANSLATOR 1
#define TARGET_EGRESS_TRANSLATOR 2

// Addresses per this project's confirmed address map (box0 system base
// 0x100000, stock/unchanged -- box0's total footprint across all four
// slaves fits inside its existing 1MB window, so system_config was never
// modified for this project):
//   Egress translator  (local 0x00000): system 0x100000 + 0x00000 = 0x100000
//   Classifier          (local 0x80000): system 0x100000 + 0x80000 = 0x180000
//   Ingress translator   (local 0xC0000): system 0x100000 + 0xC0000 = 0x1C0000
//   Dummy                (local 0xE0000): system 0x100000 + 0xE0000 = 0x1E0000 (unused by driver)
const XilVitisNetP4AddressType BASE_ADDR_CLASSIFIER          = 0x180000;
const XilVitisNetP4AddressType BASE_ADDR_INGRESS_TRANSLATOR  = 0x1C0000;
const XilVitisNetP4AddressType BASE_ADDR_EGRESS_TRANSLATOR   = 0x100000;

char* SYSFILE_PATH = "/sys/devices/pci0000:b2/0000:b2:00.0/0000:b3:00.0/resource2";

static const char* CLI_HELP =
    "Commands:\n"
    "exit, quit         Exit the program\n"
    "help               Show this text\n"
    "peek <addr>        Read a single word from configuration memory\n"
    "poke <addr> <word> Write a single word to configuration memory\n"
    "counters           Print all counter values\n"
    "tables             List known tables and their key byte widths\n"
    "tmode <table>      Query a table's actual CAM implementation mode\n"
    "tinsert <table> <key_hex> <action> [param_hex]  Insert a table entry\n"
    "tupdate <table> <key_hex> <action> [param_hex]  Update a table entry's action\n"
    "tget <table> <key_hex>                          Look up an entry by key\n"
    "tdelete <table> <key_hex>                       Delete an entry by key\n"
    "\n"
    "  <key_hex> and [param_hex] are plain hex strings, no spaces or 0x prefix,\n"
    "  e.g. 0a000005 for IPv4 10.0.0.5. Run 'tables' to see each table's\n"
    "  required key byte width and field order.";

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
    sleep(1);

    printf("Enable CMAC port 0\n");
    enable_port0(&device);

    printf("Initialize driver\n");

    printf("Ingress Classifier\n");
    result = init_target(&targets[TARGET_CLASSIFIER], &device,
        BASE_ADDR_CLASSIFIER, &XilVitisNetP4TargetConfig_vitis_net_p4_0);
    if (result) { printf("init_target failed: %d (%s)\n", result, XilVitisNetP4ReturnTypeToString(result)); goto cleanup; }
    targets[TARGET_CLASSIFIER].prog_name = "Ingress Classifier";

    printf("Ingress Translator\n");
    result = init_target(&targets[TARGET_INGRESS_TRANSLATOR], &device,
        BASE_ADDR_INGRESS_TRANSLATOR, &XilVitisNetP4TargetConfig_vitis_net_p4_1);
    if (result) { printf("init_target failed: %d (%s)\n", result, XilVitisNetP4ReturnTypeToString(result)); goto cleanup; }
    targets[TARGET_INGRESS_TRANSLATOR].prog_name = "Ingress Translator";

    printf("Egress Translator\n");
    result = init_target(&targets[TARGET_EGRESS_TRANSLATOR], &device,
        BASE_ADDR_EGRESS_TRANSLATOR, &XilVitisNetP4TargetConfig_vitis_net_p4_2);
    if (result) { printf("init_target failed: %d (%s)\n", result, XilVitisNetP4ReturnTypeToString(result)); goto cleanup; }
    targets[TARGET_EGRESS_TRANSLATOR].prog_name = "Egress Translator";

    // Cache each table's context ONCE here, matching the confirmed-working
    // pattern from the earlier drivers: GetByKey reads from an in-memory
    // shadow copy tied to the context object, not from hardware, so a
    // fresh context per command loses that state.
    result = cache_all_tables(targets);
    if (result != XIL_VITIS_NET_P4_SUCCESS)
        printf("Warning: failed to cache one or more table contexts: %d (%s)\n",
            result, XilVitisNetP4ReturnTypeToString(result));

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
            else if (strcmp(tok, "tables") == 0)
            {
                list_tables();
            }
            else if (strcmp(tok, "tmode") == 0)
            {
                char* table_name = strtok(NULL, delim);
                if (!table_name) { puts("syntax error"); continue; }
                XilVitisNetP4ReturnType r = table_mode_cmd(table_name);
                if (r != XIL_VITIS_NET_P4_SUCCESS)
                    printf("Error %d (%s)\n", r, XilVitisNetP4ReturnTypeToString(r));
            }
            else if (strcmp(tok, "tinsert") == 0 || strcmp(tok, "tupdate") == 0)
            {
                bool is_update = (strcmp(tok, "tupdate") == 0);
                char* table_name = strtok(NULL, delim);
                char* key_hex    = strtok(NULL, delim);
                char* action     = strtok(NULL, delim);
                char* param_hex  = strtok(NULL, delim);
                if (!table_name || !key_hex || !action) { puts("syntax error"); continue; }
                XilVitisNetP4ReturnType r = is_update
                    ? table_update_cmd(targets, table_name, key_hex, action, param_hex)
                    : table_insert_cmd(targets, table_name, key_hex, action, param_hex);
                if (r != XIL_VITIS_NET_P4_SUCCESS)
                    printf("Error %d (%s)\n", r, XilVitisNetP4ReturnTypeToString(r));
                else
                    puts("OK");
            }
            else if (strcmp(tok, "tget") == 0)
            {
                char* table_name = strtok(NULL, delim);
                char* key_hex    = strtok(NULL, delim);
                if (!table_name || !key_hex) { puts("syntax error"); continue; }
                XilVitisNetP4ReturnType r = table_get_cmd(targets, table_name, key_hex);
                if (r != XIL_VITIS_NET_P4_SUCCESS)
                    printf("Error %d (%s)\n", r, XilVitisNetP4ReturnTypeToString(r));
            }
            else if (strcmp(tok, "tdelete") == 0)
            {
                char* table_name = strtok(NULL, delim);
                char* key_hex    = strtok(NULL, delim);
                if (!table_name || !key_hex) { puts("syntax error"); continue; }
                XilVitisNetP4ReturnType r = table_delete_cmd(targets, table_name, key_hex);
                if (r != XIL_VITIS_NET_P4_SUCCESS)
                    printf("Error %d (%s)\n", r, XilVitisNetP4ReturnTypeToString(r));
                else
                    puts("OK");
            }
            else
            {
                puts("syntax error");
            }
        }
        free(line);
    }

cleanup:
    for (size_t i = 0; i < TARGET_COUNT; ++i)
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
    printf("Read 0x8204: 0x%08x\n", device_read32(dev, 0x8204));
    printf("Read 0x8204: 0x%08x\n", device_read32(dev, 0x8204));
    sleep(1);
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

/////////////////////////
// Table Read/Write CLI //
/////////////////////////
//
//   - Insert/Update/Delete: MaskPtr always NULL.
//   - GetByKey: mode queried dynamically per table, branched accordingly.
//   - Table contexts cached ONCE at startup, not per-command.
//   - Insert/Update retry up to 5 times on the intermittent busy-status
//     race observed during CAM operations.

#define MAX_KEY_BYTES   20
#define MAX_PARAM_BYTES 32  // increased from 8 -- set_scion_src needs 24 bytes (isd:2 + asn:6 + ip:16)

struct TableSchema {
    const char* name;
    size_t      key_bytes;
    const char* key_desc;
    const char* owner;
    XilVitisNetP4TableCtx* table_ctx;
};


static struct TableSchema TABLE_SCHEMA[] = {
    // --- Ingress Classifier (CONFIRMED) ---
    { "tab_local_addr_ipv4",    4,  "ipv4.dst", "classifier", NULL },
    { "tab_local_addr_ipv6",    16, "ipv6.dst", "classifier", NULL },
    { "tab_static_ports_ipv4",  2,  "udp.dst", "classifier", NULL },
    { "tab_static_ports_ipv6",  2,  "udp.dst", "classifier", NULL },
    { "tab_dynamic_ports_ipv4", 8,  "ipv4.src(4) + udp.src(2) + udp.dst(2)", "classifier", NULL },
    { "tab_dynamic_ports_ipv6", 20, "ipv6.src(16) + udp.src(2) + udp.dst(2)", "classifier", NULL },
    // --- Ingress Translator (key width CONFIRMED via driver_test.cpp,
    // which uses 2x uint64_t = 16 bytes for both tables; the key's
    // internal field layout is not independently confirmed against the
    // actual P4 source, only that it is 16 bytes total).
    { "tab_source_translation_46", 4, "isd[15:12](4b) + asn[47:20](28b), packed", "ingress_translator", NULL },
    { "tab_dest_translation_46", 4, "isd[15:12](4b) + asn[47:20](28b), packed", "ingress_translator", NULL },
    // --- Egress Translator (CONFIRMED via egress-translator.p4 source) ---
    { "tab_src_addr", 16, "ipv6.src", "egress_translator", NULL },
};
#define TABLE_SCHEMA_COUNT (sizeof(TABLE_SCHEMA) / sizeof(TABLE_SCHEMA[0]))

static void list_tables(void)
{
    printf("%-24s %-12s %-10s %s\n", "Table", "Owner", "Key bytes", "Key field order");
    for (size_t i = 0; i < TABLE_SCHEMA_COUNT; ++i)
        printf("%-24s %-12s %-10zu %s\n", TABLE_SCHEMA[i].name, TABLE_SCHEMA[i].owner,
            TABLE_SCHEMA[i].key_bytes, TABLE_SCHEMA[i].key_desc);
    puts("\nActions (classifier):");
    puts("  tab_local_addr_ipv4/ipv6:    NoAction (no params)");
    puts("  tab_static_ports_ipv4/ipv6:  static_ipv{4,6}_is_scion (no params), NoAction");
    puts("  tab_dynamic_ports_ipv4/ipv6: dynamic_ipv{4,6}_is_scion (param: 2-byte index, bit<13>), NoAction");
    puts("\nNOTE: Ingress translator and egress translator tables are not yet in");
    puts("this list -- their key schemas need confirming against the actual P4");
    puts("control blocks before adding (egress translator's tab_path/tab_hf_*");
    puts("tables especially -- much more complex than classifier's schema).");
}

static int hex_to_bytes(const char* hex, uint8_t* out, size_t max_len)
{
    if (!hex) return 0;
    size_t len = strlen(hex);
    if (len % 2 != 0) return -1;
    size_t n = len / 2;
    if (n > max_len) return -1;
    for (size_t i = 0; i < n; ++i)
    {
        char hi = hex[2 * i];
        char lo = hex[2 * i + 1];
        if (!isxdigit((unsigned char)hi) || !isxdigit((unsigned char)lo)) return -1;
        char byte_str[3] = { hi, lo, '\0' };
        out[i] = (uint8_t)strtol(byte_str, NULL, 16);
    }
    return (int)n;
}

static void print_bytes(const uint8_t* buf, size_t len)
{
    for (size_t i = 0; i < len; ++i)
        printf("%02x", buf[i]);
}

static struct TableSchema* find_schema(const char* table_name)
{
    for (size_t i = 0; i < TABLE_SCHEMA_COUNT; ++i)
        if (strcmp(TABLE_SCHEMA[i].name, table_name) == 0)
            return &TABLE_SCHEMA[i];
    printf("Unknown table '%s'. Run 'tables' to see valid names.\n", table_name);
    return NULL;
}

static XilVitisNetP4ReturnType cache_all_tables(struct P4Target* targets)
{
    for (size_t i = 0; i < TABLE_SCHEMA_COUNT; ++i)
    {
        struct P4Target* owner = &targets[TARGET_CLASSIFIER]; // only "classifier" owner exists so far
        if (strcmp(TABLE_SCHEMA[i].owner, "ingress_translator") == 0)
            owner = &targets[TARGET_INGRESS_TRANSLATOR];
        else if (strcmp(TABLE_SCHEMA[i].owner, "egress_translator") == 0)
            owner = &targets[TARGET_EGRESS_TRANSLATOR];

        XilVitisNetP4ReturnType result = XilVitisNetP4TargetGetTableByName(
            &owner->context, TABLE_SCHEMA[i].name, &TABLE_SCHEMA[i].table_ctx);
        if (result != XIL_VITIS_NET_P4_SUCCESS)
        {
            printf("Failed to cache table '%s': %d (%s)\n",
                TABLE_SCHEMA[i].name, result, XilVitisNetP4ReturnTypeToString(result));
            return result;
        }
    }
    return XIL_VITIS_NET_P4_SUCCESS;
}

static int parse_key(const struct TableSchema* schema, const char* key_hex,
    uint8_t key[MAX_KEY_BYTES])
{
    int n = hex_to_bytes(key_hex, key, MAX_KEY_BYTES);
    if (n < 0) { puts("Malformed key hex string."); return -1; }
    if ((size_t)n != schema->key_bytes)
    {
        printf("Table '%s' expects a %zu-byte key (%s), got %d bytes.\n",
            schema->name, schema->key_bytes, schema->key_desc, n);
        return -1;
    }
    return 0;
}

static XilVitisNetP4ReturnType table_insert_cmd(struct P4Target* targets, const char* table_name,
    const char* key_hex, const char* action_name, const char* param_hex)
{
    struct TableSchema* schema = find_schema(table_name);
    if (!schema) return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;
    if (!schema->table_ctx) { puts("Table context not cached (target init may have failed)."); return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM; }

    uint8_t key[MAX_KEY_BYTES];
    if (parse_key(schema, key_hex, key) != 0) return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;

    uint8_t param[MAX_PARAM_BYTES] = {0};
    int param_len = hex_to_bytes(param_hex, param, MAX_PARAM_BYTES);
    if (param_len < 0) { puts("Malformed action param hex string."); return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM; }

    uint32_t action_id;
    XilVitisNetP4ReturnType result = XilVitisNetP4TableGetActionId(schema->table_ctx, action_name, &action_id);
    if (result != XIL_VITIS_NET_P4_SUCCESS) { puts("Unknown action name for this table."); return result; }

    XilVitisNetP4ReturnType insert_result;
    for (int attempt = 0; attempt < 5; ++attempt)
    {
        insert_result = XilVitisNetP4TableInsert(schema->table_ctx, key, NULL, 0x0, action_id, param);
        if (insert_result != XIL_VITIS_NET_P4_GENERAL_ERR_INTERNAL_ASSERTION)
            break;
        if (attempt < 4)
        {
            printf("(busy, retrying %d/5)\n", attempt + 2);
            usleep(50000);
        }
    }
    return insert_result;
}

static XilVitisNetP4ReturnType table_update_cmd(struct P4Target* targets, const char* table_name,
    const char* key_hex, const char* action_name, const char* param_hex)
{
    struct TableSchema* schema = find_schema(table_name);
    if (!schema) return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;
    if (!schema->table_ctx) { puts("Table context not cached (target init may have failed)."); return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM; }

    uint8_t key[MAX_KEY_BYTES];
    if (parse_key(schema, key_hex, key) != 0) return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;

    uint8_t param[MAX_PARAM_BYTES] = {0};
    int param_len = hex_to_bytes(param_hex, param, MAX_PARAM_BYTES);
    if (param_len < 0) { puts("Malformed action param hex string."); return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM; }

    uint32_t action_id;
    XilVitisNetP4ReturnType result = XilVitisNetP4TableGetActionId(schema->table_ctx, action_name, &action_id);
    if (result != XIL_VITIS_NET_P4_SUCCESS) { puts("Unknown action name for this table."); return result; }

    XilVitisNetP4ReturnType update_result;
    for (int attempt = 0; attempt < 5; ++attempt)
    {
        update_result = XilVitisNetP4TableUpdate(schema->table_ctx, key, NULL, action_id, param);
        if (update_result != XIL_VITIS_NET_P4_GENERAL_ERR_INTERNAL_ASSERTION)
            break;
        if (attempt < 4)
        {
            printf("(busy, retrying %d/5)\n", attempt + 2);
            usleep(50000);
        }
    }
    return update_result;
}

static XilVitisNetP4ReturnType table_get_cmd(struct P4Target* targets, const char* table_name,
    const char* key_hex)
{
    struct TableSchema* schema = find_schema(table_name);
    if (!schema) return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;
    if (!schema->table_ctx) { puts("Table context not cached (target init may have failed)."); return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM; }

    uint8_t key[MAX_KEY_BYTES];
    if (parse_key(schema, key_hex, key) != 0) return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;

    XilVitisNetP4TableMode mode;
    XilVitisNetP4ReturnType result = XilVitisNetP4TableGetMode(schema->table_ctx, &mode);
    if (result != XIL_VITIS_NET_P4_SUCCESS) return result;

    uint32_t priority = 0, action_id = 0;
    uint8_t mask[MAX_KEY_BYTES];
    memset(mask, 0xFF, schema->key_bytes);
    uint8_t param[MAX_PARAM_BYTES] = {0};

    if (mode == XIL_VITIS_NET_P4_TABLE_MODE_BCAM)
        result = XilVitisNetP4TableGetByKey(schema->table_ctx, key, NULL, NULL, &action_id, param);
    else
        result = XilVitisNetP4TableGetByKey(schema->table_ctx, key, mask, &priority, &action_id, param);
    if (result != XIL_VITIS_NET_P4_SUCCESS) return result;

    printf("action_id=%u  priority=%u  action_params=", action_id, priority);
    print_bytes(param, MAX_PARAM_BYTES);
    putchar('\n');
    return XIL_VITIS_NET_P4_SUCCESS;
}

static XilVitisNetP4ReturnType table_delete_cmd(struct P4Target* targets, const char* table_name,
    const char* key_hex)
{
    struct TableSchema* schema = find_schema(table_name);
    if (!schema) return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;
    if (!schema->table_ctx) { puts("Table context not cached (target init may have failed)."); return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM; }

    uint8_t key[MAX_KEY_BYTES];
    if (parse_key(schema, key_hex, key) != 0) return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;

    return XilVitisNetP4TableDelete(schema->table_ctx, key, NULL);
}

static XilVitisNetP4ReturnType table_mode_cmd(const char* table_name)
{
    struct TableSchema* schema = find_schema(table_name);
    if (!schema) return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM;
    if (!schema->table_ctx) { puts("Table context not cached (target init may have failed)."); return XIL_VITIS_NET_P4_GENERAL_ERR_NULL_PARAM; }

    XilVitisNetP4TableMode mode;
    XilVitisNetP4ReturnType result = XilVitisNetP4TableGetMode(schema->table_ctx, &mode);
    if (result != XIL_VITIS_NET_P4_SUCCESS) return result;

    printf("Table '%s' mode = %d\n", table_name, (int)mode);
    return XIL_VITIS_NET_P4_SUCCESS;
}
