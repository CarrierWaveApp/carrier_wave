// NimBLE host + ESP-Hosted bindings for the ESP32-P4.
//
// esp-idf-sys's stock bindings.h excludes the entire Bluetooth block on the
// P4 ("No BT in ESP32-P4") — true for the radio, but this board (Waveshare
// P4 devkit) carries an ESP32-C6 co-processor on SDIO running ESP-Hosted:
// NimBLE runs host-only on the P4 with the controller on the C6
// (CONFIG_BT_CONTROLLER_DISABLED + CONFIG_ESP_HOSTED_HOST_FEAT_BT, see
// sdkconfig.defaults). This header re-adds the NimBLE host includes that
// bindings.h would emit on a chip with a radio, plus the ESP-Hosted
// bring-up and BT-stack-binding APIs.

#include "sdkconfig.h"

#ifdef CONFIG_BT_NIMBLE_ENABLED
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#endif

#ifdef CONFIG_ESP_HOSTED_HOST_FEAT_BT
#include "esp_hosted.h"
#include "esp_hosted_bt_host_stack.h"
#endif
