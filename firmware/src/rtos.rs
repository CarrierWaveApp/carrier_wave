//! Safe wrappers for FreeRTOS timing primitives.
//!
//! These encapsulate the `unsafe` FFI calls to `vTaskDelay` and
//! `xTaskGetTickCount` so the rest of the codebase doesn't need
//! per-call unsafe blocks for basic timing.

/// Delay the current task for the given number of ticks.
///
/// On ESP-IDF with `configTICK_RATE_HZ = 1000`, one tick = one millisecond.
pub fn delay_ticks(ticks: u32) {
    // SAFETY: vTaskDelay is always safe to call from a FreeRTOS task context.
    // All firmware threads are FreeRTOS tasks (created via std::thread on ESP-IDF).
    unsafe { esp_idf_sys::vTaskDelay(ticks) }
}

/// Return the current FreeRTOS tick count.
pub fn tick_count() -> u32 {
    // SAFETY: xTaskGetTickCount is a read-only query, safe from any task context.
    unsafe { esp_idf_sys::xTaskGetTickCount() }
}
