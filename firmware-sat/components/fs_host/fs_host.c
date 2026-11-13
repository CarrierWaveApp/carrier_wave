// Minimal Full-Speed USB host bring-up on the ESP32-P4's second OTG
// controller (index 1). Dual-host spike, Phase 2: prove the FS controller
// powers its port on GPIO 27/26, sees a device connect, resets it, and reads
// the negotiated speed — all without a hub and alongside the rest of the
// system. Written in C because the DWC HAL port API is static-inline and
// therefore invisible to Rust bindgen.

#include "fs_host.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "esp_err.h"
#include "esp_log.h"
#include "esp_cache.h"
#include "esp_heap_caps.h"
#include "esp_rom_sys.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "esp_private/usb_phy.h"
#include "hal/usb_dwc_hal.h"
#include "hal/usb_dwc_ll.h"

static const char *TAG = "fs_host";

// Diagnostic: run the SAME transfer engine on the HS controller (port 0, UTMI
// PHY) to isolate whether the "channel enables but never transfers" problem is
// in our code or specific to the FS controller. Set to 1 to target HS (needs a
// device on the HS OTG connector); 0 = normal FS controller on GPIO 27/26.
#define TEST_ON_HS 1

#if TEST_ON_HS
#define FS_PORT_ID 0
#define FS_PHY_TARGET USB_PHY_TARGET_UTMI
#else
// The Full-Speed OTG is controller index 1 in usb_dwc_info.controllers[].
#define FS_PORT_ID 1
#define FS_PHY_TARGET USB_PHY_TARGET_INT
#endif
// Poll windows.
#define CONNECT_TIMEOUT_MS 10000
#define POLL_STEP_MS       100
#define RESET_ASSERT_MS    30

// Control-transfer engine (polled). Because the P4 FS controller's port/core
// interrupt isn't delivered to the stock host (its IRQ is a per-channel
// source), we drive the DWC HAL directly and POLL for channel completion — no
// ISR, no hcd. Mirrors hcd_dwc.c's control-transfer QTD sequence.
#define QTD_LIST_LEN   3     // control = SETUP + DATA + STATUS
#define DMA_ALIGN      64    // cache line (for data buffers + cache-sync sizing)
#define QTD_LIST_ALIGN 512   // USB_DWC_QTD_LIST_MEM_ALIGN — HCDMA base alignment
#define QTD_LIST_BYTES ((((QTD_LIST_LEN * (int)sizeof(usb_dwc_ll_dma_qtd_t)) + DMA_ALIGN - 1) / DMA_ALIGN) * DMA_ALIGN)
#define CTRL_BUF_BYTES 128   // 8-byte setup packet + up to ~120 bytes of data
#define CTRL_XFER_TIMEOUT_MS 1000

// 8-byte USB SETUP packet (USB 2.0 §9.3).
typedef struct __attribute__((packed)) {
    uint8_t  bmRequestType;
    uint8_t  bRequest;
    uint16_t wValue;
    uint16_t wIndex;
    uint16_t wLength;
} setup_pkt_t;

static usb_dwc_hal_context_t s_hal;
static usb_phy_handle_t s_phy;

// Control-pipe state on the FS controller.
static usb_dwc_hal_chan_t s_ctrl_chan;      // channel object
static void *s_qtd_list;                    // QTD_LIST_LEN descriptors (DMA)
static uint8_t *s_ctrl_buf;                 // setup(8) + data (DMA)
static uint32_t *s_frame_list;              // periodic frame list (DMA, 512-aligned)
#define FRAME_LIST_ENTRIES 32               // USB_HAL_FRAME_LIST_LEN_32
#define FRAME_LIST_BYTES   (FRAME_LIST_ENTRIES * (int)sizeof(uint32_t))
static uint8_t s_dev_mps0 = 8;              // EP0 max packet size (starts at 8)
static uint8_t s_dev_addr;                  // current device address

// Re-apply EP0 characteristics (called whenever dev_addr or mps0 changes).
static void ctrl_set_ep_char(void)
{
    usb_dwc_hal_ep_char_t ep = {0};
    ep.type = USB_DWC_XFER_TYPE_CTRL;
    ep.bEndpointAddress = 0;
    ep.mps = s_dev_mps0;
    ep.dev_addr = s_dev_addr;
    usb_dwc_hal_chan_set_ep_char(&s_hal, &s_ctrl_chan, &ep);
}

// Poll one channel stage to completion. Returns the HAL channel event
// (CPLT / ERROR), or NONE on timeout / disconnect.
static usb_dwc_hal_chan_event_t ctrl_poll_stage(int timeout_ms)
{
    int n_chan = 0, n_other = 0, last_pe = -1, n_chan_evt = 0, last_ce = -1;
    uint32_t raw_hcint = 0;
    for (int i = 0; i < timeout_ms * 10; i++) {
        // Direct channel-register probe (bypasses GINTSTS/HAINT aggregation, in
        // case the FS controller doesn't aggregate channel interrupts).
        raw_hcint = s_ctrl_chan.regs->hcint_reg.val;
        if (raw_hcint != 0) {
            ESP_LOGI(TAG, "raw HCINT=0x%08x chena=%d after %d us",
                     (unsigned)raw_hcint, s_ctrl_chan.regs->hcchar_reg.chena, i * 100);
            return USB_DWC_HAL_CHAN_EVENT_CPLT; // provisional: something happened
        }
        usb_dwc_hal_port_event_t pe = usb_dwc_hal_decode_intr(&s_hal);
        if (pe != USB_DWC_HAL_PORT_EVENT_NONE) {
            last_pe = pe;
        }
        if (pe == USB_DWC_HAL_PORT_EVENT_CHAN) {
            n_chan++;
            usb_dwc_hal_chan_t *c = usb_dwc_hal_get_chan_pending_intr(&s_hal);
            while (c) {
                usb_dwc_hal_chan_event_t ce = usb_dwc_hal_chan_decode_intr(c);
                n_chan_evt++;
                last_ce = ce;
                if (ce == USB_DWC_HAL_CHAN_EVENT_CPLT || ce == USB_DWC_HAL_CHAN_EVENT_ERROR) {
                    return ce;
                }
                c = usb_dwc_hal_get_chan_pending_intr(&s_hal);
            }
        } else if (pe == USB_DWC_HAL_PORT_EVENT_DISCONN || pe == USB_DWC_HAL_PORT_EVENT_DISABLED) {
            ESP_LOGW(TAG, "port lost during control transfer (evt=%d)", pe);
            return USB_DWC_HAL_CHAN_EVENT_NONE;
        } else if (pe != USB_DWC_HAL_PORT_EVENT_NONE) {
            n_other++;
        }
        esp_rom_delay_us(100);
    }
    ESP_LOGW(TAG, "poll timeout: chan_evts=%d(hal_evt=%d,last_ce=%d) other=%d last_pe=%d raw_hcint=0x%08x chena=%d",
             n_chan, n_chan_evt, last_ce, n_other, last_pe,
             (unsigned)raw_hcint, s_ctrl_chan.regs->hcchar_reg.chena);
    return USB_DWC_HAL_CHAN_EVENT_NONE;
}

// Run one polled control transfer. For IN transfers, up to wLength bytes are
// written back to io_data. Returns 0 on success, negative on error.
static int ctrl_xfer(uint8_t bmReqType, uint8_t bReq, uint16_t wVal,
                     uint16_t wIdx, uint16_t wLen, uint8_t *io_data)
{
    const bool data_in = (bmReqType & 0x80) != 0;
    const bool has_data = (wLen > 0);

    // Build the SETUP packet at the head of the DMA buffer.
    setup_pkt_t *sp = (setup_pkt_t *)s_ctrl_buf;
    sp->bmRequestType = bmReqType;
    sp->bRequest = bReq;
    sp->wValue = wVal;
    sp->wIndex = wIdx;
    sp->wLength = wLen;
    if (has_data && !data_in && io_data) {
        memcpy(s_ctrl_buf + 8, io_data, wLen);
    }

    // Fill the QTDs: SETUP (idx0), DATA (idx1, optional), STATUS (idx2).
    // Each carries HOC so the channel halts after that single stage.
    usb_dwc_hal_xfer_desc_fill(s_qtd_list, 0, s_ctrl_buf, 8,
                               USB_DWC_HAL_XFER_DESC_FLAG_SETUP | USB_DWC_HAL_XFER_DESC_FLAG_HOC);
    if (has_data) {
        usb_dwc_hal_xfer_desc_fill(s_qtd_list, 1, s_ctrl_buf + 8, wLen,
                                   (data_in ? USB_DWC_HAL_XFER_DESC_FLAG_IN : 0) | USB_DWC_HAL_XFER_DESC_FLAG_HOC);
    } else {
        usb_dwc_hal_xfer_desc_clear(s_qtd_list, 1);
    }
    // Status stage is the opposite direction of data (IN when there's no data).
    const bool status_in = has_data ? !data_in : true;
    usb_dwc_hal_xfer_desc_fill(s_qtd_list, 2, NULL, 0,
                               (status_in ? USB_DWC_HAL_XFER_DESC_FLAG_IN : 0) | USB_DWC_HAL_XFER_DESC_FLAG_HOC);

    esp_err_t c1 = esp_cache_msync(s_qtd_list, QTD_LIST_BYTES, ESP_CACHE_MSYNC_FLAG_DIR_C2M);
    esp_err_t c2 = esp_cache_msync(s_ctrl_buf, CTRL_BUF_BYTES, ESP_CACHE_MSYNC_FLAG_DIR_C2M);
    {
        volatile uint32_t *q = (volatile uint32_t *)s_qtd_list;
        ESP_LOGI(TAG, "QTD0 status=0x%08x buf=0x%08x | qtd@%p buf@%p msync c1=%d c2=%d",
                 (unsigned)q[0], (unsigned)q[1], s_qtd_list, s_ctrl_buf, c1, c2);
    }

    {
        uint32_t f1 = s_hal.dev->hfnum_reg.frnum;
        esp_rom_delay_us(2500);
        uint32_t f2 = s_hal.dev->hfnum_reg.frnum;
        ESP_LOGI(TAG, "HFNUM f1=%u f2=%u | HPRT conn=%d ena=%d pwr=%d spd=%d",
                 (unsigned)f1, (unsigned)f2,
                 s_hal.dev->hprt_reg.prtconnsts, s_hal.dev->hprt_reg.prtena,
                 s_hal.dev->hprt_reg.prtpwr, s_hal.dev->hprt_reg.prtspd);
    }

    // --- SETUP stage (always OUT, PID DATA0) ---
    usb_dwc_hal_chan_set_dir(&s_ctrl_chan, false);
    usb_dwc_hal_chan_set_pid(&s_ctrl_chan, 0);
    usb_dwc_hal_chan_activate(&s_ctrl_chan, s_qtd_list, QTD_LIST_LEN, 0);
    ESP_LOGI(TAG, "after activate: HCDMA=0x%08x hctsiz=0x%08x hcchar=0x%08x",
             (unsigned)s_ctrl_chan.regs->hcdma_reg.val,
             (unsigned)s_ctrl_chan.regs->hctsiz_reg.val,
             (unsigned)s_ctrl_chan.regs->hcchar_reg.val);
    usb_dwc_hal_chan_event_t setup_ev = ctrl_poll_stage(CTRL_XFER_TIMEOUT_MS);
    if (setup_ev != USB_DWC_HAL_CHAN_EVENT_CPLT) {
        ESP_LOGW(TAG, "ctrl SETUP stage failed (req=0x%02x): ev=%d chan_err=%d",
                 bReq, setup_ev, usb_dwc_hal_chan_get_error(&s_ctrl_chan));
        return -1;
    }

    // --- DATA stage (optional, PID DATA1) ---
    if (has_data) {
        usb_dwc_hal_chan_set_dir(&s_ctrl_chan, data_in);
        usb_dwc_hal_chan_set_pid(&s_ctrl_chan, 1);
        usb_dwc_hal_chan_activate(&s_ctrl_chan, s_qtd_list, QTD_LIST_LEN, 1);
        if (ctrl_poll_stage(CTRL_XFER_TIMEOUT_MS) != USB_DWC_HAL_CHAN_EVENT_CPLT) {
            ESP_LOGW(TAG, "ctrl DATA stage failed (req=0x%02x)", bReq);
            return -2;
        }
    }

    // --- STATUS stage (opposite dir, PID DATA1) ---
    usb_dwc_hal_chan_set_dir(&s_ctrl_chan, status_in);
    usb_dwc_hal_chan_set_pid(&s_ctrl_chan, 1);
    usb_dwc_hal_chan_activate(&s_ctrl_chan, s_qtd_list, QTD_LIST_LEN, 2);
    if (ctrl_poll_stage(CTRL_XFER_TIMEOUT_MS) != USB_DWC_HAL_CHAN_EVENT_CPLT) {
        ESP_LOGW(TAG, "ctrl STATUS stage failed (req=0x%02x)", bReq);
        return -3;
    }

    // Hand back IN data.
    if (has_data && data_in && io_data) {
        esp_cache_msync(s_ctrl_buf, CTRL_BUF_BYTES, ESP_CACHE_MSYNC_FLAG_DIR_M2C);
        memcpy(io_data, s_ctrl_buf + 8, wLen);
    }
    return 0;
}

// Phase 3: enumerate the freshly-reset device on the FS port. Allocates the
// control channel, reads the device descriptor (VID/PID), and assigns an
// address. Returns 0 on success. Must run after fs_host_bringup() detected +
// reset a device.
static int fs_host_enumerate(void)
{
    // The HAL needs the channel-handle array allocated before chan_alloc.
    if (s_hal.channels.hdls == NULL) {
        s_hal.channels.hdls = calloc(s_hal.constant_config.chan_num_total, sizeof(usb_dwc_hal_chan_t *));
        if (s_hal.channels.hdls == NULL) {
            ESP_LOGE(TAG, "OOM: channel handle array");
            return -10;
        }
    }
    s_qtd_list = heap_caps_aligned_calloc(QTD_LIST_ALIGN, 1, QTD_LIST_BYTES,
                                          MALLOC_CAP_DMA | MALLOC_CAP_CACHE_ALIGNED | MALLOC_CAP_INTERNAL);
    s_ctrl_buf = heap_caps_aligned_calloc(DMA_ALIGN, 1, CTRL_BUF_BYTES,
                                          MALLOC_CAP_DMA | MALLOC_CAP_CACHE_ALIGNED | MALLOC_CAP_INTERNAL);
    s_frame_list = heap_caps_aligned_calloc(QTD_LIST_ALIGN, 1, FRAME_LIST_BYTES,
                                            MALLOC_CAP_DMA | MALLOC_CAP_CACHE_ALIGNED | MALLOC_CAP_INTERNAL);
    if (!s_qtd_list || !s_ctrl_buf || !s_frame_list) {
        ESP_LOGE(TAG, "OOM: DMA buffers");
        return -11;
    }

    // Configure the DWC FIFO partition before allocating channels (the HAL
    // asserts fifo_sizes_set otherwise). Balanced split; the FS controller has
    // a 256-line DFIFO. Mirrors hcd_dwc.c _calculate_fifo_from_bias (balanced).
    usb_dwc_hal_fifo_config_t fifo = {0};
    const int dfifo_depth = 256; // FS (non-HS) PHY
    const int total_lines = s_hal.constant_config.fifo_size;
    fifo.nptx_fifo_lines = dfifo_depth / 4;
    fifo.ptx_fifo_lines = dfifo_depth / 8;
    fifo.rx_fifo_lines = total_lines - fifo.ptx_fifo_lines - fifo.nptx_fifo_lines;
    usb_dwc_hal_set_fifo_config(&s_hal, &fifo);

    // Set the periodic frame list + enable the scheduler (required for the
    // SG-DMA request scheduler to run transfers). Mirrors _port_cmd_reset.
    esp_cache_msync(s_frame_list, FRAME_LIST_BYTES, ESP_CACHE_MSYNC_FLAG_DIR_C2M);
    usb_dwc_hal_port_set_frame_list(&s_hal, s_frame_list, USB_HAL_FRAME_LIST_LEN_32);
    usb_dwc_hal_port_periodic_enable(&s_hal);

    if (!usb_dwc_hal_chan_alloc(&s_hal, &s_ctrl_chan, NULL)) {
        ESP_LOGE(TAG, "control channel alloc failed");
        return -12;
    }
    s_dev_addr = 0;
    s_dev_mps0 = 8;
    ctrl_set_ep_char();

    // GET_DESCRIPTOR(device, 8): read bMaxPacketSize0 (offset 7) at address 0.
    uint8_t desc[18] = {0};
    int rc = ctrl_xfer(0x80, 6 /*GET_DESCRIPTOR*/, (1 << 8) /*DEVICE*/, 0, 8, desc);
    if (rc != 0) {
        ESP_LOGE(TAG, "GET_DESCRIPTOR(device,8) failed rc=%d", rc);
        return -13;
    }
    s_dev_mps0 = desc[7] ? desc[7] : 8;
    ESP_LOGI(TAG, "EP0 max packet size = %d", s_dev_mps0);
    ctrl_set_ep_char();

    // SET_ADDRESS(1).
    rc = ctrl_xfer(0x00, 5 /*SET_ADDRESS*/, 1, 0, 0, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "SET_ADDRESS(1) failed rc=%d", rc);
        return -14;
    }
    vTaskDelay(pdMS_TO_TICKS(10)); // USB 2.0 §9.2.6.3: 2ms recovery
    s_dev_addr = 1;
    ctrl_set_ep_char();

    // GET_DESCRIPTOR(device, 18): full descriptor → VID/PID.
    rc = ctrl_xfer(0x80, 6, (1 << 8), 0, 18, desc);
    if (rc != 0) {
        ESP_LOGE(TAG, "GET_DESCRIPTOR(device,18) failed rc=%d", rc);
        return -15;
    }
    uint16_t vid = desc[8] | (desc[9] << 8);
    uint16_t pid = desc[10] | (desc[11] << 8);
    ESP_LOGI(TAG, "*** FS device enumerated: VID=0x%04x PID=0x%04x (addr 1) ***", vid, pid);
    ESP_LOGI(TAG, "Phase 3 PASS — hand-rolled control transfers work on the FS controller.");
    return 0;
}

// PHY handles for the dual-host production path (kept alive for the process).
static usb_phy_handle_t s_phy_hs; // peripheral 0: High-Speed (UTMI PHY)
static usb_phy_handle_t s_phy_fs; // peripheral 1: Full-Speed (internal FSLS PHY, GPIO 27/26)

// Bring up BOTH OTG PHYs in host mode so the stock USB Host library can drive
// both root ports (peripheral_map = BIT0 | BIT1). The library's own PHY setup
// (skip_phy_setup = false) initializes only ONE peripheral's PHY — see
// usb_host_install(): `if (peripheral_map & BIT1) peripheral_index = 1;` with
// the comment "Right now we support only one peripheral". So for dual host we
// pass skip_phy_setup = true and create both PHYs here first. The target
// selects the controller on the P4: UTMI -> HS (periph 0), INT (FSLS on GPIO
// dp=27/dm=26) -> FS (periph 1). Returns 0 on success, negative on failure.
int usb_host_phys_bringup(void)
{
    usb_phy_config_t hs = {
        .controller = USB_PHY_CTRL_OTG,
        .target     = USB_PHY_TARGET_UTMI,
        .otg_mode   = USB_OTG_MODE_HOST,
        .otg_speed  = USB_PHY_SPEED_UNDEFINED, // host: speed set by the device
    };
    esp_err_t err = usb_new_phy(&hs, &s_phy_hs);
    ESP_LOGI(TAG, "usb_new_phy(HS/UTMI/HOST) [periph 0] -> %d", err);
    if (err != ESP_OK) {
        return -1;
    }

    usb_phy_config_t fs = {
        .controller = USB_PHY_CTRL_OTG,
        .target     = USB_PHY_TARGET_INT,
        .otg_mode   = USB_OTG_MODE_HOST,
        .otg_speed  = USB_PHY_SPEED_UNDEFINED,
    };
    err = usb_new_phy(&fs, &s_phy_fs);
    ESP_LOGI(TAG, "usb_new_phy(FS/INT/HOST) [periph 1, GPIO 27/26] -> %d", err);
    if (err != ESP_OK) {
        return -2;
    }

    ESP_LOGI(TAG, "both OTG PHYs up; stock host can now own both root ports");
    return 0;
}

int fs_host_bringup(void)
{
    ESP_LOGI(TAG, "=== FS-USB Phase 2: port power + connect detect (GPIO 27/26) ===");

    // Bring up the FS controller's internal FSLS PHY as a host. target = INT
    // selects the FS controller's PHY (routed to GPIO 27/26); this also
    // enables the OTG controller.
    usb_phy_config_t cfg = {
        .controller = USB_PHY_CTRL_OTG,
        .target     = FS_PHY_TARGET,
        .otg_mode   = USB_OTG_MODE_HOST,
        .otg_speed  = USB_PHY_SPEED_UNDEFINED,
    };
    esp_err_t err = usb_new_phy(&cfg, &s_phy);
    ESP_LOGI(TAG, "usb_new_phy(port %d, target %d, HOST) -> %d", FS_PORT_ID, FS_PHY_TARGET, err);
    if (err != ESP_OK) {
        return -1;
    }
    usb_phy_otg_set_mode(s_phy, USB_OTG_MODE_HOST);

    // Init the DWC HAL on the FS peripheral (reads the core-ID register).
    usb_dwc_hal_init(&s_hal, FS_PORT_ID);
    ESP_LOGI(TAG, "FS HAL init: channels=%d, fifo=%d lines",
             s_hal.constant_config.chan_num_total, s_hal.constant_config.fifo_size);

    usb_dwc_hal_core_soft_reset(&s_hal);
    vTaskDelay(pdMS_TO_TICKS(20));

    // Power the host port and wait for a device to pull the FS D+ line.
    usb_dwc_hal_port_init(&s_hal);
    usb_dwc_hal_port_toggle_power(&s_hal, true);
    ESP_LOGI(TAG, "FS port powered; waiting up to %d ms for a device...", CONNECT_TIMEOUT_MS);

    bool connected = false;
    for (int waited = 0; waited < CONNECT_TIMEOUT_MS; waited += POLL_STEP_MS) {
        if (usb_dwc_hal_port_check_if_connected(&s_hal)) {
            connected = true;
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(POLL_STEP_MS));
    }
    if (!connected) {
        ESP_LOGW(TAG, "no device connected on the FS port (is a radio wired to GPIO 27/26?)");
        return -2;
    }
    ESP_LOGI(TAG, "*** FS PORT: device connected ***");

    // Reset the device so the port enables and the speed is latched.
    vTaskDelay(pdMS_TO_TICKS(100));
    usb_dwc_hal_port_toggle_reset(&s_hal, true);
    vTaskDelay(pdMS_TO_TICKS(RESET_ASSERT_MS));
    usb_dwc_hal_port_toggle_reset(&s_hal, false);

    // The HAL only transitions the port to ENABLED (SOFs flowing, required
    // before any channel transfer) when the PORT_ENABLED interrupt is decoded.
    // We have no ISR on this controller, so poll usb_dwc_hal_decode_intr.
    bool enabled = false;
    for (int i = 0; i < 500; i++) { // up to ~500 ms
        usb_dwc_hal_port_event_t pe = usb_dwc_hal_decode_intr(&s_hal);
        if (pe == USB_DWC_HAL_PORT_EVENT_ENABLED) {
            enabled = true;
            break;
        }
        esp_rom_delay_us(1000);
    }
    if (!enabled) {
        ESP_LOGW(TAG, "FS port did not reach ENABLED after reset");
        return -3;
    }
    // Enable Scatter/Gather DMA (required for the QTD-list channel transfers we
    // do in enumerate) and configure the FSLS PHY clock for this FS controller.
    usb_dwc_hal_port_enable(&s_hal);
    ESP_LOGI(TAG, "FS port ENABLED: hsphy_type=%d descdma=%d hfir=0x%08x",
             s_hal.constant_config.hsphy_type,
             s_hal.dev->hcfg_reg.descdma,
             (unsigned)s_hal.dev->hfir_reg.val);

    usb_dwc_speed_t speed = usb_dwc_hal_port_get_conn_speed(&s_hal);
    const char *speed_str =
        (speed == USB_DWC_SPEED_LOW) ? "Low" :
        (speed == USB_DWC_SPEED_FULL) ? "Full" :
        (speed == USB_DWC_SPEED_HIGH) ? "High" : "?";
    ESP_LOGI(TAG, "*** FS PORT reset OK; device speed = %s (%d) ***", speed_str, speed);
    ESP_LOGI(TAG, "Phase 2 PASS — FS controller hosts a device on GPIO 27/26.");

    // Phase 3: hand-rolled polled enumeration (control transfers).
    return fs_host_enumerate();
}
