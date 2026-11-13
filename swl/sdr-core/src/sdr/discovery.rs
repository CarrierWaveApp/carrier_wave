use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn};

use crate::config::{DiscoverySection, NetworkSdrConfig, SdrOverride};
use crate::sdr::kiwi::KiwiSdrDevice;
use crate::sdr::kiwi_directory::{self, KiwiDirectoryEntry};
use crate::sdr::mock::{MockConfig, MockSdrDevice};
use crate::sdr::{KiwiStatus, SdrDevice, SdrInfo};
use crate::types::SdrId;

/// Registry of discovered and manually configured SDR devices.
pub struct SdrRegistry {
    /// All known devices keyed by their ID.
    devices: Arc<RwLock<HashMap<SdrId, DeviceEntry>>>,
    config: DiscoverySection,
    http_client: reqwest::Client,
}

struct DeviceEntry {
    info: SdrInfo,
    source: DeviceSource,
    /// Connection URL for network SDRs (KiwiSDR).
    url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum DeviceSource {
    /// Discovered via SoapySDR enumeration.
    #[allow(dead_code)]
    Soapy,
    /// Manually configured network SDR.
    Network,
    /// Auto-discovered from public KiwiSDR directory.
    Directory,
    /// Mock device (for testing).
    Mock,
}

impl SdrRegistry {
    pub fn new(config: DiscoverySection) -> Self {
        Self {
            devices: Arc::new(RwLock::new(HashMap::new())),
            config,
            http_client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(15))
                .build()
                .unwrap_or_default(),
        }
    }

    /// Run one discovery scan: enumerate local SDRs + add configured network SDRs.
    pub async fn scan(&self) {
        // 1. SoapySDR enumeration (only when feature enabled)
        #[cfg(feature = "soapy")]
        {
            match crate::sdr::soapy::enumerate_devices() {
                Ok(device_list) => {
                    for args in device_list {
                        match crate::sdr::soapy::SoapySdrDevice::from_args(args) {
                            Ok(dev) => {
                                let info = dev.info().clone();
                                let id = info.id.clone();
                                let mut devices = self.devices.write().await;
                                devices.insert(
                                    id.clone(),
                                    DeviceEntry {
                                        info: self.apply_overrides(info),
                                        source: DeviceSource::Soapy,
                                        url: None,
                                    },
                                );
                                info!(id = %id, "Discovered SoapySDR device");
                            }
                            Err(e) => {
                                warn!(error = %e, "Failed to initialize SoapySDR device");
                            }
                        }
                    }
                }
                Err(e) => {
                    warn!(error = %e, "SoapySDR enumeration failed");
                }
            }
        }

        // 2. Configured network SDRs
        for net_sdr in &self.config.network_sdrs {
            self.add_network_sdr(net_sdr).await;
        }

        // 3. KiwiSDR public directory
        if self.config.kiwisdr_directory {
            let regions = kiwi_directory::builtin_filters(&self.config.kiwisdr_regions);
            match kiwi_directory::fetch_kiwisdr_directory(&self.http_client).await {
                Ok(entries) => {
                    let filtered = kiwi_directory::filter_by_countries(&entries, &regions);
                    let count = filtered.len();
                    for entry in filtered {
                        self.add_directory_kiwi(entry).await;
                    }
                    info!(count, "KiwiSDR directory scan complete");
                }
                Err(e) => warn!(error = %e, "Failed to fetch KiwiSDR directory"),
            }
        }
    }

    /// Add a network SDR from configuration.
    async fn add_network_sdr(&self, net_config: &NetworkSdrConfig) {
        let kiwi = KiwiSdrDevice::new(&net_config.url, net_config.label.clone());
        let info = kiwi.info().clone();
        let id = info.id.clone();

        let mut devices = self.devices.write().await;
        devices.insert(
            id.clone(),
            DeviceEntry {
                info: self.apply_overrides(info),
                source: DeviceSource::Network,
                url: Some(net_config.url.clone()),
            },
        );
        info!(id = %id, url = %net_config.url, "Added network SDR");
    }

    /// Build a `KiwiStatus` from a directory entry's parsed fields.
    fn kiwi_status_from_entry(entry: &KiwiDirectoryEntry) -> KiwiStatus {
        KiwiStatus {
            users: entry.users,
            users_max: entry.users_max,
            grid: entry.grid.clone(),
            snr: entry.snr.clone(),
            antenna: entry.antenna.clone(),
            location: entry.location.clone(),
            lat: Some(entry.lat),
            lon: Some(entry.lon),
            offline: entry.offline,
        }
    }

    /// Add a KiwiSDR discovered from the public directory.
    ///
    /// If a Directory device with the same ID already exists, update its
    /// `kiwi_status` (users/slots change over time). Manually configured
    /// or non-Directory devices are never overwritten.
    async fn add_directory_kiwi(&self, entry: &KiwiDirectoryEntry) {
        let kiwi = KiwiSdrDevice::new(&entry.url, Some(entry.name.clone()));
        let mut info = kiwi.info().clone();
        let id = info.id.clone();
        let status = Self::kiwi_status_from_entry(entry);

        let mut devices = self.devices.write().await;
        if let Some(existing) = devices.get_mut(&id) {
            // Update kiwi_status for Directory entries on rescan
            if existing.source == DeviceSource::Directory {
                existing.info.kiwi_status = Some(status);
            }
            return;
        }

        info.kiwi_status = Some(status);
        devices.insert(
            id.clone(),
            DeviceEntry {
                info: self.apply_overrides(info),
                source: DeviceSource::Directory,
                url: Some(entry.url.clone()),
            },
        );
        info!(id = %id, url = %entry.url, name = %entry.name, "Added KiwiSDR from directory");
    }

    /// Register a mock SDR device (for testing).
    pub async fn add_mock(&self, id: &str, mock_config: MockConfig) {
        let mock = MockSdrDevice::new(id, mock_config);
        let info = mock.info().clone();
        let sdr_id = info.id.clone();

        let mut devices = self.devices.write().await;
        devices.insert(
            sdr_id,
            DeviceEntry {
                info: self.apply_overrides(info),
                source: DeviceSource::Mock,
                url: None,
            },
        );
    }

    /// Apply config overrides (label, antenna, etc.) to a discovered device.
    fn apply_overrides(&self, mut info: SdrInfo) -> SdrInfo {
        if let Some(overrides) = self.config.overrides.get(&info.id.0) {
            apply_override(&mut info, overrides);
        }
        // Also check serial number
        if let Some(ref serial) = info.serial {
            if let Some(overrides) = self.config.overrides.get(serial) {
                apply_override(&mut info, overrides);
            }
        }
        info
    }

    /// List all known SDR devices.
    pub async fn list(&self) -> Vec<SdrInfo> {
        let devices = self.devices.read().await;
        devices.values().map(|e| e.info.clone()).collect()
    }

    /// Get info for a specific SDR.
    pub async fn get(&self, id: &SdrId) -> Option<SdrInfo> {
        let devices = self.devices.read().await;
        devices.get(id).map(|e| e.info.clone())
    }

    /// Remove an SDR that's no longer detected.
    pub async fn remove(&self, id: &SdrId) -> bool {
        let mut devices = self.devices.write().await;
        devices.remove(id).is_some()
    }

    /// Create a concrete SdrDevice for a given ID.
    pub async fn create_device(&self, id: &SdrId) -> Option<Box<dyn SdrDevice>> {
        let devices = self.devices.read().await;
        let entry = devices.get(id)?;

        match entry.source {
            #[cfg(feature = "soapy")]
            DeviceSource::Soapy => {
                // Re-open the SoapySDR device
                // In a real impl we'd store the args; for now this is a placeholder
                None
            }
            #[cfg(not(feature = "soapy"))]
            DeviceSource::Soapy => None,
            DeviceSource::Network | DeviceSource::Directory => entry.url.as_ref().map(|url| {
                Box::new(KiwiSdrDevice::new(url, entry.info.label.clone())) as Box<dyn SdrDevice>
            }),
            DeviceSource::Mock => Some(Box::new(MockSdrDevice::new(
                &entry.info.id.0,
                MockConfig::default(),
            ))),
        }
    }

    /// Start a periodic scan loop.
    pub fn start_scan_loop(self: Arc<Self>, interval_secs: u64) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            loop {
                self.scan().await;
                tokio::time::sleep(std::time::Duration::from_secs(interval_secs)).await;
            }
        })
    }
}

fn apply_override(info: &mut SdrInfo, overrides: &SdrOverride) {
    if let Some(ref label) = overrides.label {
        info.label = Some(label.clone());
    }
    if let Some(ref antenna) = overrides.antenna {
        if !info.capabilities.antennas.contains(antenna) {
            info.capabilities.antennas.push(antenna.clone());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::DiscoverySection;

    fn test_config() -> DiscoverySection {
        DiscoverySection {
            enabled: true,
            rescan_interval_secs: 30,
            mdns_enabled: false,
            mdns_browse_types: vec![],
            overrides: HashMap::new(),
            network_sdrs: vec![],
            kiwisdr_directory: false,
            kiwisdr_regions: vec![],
        }
    }

    #[tokio::test]
    async fn registry_add_and_list_mock() {
        let registry = SdrRegistry::new(test_config());
        registry.add_mock("mock-1", MockConfig::default()).await;
        registry.add_mock("mock-2", MockConfig::default()).await;

        let devices = registry.list().await;
        assert_eq!(devices.len(), 2);
    }

    #[tokio::test]
    async fn registry_get_by_id() {
        let registry = SdrRegistry::new(test_config());
        registry.add_mock("mock-1", MockConfig::default()).await;

        let id = SdrId::from("mock-1");
        let info = registry.get(&id).await;
        assert!(info.is_some());
        assert_eq!(info.unwrap().driver, "mock");

        let missing = registry.get(&SdrId::from("nope")).await;
        assert!(missing.is_none());
    }

    #[tokio::test]
    async fn registry_remove() {
        let registry = SdrRegistry::new(test_config());
        registry.add_mock("mock-1", MockConfig::default()).await;

        let id = SdrId::from("mock-1");
        assert!(registry.remove(&id).await);
        assert_eq!(registry.list().await.len(), 0);
        assert!(!registry.remove(&id).await); // already gone
    }

    #[tokio::test]
    async fn registry_applies_overrides() {
        let mut config = test_config();
        config.overrides.insert(
            "mock-1".to_string(),
            SdrOverride {
                label: Some("My Custom Label".into()),
                antenna: Some("yagi-20m".into()),
                gain: None,
                sample_rate: None,
                enabled: None,
            },
        );

        let registry = SdrRegistry::new(config);
        registry.add_mock("mock-1", MockConfig::default()).await;

        let info = registry.get(&SdrId::from("mock-1")).await.unwrap();
        assert_eq!(info.label.as_deref(), Some("My Custom Label"));
        assert!(info.capabilities.antennas.contains(&"yagi-20m".to_string()));
    }

    #[tokio::test]
    async fn registry_create_mock_device() {
        let registry = SdrRegistry::new(test_config());
        registry.add_mock("mock-1", MockConfig::default()).await;

        let device = registry.create_device(&SdrId::from("mock-1")).await;
        assert!(device.is_some());
        let dev = device.unwrap();
        assert_eq!(dev.info().driver, "mock");
    }

    #[tokio::test]
    async fn registry_network_sdr_added_on_scan() {
        let mut config = test_config();
        config.network_sdrs.push(NetworkSdrConfig {
            driver: "kiwisdr".into(),
            url: "http://testkiwi.local:8073".into(),
            label: Some("Test Kiwi".into()),
            gain: None,
        });

        let registry = SdrRegistry::new(config);
        registry.scan().await;

        let devices = registry.list().await;
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].driver, "kiwisdr");
        assert_eq!(devices[0].label.as_deref(), Some("Test Kiwi"));
    }

    #[tokio::test]
    async fn registry_add_directory_kiwi() {
        let registry = SdrRegistry::new(test_config());
        let entry = KiwiDirectoryEntry {
            url: "http://michigan-kiwi.example.com:8073".into(),
            name: "Michigan KiwiSDR".into(),
            lat: 42.35,
            lon: -83.05,
            id: "00:1a:2b:3c:4d:5e".into(),
            users: Some(1),
            users_max: Some(4),
            grid: Some("EN72".into()),
            snr: Some("25,25".into()),
            antenna: None,
            location: Some("Michigan, United States".into()),
            offline: Some(false),
        };

        registry.add_directory_kiwi(&entry).await;
        let devices = registry.list().await;
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].driver, "kiwisdr");
        assert_eq!(devices[0].label.as_deref(), Some("Michigan KiwiSDR"));

        let status = devices[0].kiwi_status.as_ref().unwrap();
        assert_eq!(status.users, Some(1));
        assert_eq!(status.users_max, Some(4));
        assert_eq!(status.grid.as_deref(), Some("EN72"));
        assert!((status.lat.unwrap() - 42.35).abs() < 0.01);
    }

    #[tokio::test]
    async fn registry_directory_kiwi_skips_existing() {
        let mut config = test_config();
        config.network_sdrs.push(NetworkSdrConfig {
            driver: "kiwisdr".into(),
            url: "http://michigan-kiwi.example.com:8073".into(),
            label: Some("Manual Kiwi".into()),
            gain: None,
        });

        let registry = SdrRegistry::new(config);
        registry.scan().await;

        // Now try to add the same host via directory — should be skipped
        let entry = KiwiDirectoryEntry {
            url: "http://michigan-kiwi.example.com:8073".into(),
            name: "Directory Kiwi".into(),
            lat: 42.35,
            lon: -83.05,
            id: "00:1a:2b:3c:4d:5e".into(),
            users: Some(2),
            users_max: Some(4),
            grid: None,
            snr: None,
            antenna: None,
            location: None,
            offline: Some(false),
        };
        registry.add_directory_kiwi(&entry).await;

        let devices = registry.list().await;
        assert_eq!(devices.len(), 1);
        // Should keep the manual label, not overwrite with directory
        assert_eq!(devices[0].label.as_deref(), Some("Manual Kiwi"));
    }

    #[tokio::test]
    async fn create_device_for_network_kiwi_uses_url() {
        let mut config = test_config();
        config.network_sdrs.push(NetworkSdrConfig {
            driver: "kiwisdr".into(),
            url: "http://testkiwi.local:8073".into(),
            label: Some("Test Kiwi".into()),
            gain: None,
        });

        let registry = SdrRegistry::new(config);
        registry.scan().await;

        let devices = registry.list().await;
        assert_eq!(devices.len(), 1);

        let device = registry.create_device(&devices[0].id).await;
        assert!(device.is_some());
        assert_eq!(device.unwrap().info().driver, "kiwisdr");
    }

    #[tokio::test]
    async fn create_device_for_directory_kiwi() {
        let registry = SdrRegistry::new(test_config());
        let entry = KiwiDirectoryEntry {
            url: "http://dir-kiwi.example.com:8073".into(),
            name: "Directory KiwiSDR".into(),
            lat: 42.0,
            lon: -83.0,
            id: "ff:ee:dd:cc:bb:aa".into(),
            users: None,
            users_max: None,
            grid: None,
            snr: None,
            antenna: None,
            location: None,
            offline: None,
        };
        registry.add_directory_kiwi(&entry).await;

        let devices = registry.list().await;
        let device = registry.create_device(&devices[0].id).await;
        assert!(device.is_some());
        assert_eq!(device.unwrap().info().driver, "kiwisdr");
    }
}
