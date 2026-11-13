//! Audio I/O for FT8 through the on-board ES8388 codec (U3).
//!
//! ```text
//!   Radio speaker/phones --> J8 AUDIO IN  --> C23/C24 --> ES8388 LIN1/RIN1 --> ADC --> I2S DIN  --> ESP
//!   Radio mic in         <-- J7 AUDIO OUT <-- C25/C26 <-- ES8388 LOUT1/ROUT1 <-- DAC <-- I2S DOUT <-- ESP
//! ```
//!
//! The ESP32-S3 is the I²S master (MCLK/BCLK/LRCK out) and the codec runs
//! as a slave; it is configured over the shared I²C bus at address 0x10.
//! One full-duplex I²S0 channel pair runs continuously at 16-bit stereo,
//! [`FT8_SAMPLE_RATE`]. TX writes the FT8 tone burst (mono, duplicated to
//! both channels); RX is drained by the capture task only while the app has
//! FT8 decoding enabled — DMA simply overwrites when nobody reads.
//!
//! Pin numbers live in [`crate::board`]. There is no jack plug detection on
//! the rev 2 board (the TRS switch contacts are not wired).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::Arc;

use esp_idf_hal::gpio::{Gpio3, Gpio39, Gpio40, Gpio42, Gpio43};
use esp_idf_hal::i2s::I2S0;
use esp_idf_sys::{self as sys, EspError};
use log::{info, warn};

use crate::board::{
    I2C_ADDR_ES8388, PIN_I2S_BCLK, PIN_I2S_DIN, PIN_I2S_DOUT, PIN_I2S_LRCK, PIN_I2S_MCLK,
};
use crate::i2c_bus::SharedI2c;

/// FreeRTOS portMAX_DELAY — block indefinitely.
const PORT_MAX_DELAY: u32 = u32::MAX;

/// FT8 works at 12 kHz; both input and output paths are locked to this rate.
pub const FT8_SAMPLE_RATE: u32 = 12_000;

/// One FT8 slot is 15 s of audio. Captured samples are buffered up to one full
/// slot before handing to the decoder.
pub const FT8_SLOT_SAMPLES: usize = (FT8_SAMPLE_RATE as usize) * 15;

/// LOUT1/ROUT1 analogue volume (ES8388 regs 0x2E/0x2F). 1.5 dB steps from
/// −30 dB at 0x00; 0x1E = 0 dB. −12 dB keeps a full-scale FT8 burst around
/// 250 mV RMS into a radio's mic jack — adjust at bring-up if the rig's ALC
/// slams.
const CODEC_LOUT_VOLUME: u8 = 0x0C;

// ---------------------------------------------------------------
// ES8388 codec control (I²C)
// ---------------------------------------------------------------

mod es8388 {
    pub const CONTROL1: u8 = 0x00;
    pub const CONTROL2: u8 = 0x01;
    pub const CHIPPOWER: u8 = 0x02;
    pub const ADCPOWER: u8 = 0x03;
    pub const DACPOWER: u8 = 0x04;
    pub const MASTERMODE: u8 = 0x08;
    pub const ADCCONTROL1: u8 = 0x09;
    pub const ADCCONTROL2: u8 = 0x0A;
    pub const ADCCONTROL3: u8 = 0x0B;
    pub const ADCCONTROL4: u8 = 0x0C;
    pub const ADCCONTROL5: u8 = 0x0D;
    pub const LADCVOL: u8 = 0x10;
    pub const RADCVOL: u8 = 0x11;
    pub const DACCONTROL1: u8 = 0x17;
    pub const DACCONTROL2: u8 = 0x18;
    pub const DACCONTROL3: u8 = 0x19;
    pub const LDACVOL: u8 = 0x1A;
    pub const RDACVOL: u8 = 0x1B;
    pub const DACCONTROL16: u8 = 0x26;
    pub const DACCONTROL17: u8 = 0x27;
    pub const DACCONTROL20: u8 = 0x2A;
    pub const DACCONTROL21: u8 = 0x2B;
    pub const DACCONTROL23: u8 = 0x2D;
    pub const LOUT1VOL: u8 = 0x2E;
    pub const ROUT1VOL: u8 = 0x2F;
}

/// Program the ES8388 as an I²S slave, 16-bit, single-speed, MCLK = 256·fs,
/// ADC on LIN1/RIN1 (0 dB PGA), DAC to LOUT1/ROUT1. Sequence follows the
/// Espressif ADF `es8388_init` for the ADC+DAC case.
fn codec_init(bus: &SharedI2c) -> Result<(), EspError> {
    use es8388::*;
    let w = |reg: u8, val: u8| bus.write(I2C_ADDR_ES8388, &[reg, val]);

    // Mute the DAC while everything else is reprogrammed.
    w(DACCONTROL3, 0x04)?;
    w(CONTROL2, 0x50)?;
    w(CHIPPOWER, 0x00)?;
    // Slave mode: the ESP drives MCLK/BCLK/LRCK.
    w(MASTERMODE, 0x00)?;
    // DAC path.
    w(DACPOWER, 0xC0)?; // DAC + outputs off during setup
    w(CONTROL1, 0x12)?; // play & record mode
    w(DACCONTROL1, 0x18)?; // 16-bit I2S (Philips)
    w(DACCONTROL2, 0x02)?; // single speed, MCLK/LRCK = 256
    w(DACCONTROL16, 0x00)?; // mixer inputs LIN1/RIN1
    w(DACCONTROL17, 0x90)?; // left DAC -> left mixer, 0 dB
    w(DACCONTROL20, 0x90)?; // right DAC -> right mixer, 0 dB
    w(DACCONTROL21, 0x80)?; // ADC and DAC share LRCK
    w(DACCONTROL23, 0x00)?; // VROI = 0
    w(LDACVOL, 0x00)?; // 0 dB digital
    w(RDACVOL, 0x00)?;
    w(LOUT1VOL, CODEC_LOUT_VOLUME)?;
    w(ROUT1VOL, CODEC_LOUT_VOLUME)?;
    w(DACPOWER, 0x30)?; // DAC L/R + LOUT1/ROUT1 on
                        // ADC path.
    w(ADCPOWER, 0xFF)?;
    w(ADCCONTROL1, 0x00)?; // PGA 0 dB both channels (line level from the radio)
    w(ADCCONTROL2, 0x00)?; // LIN1/RIN1 as the ADC inputs
    w(ADCCONTROL3, 0x02)?;
    w(ADCCONTROL4, 0x0C)?; // 16-bit I2S (Philips)
    w(ADCCONTROL5, 0x02)?; // single speed, MCLK/LRCK = 256
    w(LADCVOL, 0x00)?; // 0 dB digital
    w(RADCVOL, 0x00)?;
    w(ADCPOWER, 0x09)?; // ADC on, LIN/RIN on, MICBIAS off
                        // Unmute.
    w(DACCONTROL3, 0x00)?;
    Ok(())
}

// ---------------------------------------------------------------
// I²S full duplex
// ---------------------------------------------------------------

fn check(rc: sys::esp_err_t) -> Result<(), EspError> {
    match EspError::from(rc) {
        Some(err) => Err(err),
        None => Ok(()),
    }
}

/// Owns the I²S0 TX/RX channel pair and the codec. Created once at boot;
/// `None` in the main state if the codec or I²S bring-up fails (FT8 is then
/// disabled, the CAT bridge keeps running).
pub struct AudioOut {
    tx: sys::i2s_chan_handle_t,
    rx: sys::i2s_chan_handle_t,
    // Keep the peripheral/pin bindings alive for the lifetime of the driver.
    _pins: I2sPins,
}

// SAFETY: The TX handle is only used through `&mut self`; the RX handle is
// handed out as a `CaptureHandle` and only ever read from one capture task
// at a time (the main loop enforces a single capture). Both are opaque
// ESP-IDF pointers.
unsafe impl Send for AudioOut {}

struct I2sPins {
    _i2s: I2S0<'static>,
    _mclk: Gpio43<'static>,
    _bclk: Gpio39<'static>,
    _lrck: Gpio40<'static>,
    _dout: Gpio42<'static>,
    _din: Gpio3<'static>,
}

/// RX channel handle for the capture task.
#[derive(Clone, Copy)]
pub struct CaptureHandle(sys::i2s_chan_handle_t);

// SAFETY: see `AudioOut`.
unsafe impl Send for CaptureHandle {}

impl AudioOut {
    /// Configure the codec over I²C, then bring up I²S0 master full duplex at
    /// 12 kHz / 16-bit / stereo with MCLK = 256·fs.
    #[allow(clippy::too_many_arguments)]
    pub fn init(
        i2s: I2S0<'static>,
        mclk: Gpio43<'static>,
        bclk: Gpio39<'static>,
        lrck: Gpio40<'static>,
        dout: Gpio42<'static>,
        din: Gpio3<'static>,
        bus: &SharedI2c,
    ) -> Result<Self, EspError> {
        use sys::{
            i2s_chan_config_t, i2s_chan_handle_t, i2s_channel_enable, i2s_channel_init_std_mode,
            i2s_new_channel, i2s_std_clk_config_t, i2s_std_config_t, i2s_std_gpio_config_t,
            i2s_std_slot_config_t,
        };

        codec_init(bus)?;

        #[allow(clippy::needless_update)]
        let chan_cfg = i2s_chan_config_t {
            id: sys::i2s_port_t_I2S_NUM_0,
            role: sys::i2s_role_t_I2S_ROLE_MASTER,
            dma_desc_num: 4,
            dma_frame_num: 240,
            // `..zeroed()` covers fields added in newer ESP-IDF versions.
            ..unsafe { std::mem::zeroed() }
        };

        let mut tx_handle: i2s_chan_handle_t = std::ptr::null_mut();
        let mut rx_handle: i2s_chan_handle_t = std::ptr::null_mut();
        check(unsafe { i2s_new_channel(&chan_cfg, &mut tx_handle, &mut rx_handle) })?;

        let mut std_cfg: i2s_std_config_t = unsafe { std::mem::zeroed() };
        let clk: i2s_std_clk_config_t = unsafe {
            let mut c: i2s_std_clk_config_t = std::mem::zeroed();
            c.sample_rate_hz = FT8_SAMPLE_RATE;
            c.clk_src = sys::soc_periph_i2s_clk_src_t_I2S_CLK_SRC_DEFAULT;
            c.mclk_multiple = sys::i2s_mclk_multiple_t_I2S_MCLK_MULTIPLE_256;
            c
        };
        let slot: i2s_std_slot_config_t = unsafe {
            // mirrors `I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(BITS_16, STEREO)`.
            let mut s: i2s_std_slot_config_t = std::mem::zeroed();
            s.data_bit_width = sys::i2s_data_bit_width_t_I2S_DATA_BIT_WIDTH_16BIT;
            s.slot_bit_width = sys::i2s_slot_bit_width_t_I2S_SLOT_BIT_WIDTH_AUTO;
            s.slot_mode = sys::i2s_slot_mode_t_I2S_SLOT_MODE_STEREO;
            s.slot_mask = sys::i2s_std_slot_mask_t_I2S_STD_SLOT_BOTH;
            s.ws_width = sys::i2s_data_bit_width_t_I2S_DATA_BIT_WIDTH_16BIT;
            s.ws_pol = false;
            s.bit_shift = true; // Philips I2S: 1-bit shift
            s
        };
        let gpio = i2s_std_gpio_config_t {
            mclk: PIN_I2S_MCLK,
            bclk: PIN_I2S_BCLK,
            ws: PIN_I2S_LRCK,
            dout: PIN_I2S_DOUT,
            din: PIN_I2S_DIN,
            invert_flags: unsafe { std::mem::zeroed() },
        };
        std_cfg.clk_cfg = clk;
        std_cfg.slot_cfg = slot;
        std_cfg.gpio_cfg = gpio;

        // Same config on both directions = shared clocks, full duplex.
        check(unsafe { i2s_channel_init_std_mode(tx_handle, &std_cfg) })?;
        check(unsafe { i2s_channel_init_std_mode(rx_handle, &std_cfg) })?;
        check(unsafe { i2s_channel_enable(tx_handle) })?;
        check(unsafe { i2s_channel_enable(rx_handle) })?;

        info!(
            "Audio: ES8388 @0x{:02X} + I2S0 duplex up (MCLK={}, BCLK={}, LRCK={}, DOUT={}, DIN={}, {} Hz)",
            I2C_ADDR_ES8388,
            PIN_I2S_MCLK,
            PIN_I2S_BCLK,
            PIN_I2S_LRCK,
            PIN_I2S_DOUT,
            PIN_I2S_DIN,
            FT8_SAMPLE_RATE
        );
        Ok(Self {
            tx: tx_handle,
            rx: rx_handle,
            _pins: I2sPins {
                _i2s: i2s,
                _mclk: mclk,
                _bclk: bclk,
                _lrck: lrck,
                _dout: dout,
                _din: din,
            },
        })
    }

    /// Handle for [`start_capture`].
    pub fn capture_handle(&self) -> CaptureHandle {
        CaptureHandle(self.rx)
    }

    /// Blocking write of PCM samples to the audio-out jack.
    ///
    /// Samples are 16-bit signed mono at [`FT8_SAMPLE_RATE`]; each is sent
    /// to both codec channels.
    pub fn write_pcm(&mut self, samples: &[i16]) -> Result<(), EspError> {
        const FRAMES: usize = 512;
        let mut stereo = [0i16; FRAMES * 2];
        for block in samples.chunks(FRAMES) {
            for (i, &s) in block.iter().enumerate() {
                stereo[2 * i] = s;
                stereo[2 * i + 1] = s;
            }
            let used = &stereo[..block.len() * 2];
            // SAFETY: `used` is a contiguous i16 slice; reinterpreting as bytes
            // is sound because the I2S channel writes raw bytes into its DMA ring.
            let bytes: &[u8] = unsafe {
                std::slice::from_raw_parts(used.as_ptr() as *const u8, std::mem::size_of_val(used))
            };
            let mut offset = 0;
            while offset < bytes.len() {
                let mut written: usize = 0;
                let rc = unsafe {
                    sys::i2s_channel_write(
                        self.tx,
                        bytes.as_ptr().add(offset) as *const _,
                        bytes.len() - offset,
                        &mut written,
                        PORT_MAX_DELAY,
                    )
                };
                if let Some(err) = EspError::from(rc) {
                    return Err(err);
                }
                if written == 0 {
                    warn!("Audio: I2S write stalled, aborting frame");
                    return Ok(());
                }
                offset += written;
            }
        }
        Ok(())
    }

    /// Silence the output by writing one buffer of zeros.
    pub fn mute(&mut self) -> Result<(), EspError> {
        self.write_pcm(&[0i16; 256])
    }
}

impl Drop for AudioOut {
    fn drop(&mut self) {
        unsafe {
            sys::i2s_channel_disable(self.tx);
            sys::i2s_channel_disable(self.rx);
            sys::i2s_del_channel(self.tx);
            sys::i2s_del_channel(self.rx);
        }
    }
}

// ---------------------------------------------------------------
// Audio-in capture (I²S RX from the codec ADC)
// ---------------------------------------------------------------

/// One burst of captured samples delivered to the decoder task.
pub struct CaptureChunk {
    /// Left-channel samples normalised to ±1.0.
    pub samples: Vec<f32>,
}

/// Stop handle for a running capture task.
#[derive(Clone)]
pub struct CaptureStop {
    running: Arc<AtomicBool>,
}

impl CaptureStop {
    pub fn stop(&self) {
        self.running.store(false, Ordering::SeqCst);
    }

    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::SeqCst)
    }
}

/// Start draining the codec ADC into 0.25 s chunks.
///
/// Returns `(stop_handle, rx)` where `rx` receives [`CaptureChunk`]s until
/// `stop_handle.stop()` is called.
pub fn start_capture(
    handle: CaptureHandle,
) -> Result<(CaptureStop, Receiver<CaptureChunk>), EspError> {
    let running = Arc::new(AtomicBool::new(true));
    let (tx, rx) = mpsc::channel::<CaptureChunk>();

    let task_running = running.clone();
    std::thread::Builder::new()
        .stack_size(6144)
        .name("ft8-capture".into())
        .spawn(move || {
            capture_loop(handle, task_running.clone(), tx);
            task_running.store(false, Ordering::SeqCst);
        })
        .ok();

    info!("Audio: capture started @ {} Hz", FT8_SAMPLE_RATE);
    Ok((CaptureStop { running }, rx))
}

/// Read stereo 16-bit frames from the RX channel, keep the left channel
/// (LIN1 = the tip of the audio-in jack), normalise to ±1.0 and forward
/// 0.25 s chunks over `tx`.
fn capture_loop(handle: CaptureHandle, running: Arc<AtomicBool>, tx: Sender<CaptureChunk>) {
    // 0.25 s chunks keep decoder latency bounded without overwhelming the mpsc queue.
    const CHUNK_SAMPLES: usize = (FT8_SAMPLE_RATE as usize) / 4;
    const FRAMES_PER_READ: usize = 240;

    let mut raw = [0i16; FRAMES_PER_READ * 2];
    let mut accum: Vec<f32> = Vec::with_capacity(CHUNK_SAMPLES);

    while running.load(Ordering::SeqCst) {
        let mut read_bytes: usize = 0;
        let rc = unsafe {
            sys::i2s_channel_read(
                handle.0,
                raw.as_mut_ptr() as *mut _,
                std::mem::size_of_val(&raw),
                &mut read_bytes,
                100,
            )
        };
        if rc != sys::ESP_OK {
            // Timeout when the DMA ring is briefly empty — just loop.
            continue;
        }
        let frames = read_bytes / (2 * std::mem::size_of::<i16>());
        for frame in 0..frames {
            let left = raw[2 * frame];
            accum.push(left as f32 / 32768.0);
            if accum.len() >= CHUNK_SAMPLES {
                let chunk = CaptureChunk {
                    samples: std::mem::replace(&mut accum, Vec::with_capacity(CHUNK_SAMPLES)),
                };
                if tx.send(chunk).is_err() {
                    // Downstream gone — exit cleanly.
                    running.store(false, Ordering::SeqCst);
                    break;
                }
            }
        }
    }
}
