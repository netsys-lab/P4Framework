#pragma once

#include "device.h"
#include "include/vitisnetp4_common.h"
#include "include/vitisnetp4_target.h"


struct P4Target
{
    const char* prog_name;
    struct Device* device;
    XilVitisNetP4AddressType base_addr;
    XilVitisNetP4TargetConfig* config;
    XilVitisNetP4TargetCtx context;
    XilVitisNetP4CounterCtx* counters;
    // FIXED: env must live as long as the target itself. Both
    // XilVitisNetP4TargetInit and XilVitisNetP4CounterInit store the raw
    // EnvIf pointer they're given (confirmed via source:
    // counter_extern.c's CtxPtr->EnvIfPtr = EnvIfPtr, no copy) -- if env
    // were a local variable inside init_target(), that pointer would
    // dangle the moment init_target() returns, causing crashes whenever
    // counter/table functions are called later (e.g. calling a garbage
    // function pointer read from overwritten stack memory).
    XilVitisNetP4EnvIf env;
};

XilVitisNetP4ReturnType init_target(
    struct P4Target* target, struct Device* device,
    XilVitisNetP4AddressType base_addr,
    XilVitisNetP4TargetConfig* config);

XilVitisNetP4ReturnType exit_target(struct P4Target *target);

XilVitisNetP4ReturnType env_read32(
    XilVitisNetP4EnvIf* EnvIfPtr, XilVitisNetP4AddressType Address, uint32_t* ReadValuePtr);
XilVitisNetP4ReturnType env_write32(
    XilVitisNetP4EnvIf* EnvIfPtr, XilVitisNetP4AddressType Address, uint32_t WriteValue);
