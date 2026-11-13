# Minimal Full-Speed USB host on the ESP32-P4's second OTG controller
# (index 1, D+/D- on GPIO 27/26). Lives in C because the DWC HAL port API is
# static-inline (invisible to Rust bindgen); Rust calls fs_host_bringup().
idf_component_register(
    SRCS "fs_host.c"
    INCLUDE_DIRS "include"
    REQUIRES hal usb soc esp_common esp_hw_support freertos log esp_mm heap esp_rom
)
