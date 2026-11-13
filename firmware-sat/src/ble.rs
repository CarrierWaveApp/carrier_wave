//! BLE GATT server implementing the Nordic UART Service (NUS).
//!
//! Uses the NimBLE stack in host-only mode — the ESP32-P4 has no BT radio,
//! so the controller lives on the companion ESP32-C6 behind the HCI UART
//! transport configured in sdkconfig.defaults.
//!
//! NUS UUIDs (128-bit):
//!   Service: 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
//!   RX:      6E400002-...  (client writes here)
//!   TX:      6E400003-...  (server notifies here)
//!
//! Security: the RX write characteristic requires an encrypted, authenticated
//! link (LE Secure Connections + MITM). First pairing uses passkey display —
//! the bridge picks a random 6-digit code, shows it on the OLED, and the
//! iOS/macOS client prompts the user to enter it. Bonds persist in NVS so
//! subsequent reconnects from a known peer are silent.

use std::ffi::c_int;
use std::sync::atomic::{AtomicBool, AtomicU16, Ordering};
use std::sync::mpsc::Sender;
use std::sync::OnceLock;

use ::log::{debug, error, info, warn};
use esp_idf_sys::*;

use crate::BridgeEvent;

const DEVICE_NAME: &[u8] = b"CW Sat Bridge\0";

/// BLE_HS_FOREVER is a C macro (INT32_MAX) not exported by bindgen.
const BLE_HS_FOREVER: i32 = i32::MAX;

// NUS UUIDs in little-endian byte order (NimBLE convention)
const NUS_SVC_UUID: [u8; 16] = [
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0, 0x93, 0xf3, 0xa3, 0xb5, 0x01, 0x00, 0x40, 0x6e,
];

const NUS_RX_UUID: [u8; 16] = [
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0, 0x93, 0xf3, 0xa3, 0xb5, 0x02, 0x00, 0x40, 0x6e,
];

const NUS_TX_UUID: [u8; 16] = [
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0, 0x93, 0xf3, 0xa3, 0xb5, 0x03, 0x00, 0x40, 0x6e,
];

/// BLE connection state — accessed from NimBLE callbacks and app thread.
static CONN_HANDLE: AtomicU16 = AtomicU16::new(BLE_HS_CONN_HANDLE_NONE as u16);
static TX_SUBSCRIBED: AtomicBool = AtomicBool::new(false);
/// `true` once the link is encrypted + authenticated. Cleared on disconnect.
/// Gates all outbound notifications so an unbonded peer never receives data.
static LINK_ENCRYPTED: AtomicBool = AtomicBool::new(false);

/// TX attribute handle — written once by NimBLE during GATT registration,
/// then read-only. Must remain a static mut because NimBLE writes to it
/// via a raw `*mut u16` pointer during `ble_gatts_add_svcs`.
static mut TX_ATTR_HANDLE: u16 = 0;

/// Event sender — set once during init.
static EVENT_TX: OnceLock<Sender<BridgeEvent>> = OnceLock::new();

/// BLE NUS interface.
pub struct Ble;

impl Ble {
    /// Initialize the NimBLE stack, register NUS GATT service, and start advertising.
    ///
    /// # Safety
    /// Must be called once from app_main.
    pub unsafe fn init(event_tx: Sender<BridgeEvent>) -> Self {
        EVENT_TX.set(event_tx).ok();

        // NVS required for NimBLE bonding info
        let mut err = nvs_flash_init();
        if err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND {
            nvs_flash_erase();
            err = nvs_flash_init();
        }
        assert!(err == ESP_OK, "NVS init failed: {err}");

        // ESP-Hosted: the P4 has no BT radio — the controller is the
        // board's SDIO-attached ESP32-C6 running the hosted slave firmware.
        // Bring the transport up, connect, then bind NimBLE to the HCI
        // byte-pipe. Must all happen BEFORE nimble_port_init().
        let err = esp_hosted_init();
        assert!(err == ESP_OK, "esp_hosted_init failed: {err}");
        let err = esp_hosted_connect_to_slave();
        assert!(err == ESP_OK, "esp_hosted_connect_to_slave failed: {err}");
        let mut bt_cfg: esp_hosted_bt_host_stack_cfg_t = std::mem::zeroed();
        bt_cfg.stack = esp_hosted_bt_host_stack_t_ESP_HOSTED_BT_HOST_STACK_NIMBLE;
        bt_cfg.bring_up_controller = true;
        bt_cfg.controller_ready_timeout_ms = 5_000;
        let err = esp_hosted_bt_host_stack_setup(&mut bt_cfg);
        assert!(err == ESP_OK, "esp_hosted_bt_host_stack_setup failed: {err}");
        info!("ESP-Hosted BT link up (C6 controller over SDIO)");

        // Initialize NimBLE
        assert!(nimble_port_init() == ESP_OK, "NimBLE init failed");

        // Configure host
        ble_hs_cfg.sync_cb = Some(on_sync);
        ble_hs_cfg.reset_cb = Some(on_reset);

        // Security manager: DISABLED for now. iOS auto-pair flow has been
        // unworkable in practice (stale iCloud Keychain LTKs, peripheral-
        // initiated Security Requests being silently ignored, etc.). The
        // bridge is therefore an OPEN BLE peripheral — anyone in range can
        // connect and write CAT. This is acceptable for current dev work
        // (single-user, short-range, controlled environment) but MUST be
        // revisited before a production release.
        //
        // To re-enable later:
        //   sm_io_cap = BLE_HS_IO_DISPLAY_ONLY
        //   sm_bonding = 1, sm_mitm = 1, sm_sc = 1
        //   key_dist = ENC | ID on both sides
        //   plus restore the encryption checks in gatt_nus_access,
        //   Ble::send / subscribed, and the ENC_CHANGE terminate path.
        ble_hs_cfg.sm_io_cap = BLE_HS_IO_NO_INPUT_OUTPUT as u8;
        ble_hs_cfg.set_sm_bonding(0);
        ble_hs_cfg.set_sm_mitm(0);
        ble_hs_cfg.set_sm_sc(0);

        // Set device name
        ble_svc_gap_device_name_set(DEVICE_NAME.as_ptr() as *const _);

        // Register GAP and GATT services
        ble_svc_gap_init();
        ble_svc_gatt_init();

        // Initialize GATT structures (must happen before registration)
        init_gatt_defs();

        // Register NUS GATT service
        let rc = ble_gatts_count_cfg(&raw const GATT_SVCS as *const _);
        assert!(rc == 0, "GATT count_cfg failed: {rc}");
        let rc = ble_gatts_add_svcs(&raw const GATT_SVCS as *const _);
        assert!(rc == 0, "GATT add_svcs failed: {rc}");

        // NVS-backed bond store is auto-initialized by nimble_port_init()
        // when CONFIG_BT_NIMBLE_NVS_PERSIST=y (set in sdkconfig.defaults).

        // Start NimBLE host task
        nimble_port_freertos_init(Some(nimble_host_task));

        info!("BLE NUS initialized");
        Self
    }

    /// Send data to the connected BLE client via NUS TX (notify).
    ///
    /// Encryption requirement DISABLED — sends as long as the client is
    /// connected and subscribed (see init() comment for context).
    pub fn send(&self, data: &[u8]) -> Result<(), &'static str> {
        let conn = CONN_HANDLE.load(Ordering::Acquire);
        if conn == BLE_HS_CONN_HANDLE_NONE as u16 || !TX_SUBSCRIBED.load(Ordering::Acquire) {
            return Err("no subscriber");
        }

        // SAFETY: NimBLE mbuf and notify APIs require unsafe. The conn_handle
        // and attr_handle are valid because we checked connection state above.
        // TX_ATTR_HANDLE is read-only after init.
        unsafe {
            let om = ble_hs_mbuf_from_flat(data.as_ptr() as *const _, data.len() as u16);
            if om.is_null() {
                error!("Failed to allocate mbuf");
                return Err("no memory");
            }

            let rc = ble_gatts_notify_custom(conn, TX_ATTR_HANDLE, om);
            if rc != 0 {
                error!("Notify failed: {rc}");
                return Err("notify failed");
            }

            debug!("NUS TX: {} bytes", data.len());
            Ok(())
        }
    }

    /// Check if a BLE client is connected.
    pub fn connected(&self) -> bool {
        CONN_HANDLE.load(Ordering::Acquire) != BLE_HS_CONN_HANDLE_NONE as u16
    }

    /// Check if the client is subscribed to TX notifications.
    /// (Encryption requirement removed — see init() comment.)
    pub fn subscribed(&self) -> bool {
        CONN_HANDLE.load(Ordering::Acquire) != BLE_HS_CONN_HANDLE_NONE as u16
            && TX_SUBSCRIBED.load(Ordering::Acquire)
    }

    /// Diagnostic-only — exposes the raw subscribe/encryption flags so
    /// `BleSender` can log a precise reason when a notify is dropped.
    pub fn tx_subscribed_for_log(&self) -> bool {
        TX_SUBSCRIBED.load(Ordering::Acquire)
    }

    pub fn link_encrypted_for_log(&self) -> bool {
        LINK_ENCRYPTED.load(Ordering::Acquire)
    }

    /// Most recent RSSI of the active connection, in dBm. Returns `None`
    /// when no client is connected or the controller refuses the query.
    /// Cheap (single HCI command), safe to call on the main loop tick.
    /// Unused on the headless sat bridge (no Health screen) — kept for
    /// parity with the S3 firmware's ble.rs.
    #[allow(dead_code)]
    pub fn rssi(&self) -> Option<i8> {
        let conn = CONN_HANDLE.load(Ordering::Acquire);
        if conn == BLE_HS_CONN_HANDLE_NONE as u16 {
            return None;
        }
        let mut rssi: i8 = 0;
        // SAFETY: `ble_gap_conn_rssi` only reads the controller-side state
        // for the supplied connection handle. We just verified the handle
        // is non-sentinel.
        let rc = unsafe { ble_gap_conn_rssi(conn, &mut rssi) };
        (rc == 0).then_some(rssi)
    }

    /// Count the persistent peer-security records in NVS (i.e. how many
    /// devices the bridge currently has bonds for). Always `0` while the
    /// security manager is disabled — see `init()` — but it's still a
    /// useful indicator on the Health screen for "did the last erase-flash
    /// actually clear bonds?".
    #[allow(dead_code)]
    pub fn bond_count(&self) -> u32 {
        let mut count: c_int = 0;
        // SAFETY: `ble_store_util_count` is a pure NVS query into NimBLE's
        // built-in store; safe to call from any task. `BLE_STORE_OBJ_TYPE_PEER_SEC`
        // is the standard "persistent bond" object type.
        let rc = unsafe {
            ble_store_util_count(BLE_STORE_OBJ_TYPE_PEER_SEC as i32, &mut count as *mut c_int)
        };
        if rc == 0 {
            count.max(0) as u32
        } else {
            0
        }
    }
}

// ---------------------------------------------------------------
// GAP event handler
// ---------------------------------------------------------------

unsafe extern "C" fn gap_event_handler(
    event: *mut ble_gap_event,
    _arg: *mut std::ffi::c_void,
) -> i32 {
    let evt = &*event;
    match evt.type_ as u32 {
        BLE_GAP_EVENT_CONNECT => {
            let conn = &evt.__bindgen_anon_1.connect;
            if conn.status == 0 {
                info!("BLE client connected (handle={})", conn.conn_handle);
                CONN_HANDLE.store(conn.conn_handle, Ordering::Release);
                LINK_ENCRYPTED.store(false, Ordering::Release);
                ble_att_set_preferred_mtu(256);
                // Do NOT proactively call ble_gap_security_initiate here.
                // On recent iOS versions, the peripheral-initiated Security
                // Request that arrives mid-service-discovery is silently
                // ignored, leaving the link in a half-state where iOS
                // never re-attempts encryption. Instead, let iOS drive:
                // when the app writes the data char, our access callback
                // returns INSUFFICIENT_ENC and iOS auto-triggers pairing.
            } else {
                warn!("BLE connection failed: {}", conn.status);
                advertise();
            }
        }
        BLE_GAP_EVENT_DISCONNECT => {
            let disc = &evt.__bindgen_anon_1.disconnect;
            info!("BLE client disconnected (reason={})", disc.reason);
            CONN_HANDLE.store(BLE_HS_CONN_HANDLE_NONE as u16, Ordering::Release);
            TX_SUBSCRIBED.store(false, Ordering::Release);
            LINK_ENCRYPTED.store(false, Ordering::Release);

            if let Some(tx) = EVENT_TX.get() {
                let _ = tx.send(BridgeEvent::BlePairingPasskey(None));
                let _ = tx.send(BridgeEvent::BleDisconnected);
            }

            advertise();
        }
        BLE_GAP_EVENT_SUBSCRIBE => {
            let sub = &evt.__bindgen_anon_1.subscribe;
            if sub.attr_handle == TX_ATTR_HANDLE {
                let subscribed = sub.cur_notify() != 0;
                TX_SUBSCRIBED.store(subscribed, Ordering::Release);
                info!(
                    "TX notifications {}",
                    if subscribed { "enabled" } else { "disabled" }
                );

                // Encryption requirement removed — fire BleConnected as
                // soon as TX is subscribed (see init() comment).
                if subscribed {
                    if let Some(tx) = EVENT_TX.get() {
                        let _ = tx.send(BridgeEvent::BleConnected);
                    }
                }
            }
        }
        BLE_GAP_EVENT_MTU => {
            let mtu = &evt.__bindgen_anon_1.mtu;
            info!("MTU updated to {}", mtu.value);
        }
        BLE_GAP_EVENT_PASSKEY_ACTION => {
            let pka = &evt.__bindgen_anon_1.passkey;
            if pka.params.action == BLE_SM_IOACT_DISP as u8 {
                // esp_random() is a hardware RNG on ESP32-S3. 6-digit range.
                let passkey = esp_random() % 1_000_000;
                let mut pkinfo: ble_sm_io = std::mem::zeroed();
                pkinfo.action = BLE_SM_IOACT_DISP as u8;
                pkinfo.__bindgen_anon_1.passkey = passkey;
                let rc = ble_sm_inject_io(pka.conn_handle, &mut pkinfo);
                if rc != 0 {
                    error!("ble_sm_inject_io failed: {rc}");
                } else {
                    info!("Pairing passkey: {:06}", passkey);
                    if let Some(tx) = EVENT_TX.get() {
                        let _ = tx.send(BridgeEvent::BlePairingPasskey(Some(passkey)));
                    }
                }
            } else {
                warn!("Unexpected passkey action: {}", pka.params.action);
            }
        }
        BLE_GAP_EVENT_ENC_CHANGE => {
            // Security disabled — log the outcome but don't gate on it
            // and don't terminate the connection. (See init() comment.)
            let ec = &evt.__bindgen_anon_1.enc_change;
            if ec.status == 0 {
                let mut desc: ble_gap_conn_desc = std::mem::zeroed();
                if ble_gap_conn_find(ec.conn_handle, &mut desc) == 0 {
                    info!(
                        "ENC_CHANGE: status=0 enc={} authen={}",
                        desc.sec_state.encrypted(),
                        desc.sec_state.authenticated(),
                    );
                }
                LINK_ENCRYPTED.store(true, Ordering::Release);
            } else {
                warn!("ENC_CHANGE: failed status={}", ec.status);
                LINK_ENCRYPTED.store(false, Ordering::Release);
            }
            if let Some(tx) = EVENT_TX.get() {
                let _ = tx.send(BridgeEvent::BlePairingPasskey(None));
            }
        }
        BLE_GAP_EVENT_REPEAT_PAIRING => {
            // Peer re-pairing: delete the stale bond so the new one sticks.
            // Fires when a peer that we have a bond for tries to start fresh
            // pairing (typically: user forgot us on the phone, or iOS rotated
            // identity). After the delete + RETRY, the SM re-runs pairing
            // using the configured params (SC + MITM + DisplayOnly), which
            // re-triggers the passkey display.
            let rp = &evt.__bindgen_anon_1.repeat_pairing;
            let mut desc: ble_gap_conn_desc = std::mem::zeroed();
            if ble_gap_conn_find(rp.conn_handle, &mut desc) == 0 {
                info!("Repeat pairing — deleting stale bond, restarting passkey flow");
                ble_store_util_delete_peer(&desc.peer_id_addr);
            } else {
                warn!("Repeat pairing event but conn_find failed");
            }
            return BLE_GAP_REPEAT_PAIRING_RETRY as i32;
        }
        BLE_GAP_EVENT_ADV_COMPLETE => {
            advertise();
        }
        other => {
            // Log every GAP event we don't already handle — diagnoses
            // weird pairing flows where iOS might be sending events we
            // expected to handle elsewhere.
            info!("GAP event {} (unhandled)", other);
        }
    }
    0
}

// ---------------------------------------------------------------
// GATT access callbacks
// ---------------------------------------------------------------

unsafe extern "C" fn gatt_nus_noop(
    _conn: u16,
    _attr: u16,
    _ctxt: *mut ble_gatt_access_ctxt,
    _arg: *mut std::ffi::c_void,
) -> i32 {
    0
}

unsafe extern "C" fn gatt_nus_access(
    _conn: u16,
    _attr: u16,
    ctxt: *mut ble_gatt_access_ctxt,
    _arg: *mut std::ffi::c_void,
) -> i32 {
    // Security checks DISABLED — see init() comment. Writes are accepted
    // unconditionally on any (encrypted or not) link.
    let ctx = &*ctxt;
    if ctx.op == BLE_GATT_ACCESS_OP_WRITE_CHR as u8 {
        let om = ctx.om;
        let len = os_mbuf_len(om) as usize;
        if len > 0 {
            let mut buf = vec![0u8; len.min(512)];
            ble_hs_mbuf_to_flat(
                om,
                buf.as_mut_ptr() as *mut _,
                buf.len() as u16,
                std::ptr::null_mut(),
            );

            debug!("NUS RX: {} bytes", buf.len());
            if let Some(tx) = EVENT_TX.get() {
                let _ = tx.send(BridgeEvent::BleData(buf));
            }
        }
        return 0;
    }
    BLE_ATT_ERR_UNLIKELY as i32
}

// ---------------------------------------------------------------
// GATT service definition
// ---------------------------------------------------------------

// NimBLE requires static lifetime for GATT service definitions.
// These are constructed as raw C structs.
//
// NOTE: The actual GATT service registration uses the raw NimBLE C API
// because esp-idf-svc's BLE wrappers don't expose NUS-level control.
// The static arrays below are filled in at init time.
//
// These must remain `static mut` because NimBLE requires stable pointers
// to these structures and writes to them during registration.

static mut NUS_SVC_UUID_BLE: ble_uuid128_t = ble_uuid128_t {
    u: ble_uuid_t {
        type_: BLE_UUID_TYPE_128 as u8,
    },
    value: [0; 16],
};

static mut NUS_RX_UUID_BLE: ble_uuid128_t = ble_uuid128_t {
    u: ble_uuid_t {
        type_: BLE_UUID_TYPE_128 as u8,
    },
    value: [0; 16],
};

static mut NUS_TX_UUID_BLE: ble_uuid128_t = ble_uuid128_t {
    u: ble_uuid_t {
        type_: BLE_UUID_TYPE_128 as u8,
    },
    value: [0; 16],
};

static mut GATT_CHR_DEFS: [ble_gatt_chr_def; 3] = unsafe { std::mem::zeroed() };
static mut GATT_SVCS: [ble_gatt_svc_def; 2] = unsafe { std::mem::zeroed() };

/// Initialize the static GATT structures. Called before `ble_gatts_count_cfg`.
unsafe fn init_gatt_defs() {
    NUS_SVC_UUID_BLE.value = NUS_SVC_UUID;
    NUS_RX_UUID_BLE.value = NUS_RX_UUID;
    NUS_TX_UUID_BLE.value = NUS_TX_UUID;

    // RX (client → bridge): chr is declared OPEN at the GATT layer so the
    // access callback actually runs. NimBLE's built-in WRITE_ENC permission
    // check returns ATT error 0x05 (INSUFFICIENT_AUTHEN) on an unencrypted
    // link, but iOS's CoreBluetooth only auto-triggers pairing on ATT 0x0F
    // (INSUFFICIENT_ENCRYPTION). The access callback (`gatt_nus_access`)
    // does the security check manually and returns the correct ATT error
    // code so iOS will prompt for the passkey.
    GATT_CHR_DEFS[0] = ble_gatt_chr_def {
        uuid: &raw const NUS_RX_UUID_BLE as *const ble_uuid_t,
        access_cb: Some(gatt_nus_access),
        arg: std::ptr::null_mut(),
        descriptors: std::ptr::null_mut(),
        flags: (BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP) as ble_gatt_chr_flags,
        min_key_size: 0,
        val_handle: std::ptr::null_mut(),
        cpfd: std::ptr::null_mut(),
    };

    // TX (bridge → client): notify chr is also OPEN at the GATT layer.
    // NimBLE's auto-created CCCD inherits permissions from the chr, and we
    // want CCCD writes to succeed *before* encryption (so iOS subscribes
    // first, then writes RX which triggers the encryption flow). Real
    // notify-time security is enforced by `Ble::send` in main.rs which
    // refuses to send while `LINK_ENCRYPTED` is false.
    GATT_CHR_DEFS[1] = ble_gatt_chr_def {
        uuid: &raw const NUS_TX_UUID_BLE as *const ble_uuid_t,
        access_cb: Some(gatt_nus_noop),
        arg: std::ptr::null_mut(),
        descriptors: std::ptr::null_mut(),
        flags: BLE_GATT_CHR_F_NOTIFY as ble_gatt_chr_flags,
        min_key_size: 0,
        val_handle: &raw mut TX_ATTR_HANDLE,
        cpfd: std::ptr::null_mut(),
    };

    // Terminator (zeroed)
    GATT_CHR_DEFS[2] = std::mem::zeroed();

    GATT_SVCS[0] = ble_gatt_svc_def {
        type_: BLE_GATT_SVC_TYPE_PRIMARY as u8,
        uuid: &raw const NUS_SVC_UUID_BLE as *const ble_uuid_t,
        includes: std::ptr::null_mut(),
        characteristics: &raw const GATT_CHR_DEFS as *const _,
    };

    // Terminator
    GATT_SVCS[1] = std::mem::zeroed();
}

// ---------------------------------------------------------------
// Advertising
// ---------------------------------------------------------------

unsafe fn advertise() {
    let mut adv_params: ble_gap_adv_params = std::mem::zeroed();
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND as u8;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN as u8;
    adv_params.itvl_min = 160; // 100ms in 0.625ms units
    adv_params.itvl_max = 240; // 150ms

    let mut fields: ble_hs_adv_fields = std::mem::zeroed();
    fields.flags = (BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP) as u8;
    fields.name = DEVICE_NAME.as_ptr();
    fields.name_len = (DEVICE_NAME.len() - 1) as u8; // exclude NUL
    fields.set_name_is_complete(1);

    let mut rsp_fields: ble_hs_adv_fields = std::mem::zeroed();
    rsp_fields.uuids128 = &raw const NUS_SVC_UUID_BLE;
    rsp_fields.num_uuids128 = 1;
    rsp_fields.set_uuids128_is_complete(1);

    ble_gap_adv_set_fields(&fields);
    ble_gap_adv_rsp_set_fields(&rsp_fields);

    // Advertise with the random-static address ensured in on_sync(), which
    // is deterministically derived from the BT eFuse MAC (so it's stable
    // across erase-flash cycles).
    let rc = ble_gap_adv_start(
        BLE_OWN_ADDR_RANDOM as u8,
        std::ptr::null(),
        BLE_HS_FOREVER,
        &adv_params,
        Some(gap_event_handler),
        std::ptr::null_mut(),
    );
    if rc != 0 && rc != BLE_HS_EALREADY as i32 {
        error!("Failed to start advertising: {rc}");
    } else {
        info!("Advertising as \"CW Sat Bridge\"");
    }
}

// ---------------------------------------------------------------
// NimBLE host callbacks
// ---------------------------------------------------------------

unsafe extern "C" fn on_sync() {
    // ESP-IDF NimBLE doesn't expose a way to set the host's public address
    // from Rust (`ble_hs_id_set_pub` isn't bound; `g_dev_addr` is declared
    // but not actually exported from NimBLE's static lib). And without a
    // public address, `ble_hs_util_ensure_addr(0)` falls back to generating
    // a *fresh* random-static address every erase-flash cycle.
    //
    // Workaround: derive a STABLE random-static address from the BT eFuse
    // MAC. The address type is "random static" in BT terms, but functionally
    // it's as stable as the public MAC because eFuse doesn't change.
    //
    // Byte order: esp_read_mac returns big-endian (wire order); NimBLE
    // expects little-endian. Random-static addresses also require the top
    // two bits to be 1 (i.e. MSB | 0xC0).
    let mut mac: [u8; 6] = [0; 6];
    // The ESP32-P4 has no BT radio and therefore no BT MAC efuse —
    // esp_read_mac(BT) returns ESP_ERR_NOT_SUPPORTED. Fall back to the
    // base MAC, which is just as stable for deriving the random-static
    // address.
    let mut rc = esp_read_mac(mac.as_mut_ptr(), esp_mac_type_t_ESP_MAC_BT);
    if rc != ESP_OK {
        rc = esp_read_mac(mac.as_mut_ptr(), esp_mac_type_t_ESP_MAC_BASE);
    }
    if rc != ESP_OK {
        error!("esp_read_mac failed: {rc}");
        return;
    }
    let rnd_addr: [u8; 6] = [mac[5], mac[4], mac[3], mac[2], mac[1], mac[0] | 0xC0];
    let rc = ble_hs_id_set_rnd(rnd_addr.as_ptr());
    if rc != 0 {
        error!("ble_hs_id_set_rnd failed: {rc}");
        return;
    }

    info!(
        "BLE address (RANDOM_STATIC, from BT MAC): {:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}",
        rnd_addr[5], rnd_addr[4], rnd_addr[3], rnd_addr[2], rnd_addr[1], rnd_addr[0]
    );

    advertise();
}

unsafe extern "C" fn on_reset(reason: i32) {
    warn!("NimBLE host reset, reason={reason}");
}

unsafe extern "C" fn nimble_host_task(_param: *mut std::ffi::c_void) {
    info!("NimBLE host task started");
    nimble_port_run();
    nimble_port_freertos_deinit();
}
