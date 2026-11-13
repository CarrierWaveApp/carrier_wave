// Thin C shim between firmware Rust and the shared CFT8 library.
//
// The upstream `monitor_t` struct has public, directly-accessed fields
// (block_size, wf, etc.). Rather than duplicating its layout in Rust (which is
// brittle and would break on any upstream struct change), we expose a handful
// of C functions that allocate the struct on the heap, run the init/teardown,
// and hand back accessors the Rust side can call through thin `extern "C"`
// bindings.

#include <stdlib.h>
#include <string.h>

#include "../../swift/packages/CarrierWaveCore/Sources/CFT8/common/monitor.h"
#include "../../swift/packages/CarrierWaveCore/Sources/CFT8/ft8/decode.h"

// Allocate + initialise a monitor_t on the heap. Returns NULL on OOM.
monitor_t* ft8_shim_monitor_new(const monitor_config_t* cfg) {
    monitor_t* mon = (monitor_t*) calloc(1, sizeof(monitor_t));
    if (mon == NULL) {
        return NULL;
    }
    monitor_init(mon, cfg);
    return mon;
}

// Tear down and free a monitor_t previously returned by ft8_shim_monitor_new.
void ft8_shim_monitor_free(monitor_t* mon) {
    if (mon == NULL) {
        return;
    }
    monitor_free(mon);
    free(mon);
}

int ft8_shim_monitor_block_size(const monitor_t* mon) {
    return mon->block_size;
}

// Process exactly block_size samples.
void ft8_shim_monitor_process(monitor_t* mon, const float* frame) {
    monitor_process(mon, frame);
}

// Expose the embedded waterfall so Rust can hand it to ftx_find_candidates /
// ftx_decode_candidate without having to mirror the struct layout.
ftx_waterfall_t* ft8_shim_monitor_waterfall(monitor_t* mon) {
    return &mon->wf;
}
