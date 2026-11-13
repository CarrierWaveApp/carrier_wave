# Configuration

The server is configured via a TOML file. See `examples/config.toml` for a complete example.

## Sections

### [server]

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | required | Server display name |
| `listen_addr` | string | `"0.0.0.0"` | Bind address |
| `port` | u16 | `8080` | HTTP port |

### [discovery]

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enable_soapy` | bool | `true` | Scan for SoapySDR USB devices |
| `enable_mdns` | bool | `false` | Scan for network SDRs via mDNS |
| `rescan_interval_secs` | u64 | `60` | Seconds between periodic device scans |
| `overrides` | table | `{}` | Per-device config overrides (keyed by SDR ID) |

#### [discovery.overrides.<id>]

| Field | Type | Description |
|-------|------|-------------|
| `label` | string? | Override device label |
| `max_bandwidth` | u32? | Override max bandwidth |

### [discovery.network_sdrs]

Array of network SDR entries:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier |
| `driver` | string | Backend type (`"kiwi"`) |
| `url` | string | WebSocket URL |
| `label` | string? | Display label |
| `password` | string? | Authentication password |

### [recording]

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `default_sample_rate` | u32 | `48000` | Default recording sample rate |
| `default_mode` | string | `"cw"` | Default demodulation mode |

### [storage]

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `data_dir` | path | `"./data"` | Directory for audio segment files |
| `db_path` | path | `"./data/sdr.db"` | SQLite database file path |
| `segment_duration_secs` | u64 | `300` | Duration per audio file segment (seconds) |

### [time]

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `ntp_server` | string | `"pool.ntp.org"` | NTP server for time sync |
| `sync_interval_secs` | u64 | `300` | Seconds between NTP sync attempts |

## Example

```toml
[server]
name = "my-sdr-server"
listen_addr = "0.0.0.0"
port = 8080

[discovery]
enable_soapy = true
enable_mdns = false
rescan_interval_secs = 60

[[discovery.network_sdrs]]
id = "kiwi-1"
driver = "kiwi"
url = "ws://kiwi.example.com:8073"
label = "Remote KiwiSDR"

[recording]
default_sample_rate = 48000
default_mode = "cw"

[storage]
data_dir = "./data"
db_path = "./data/sdr.db"
segment_duration_secs = 300

[time]
ntp_server = "pool.ntp.org"
sync_interval_secs = 300
```
