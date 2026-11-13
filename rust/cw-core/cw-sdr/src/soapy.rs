//! SoapySDR backend (macOS), loaded at runtime with `dlopen` so the app runs
//! without SoapySDR installed. Covers SDRplay (SoapySDRPlay3), RTL-SDR
//! (SoapyRTLSDR) and Airspy HF+ (SoapyAirspyHF) through their Soapy modules.
//!
//! Binds the SoapySDR 0.8 C API (`SoapySDR/Device.h`); 0.7 changed the
//! `setupStream` signature, so the ABI version is checked on load. Stream
//! setup mirrors `swl/sdr-core/src/sdr/soapy.rs`.

use std::ffi::{c_char, c_int, c_long, c_longlong, c_void, CStr, CString};
use std::ptr;
use std::sync::{Arc, OnceLock};

use libloading::Library;
use num_complex::Complex32;

use crate::error::SdrError;
use crate::source::{IqSource, SourceConfig};

const SOAPY_SDR_RX: c_int = 1;
const SOAPY_SDR_TIMEOUT: c_int = -1;
const SOAPY_SDR_OVERFLOW: c_int = -4;
const FORMAT_CF32: &CStr = c"CF32";
const READ_TIMEOUT_US: c_long = 200_000;
const READ_ELEMS: usize = 16_384;

const LIBRARY_CANDIDATES: &[&str] = &[
    "/opt/homebrew/lib/libSoapySDR.dylib",
    "/usr/local/lib/libSoapySDR.dylib",
    "/opt/local/lib/libSoapySDR.dylib",
    "libSoapySDR.dylib",
];

#[repr(C)]
struct Kwargs {
    size: usize,
    keys: *mut *mut c_char,
    vals: *mut *mut c_char,
}

type Device = c_void;
type Stream = c_void;

/// Resolved SoapySDR entry points. Function pointers stay valid while
/// `_library` is alive, which it is for the life of the `Api`.
struct Api {
    _library: Library,
    last_error: unsafe extern "C" fn() -> *const c_char,
    enumerate: unsafe extern "C" fn(*const c_char, *mut usize) -> *mut Kwargs,
    kwargs_list_clear: unsafe extern "C" fn(*mut Kwargs, usize),
    kwargs_to_string: unsafe extern "C" fn(*const Kwargs) -> *mut c_char,
    free: unsafe extern "C" fn(*mut c_void),
    make: unsafe extern "C" fn(*const c_char) -> *mut Device,
    unmake: unsafe extern "C" fn(*mut Device) -> c_int,
    set_sample_rate: unsafe extern "C" fn(*mut Device, c_int, usize, f64) -> c_int,
    get_sample_rate: unsafe extern "C" fn(*const Device, c_int, usize) -> f64,
    set_frequency: unsafe extern "C" fn(*mut Device, c_int, usize, f64, *const Kwargs) -> c_int,
    set_gain_mode: unsafe extern "C" fn(*mut Device, c_int, usize, bool) -> c_int,
    set_gain: unsafe extern "C" fn(*mut Device, c_int, usize, f64) -> c_int,
    setup_stream: unsafe extern "C" fn(*mut Device, c_int, *const c_char, *const usize, usize, *const Kwargs) -> *mut Stream,
    close_stream: unsafe extern "C" fn(*mut Device, *mut Stream) -> c_int,
    activate_stream: unsafe extern "C" fn(*mut Device, *mut Stream, c_int, c_longlong, usize) -> c_int,
    deactivate_stream: unsafe extern "C" fn(*mut Device, *mut Stream, c_int, c_longlong) -> c_int,
    read_stream:
        unsafe extern "C" fn(*mut Device, *mut Stream, *const *mut c_void, usize, *mut c_int, *mut c_longlong, c_long) -> c_int,
}

/// Resolve one symbol as a plain function pointer.
///
/// # Safety
/// `T` must be the exact C signature of `name`.
unsafe fn symbol<T: Copy>(library: &Library, name: &str) -> Result<T, SdrError> {
    library
        .get::<T>(name.as_bytes())
        .map(|sym| *sym)
        .map_err(|e| SdrError::SoapyUnavailable(format!("missing symbol {name}: {e}")))
}

impl Api {
    fn load() -> Result<Api, SdrError> {
        let mut failures = Vec::new();
        for path in LIBRARY_CANDIDATES {
            // SAFETY: loading SoapySDR runs only its (trusted) static initializers.
            match unsafe { Library::new(path) } {
                Ok(library) => return unsafe { Self::bind(library) },
                Err(e) => failures.push(format!("{path}: {e}")),
            }
        }
        Err(SdrError::SoapyUnavailable(format!(
            "libSoapySDR not found (install with `brew install soapysdr`); tried {}",
            failures.join("; ")
        )))
    }

    /// # Safety
    /// `library` must be SoapySDR; signatures below match the 0.8 C API,
    /// verified via `SoapySDR_getABIVersion` before any other symbol is used.
    unsafe fn bind(library: Library) -> Result<Api, SdrError> {
        let abi_version: unsafe extern "C" fn() -> *const c_char = symbol(&library, "SoapySDR_getABIVersion")?;
        let abi = CStr::from_ptr(abi_version()).to_string_lossy().into_owned();
        if !abi.starts_with("0.8") {
            return Err(SdrError::SoapyUnavailable(format!("unsupported SoapySDR ABI {abi} (need 0.8)")));
        }
        Ok(Api {
            last_error: symbol(&library, "SoapySDRDevice_lastError")?,
            enumerate: symbol(&library, "SoapySDRDevice_enumerateStrArgs")?,
            kwargs_list_clear: symbol(&library, "SoapySDRKwargsList_clear")?,
            kwargs_to_string: symbol(&library, "SoapySDRKwargs_toString")?,
            free: symbol(&library, "SoapySDR_free")?,
            make: symbol(&library, "SoapySDRDevice_makeStrArgs")?,
            unmake: symbol(&library, "SoapySDRDevice_unmake")?,
            set_sample_rate: symbol(&library, "SoapySDRDevice_setSampleRate")?,
            get_sample_rate: symbol(&library, "SoapySDRDevice_getSampleRate")?,
            set_frequency: symbol(&library, "SoapySDRDevice_setFrequency")?,
            set_gain_mode: symbol(&library, "SoapySDRDevice_setGainMode")?,
            set_gain: symbol(&library, "SoapySDRDevice_setGain")?,
            setup_stream: symbol(&library, "SoapySDRDevice_setupStream")?,
            close_stream: symbol(&library, "SoapySDRDevice_closeStream")?,
            activate_stream: symbol(&library, "SoapySDRDevice_activateStream")?,
            deactivate_stream: symbol(&library, "SoapySDRDevice_deactivateStream")?,
            read_stream: symbol(&library, "SoapySDRDevice_readStream")?,
            _library: library,
        })
    }

    fn last_error(&self) -> String {
        // SAFETY: returns a static, NUL-terminated thread-local string.
        unsafe { CStr::from_ptr((self.last_error)()).to_string_lossy().into_owned() }
    }

    fn check(&self, status: c_int, what: &str) -> Result<(), SdrError> {
        if status == 0 {
            Ok(())
        } else {
            Err(SdrError::Device(format!("{what} failed ({status}): {}", self.last_error())))
        }
    }
}

/// The library is loaded once per process and never unloaded.
fn api() -> Result<Arc<Api>, SdrError> {
    static API: OnceLock<Result<Arc<Api>, String>> = OnceLock::new();
    API.get_or_init(|| Api::load().map(Arc::new).map_err(|e| e.to_string()))
        .clone()
        .map_err(SdrError::SoapyUnavailable)
}

/// List attached devices as Soapy args strings (e.g. `driver=sdrplay, serial=…`).
pub fn enumerate() -> Result<Vec<String>, SdrError> {
    let api = api()?;
    let mut count = 0usize;
    // SAFETY: empty args string; the returned list is freed below.
    unsafe {
        let list = (api.enumerate)(c"".as_ptr(), &mut count);
        if list.is_null() {
            return Ok(Vec::new());
        }
        let devices = (0..count)
            .map(|i| {
                let raw = (api.kwargs_to_string)(list.add(i));
                let text = CStr::from_ptr(raw).to_string_lossy().into_owned();
                (api.free)(raw.cast());
                text
            })
            .collect();
        (api.kwargs_list_clear)(list, count);
        Ok(devices)
    }
}

pub struct SoapySource {
    api: Arc<Api>,
    device: *mut Device,
    stream: *mut Stream,
    sample_rate: f64,
    buf: Vec<Complex32>,
}

// SAFETY: the device and stream handles are only used from the owning
// worker thread; SoapySDR permits moving a device between threads.
unsafe impl Send for SoapySource {}

impl SoapySource {
    pub fn open(args: &str, config: &SourceConfig) -> Result<Self, SdrError> {
        let api = api()?;
        let c_args = CString::new(args).map_err(|_| SdrError::Config("Soapy args contain NUL".into()))?;
        // SAFETY: valid C string; a null result is handled.
        let device = unsafe { (api.make)(c_args.as_ptr()) };
        if device.is_null() {
            return Err(SdrError::Device(format!("could not open '{args}': {}", api.last_error())));
        }
        // From here `Drop` releases the device on any early return.
        let mut source = SoapySource { api, device, stream: ptr::null_mut(), sample_rate: 0.0, buf: vec![Complex32::default(); READ_ELEMS] };
        source.configure(config)?;
        Ok(source)
    }

    fn configure(&mut self, config: &SourceConfig) -> Result<(), SdrError> {
        let api = Arc::clone(&self.api);
        let channels = [0usize];
        // SAFETY: `self.device` is a live device from `make`.
        unsafe {
            api.check((api.set_sample_rate)(self.device, SOAPY_SDR_RX, 0, f64::from(config.sample_rate)), "setSampleRate")?;
            self.sample_rate = (api.get_sample_rate)(self.device, SOAPY_SDR_RX, 0);
            api.check((api.set_gain_mode)(self.device, SOAPY_SDR_RX, 0, config.gain_db.is_none()), "setGainMode")?;
            if let Some(gain) = config.gain_db {
                api.check((api.set_gain)(self.device, SOAPY_SDR_RX, 0, gain), "setGain")?;
            }
            api.check((api.set_frequency)(self.device, SOAPY_SDR_RX, 0, config.center_hz, ptr::null()), "setFrequency")?;
            let stream = (api.setup_stream)(self.device, SOAPY_SDR_RX, FORMAT_CF32.as_ptr(), channels.as_ptr(), 1, ptr::null());
            if stream.is_null() {
                return Err(SdrError::Device(format!("setupStream failed: {}", api.last_error())));
            }
            self.stream = stream;
            api.check((api.activate_stream)(self.device, stream, 0, 0, 0), "activateStream")?;
        }
        if self.sample_rate <= 0.0 {
            self.sample_rate = f64::from(config.sample_rate);
        }
        Ok(())
    }
}

impl IqSource for SoapySource {
    fn read_block(&mut self) -> Result<Option<Vec<Complex32>>, SdrError> {
        let buffs = [self.buf.as_mut_ptr().cast::<c_void>()];
        let mut flags: c_int = 0;
        let mut time_ns: c_longlong = 0;
        // SAFETY: one CF32 channel; `buf` holds READ_ELEMS complex floats.
        let read = unsafe {
            (self.api.read_stream)(self.device, self.stream, buffs.as_ptr(), READ_ELEMS, &mut flags, &mut time_ns, READ_TIMEOUT_US)
        };
        match read {
            n if n >= 0 => Ok(Some(self.buf[..n as usize].to_vec())),
            SOAPY_SDR_TIMEOUT | SOAPY_SDR_OVERFLOW => Ok(Some(Vec::new())),
            code => Err(SdrError::Device(format!("readStream failed ({code}): {}", self.api.last_error()))),
        }
    }

    fn set_center_hz(&mut self, hz: f64) -> Result<(), SdrError> {
        // SAFETY: live device.
        let status = unsafe { (self.api.set_frequency)(self.device, SOAPY_SDR_RX, 0, hz, ptr::null()) };
        self.api.check(status, "setFrequency")
    }

    fn sample_rate(&self) -> f64 {
        self.sample_rate
    }
}

impl Drop for SoapySource {
    fn drop(&mut self) {
        // SAFETY: handles came from this API and are released exactly once.
        unsafe {
            if !self.stream.is_null() {
                (self.api.deactivate_stream)(self.device, self.stream, 0, 0);
                (self.api.close_stream)(self.device, self.stream);
            }
            (self.api.unmake)(self.device);
        }
    }
}
