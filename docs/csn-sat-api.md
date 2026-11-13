# CSN Technologies S.A.T. — Network API Reference

**Date:** 2026-09-11
**Scope:** Everything CW Sweep needs to observe or command the CSN S.A.T. satellite tracker. Sourced from the vendor manual/changelog, Hamlib, and two open-source clients (Zenith, SDRLoggerPlus). Items marked **[U]** are unverified; probe the unit before relying on them.

## Summary

- Self-contained WiFi (2.4 GHz only) tracker: SGP4 from TLEs on-device, drives a Yaesu G-5400/5500/5600 rotator via the control box's 8-pin DIN, tunes an Icom radio for Doppler over its 3.5 mm CI-V jack. Web UI at `http://<ip>/`, mDNS `rotator.local`. Site refuses HTTPS.
- Vendor-documented **HTTP GET API** with JSON responses: `/track`, `/status`, `/gtrack`, plus command URLs `/?a=<letter>|p1|p2…`.
- **UDP event broadcasts on port 9932** (`SAT,START TRACK`, `SAT,AOS`, `SAT,LOS`, `SAT,TRANSPONDER`, `SAT,QSO`, `SAT,STOP`).
- Pushes ADIF QSO records to loggers; the MacLogger option is a **WSJT-X-style UDP logged-ADIF datagram on port 2237**.
- Minimal **Hamlib rigctld/rotctld server on TCP 4532/4533**; PSTRotator XML server on UDP 12000/12001; NMEA GPS on TCP 2947.
- Radio connection is **CI-V only via the IC-9700 REMOTE jack**. No CI-V passthrough. It is designed to be the exclusive tuning master.
- On the 9700 it uses **VFO mode, Main = uplink, Sub = downlink**, explicitly *not* the radio's Satellite mode. Recommended radio settings: CI-V baud 19200 (not Auto), address A2, **CI-V Transceive OFF**, Auto Repeater ON (DUP).
- Latest firmware 9.188 (2026-04-12).

## Hardware / connectivity

| Item | Detail |
|---|---|
| Rotator types (`rotatorType`) | 1 G-5500, 2 G-5400, 6 G-5600, 3 G-5600 (90° EL), 4 G-5500 (360/90), 5 PSTRotator. SPID (9.094) and Axis cameras (9.176) added; interface undocumented [U]. No GS-232 / EasyComm |
| Radio types (`rigType`) | 0 None, 1 Icom 9700/9100, 7 Icom 7100, 9 Icom 5100, 4 Icom 820H/821H/910H, 8 Hamlib SDR; Icom 2730 (9.182); Flex via Flex API |
| VFO types (`rigVFO`) | 1 Single Downlink, 2 Single Uplink, 3 A Down/B Up, 4 A Up/B Down, 5 Main Down/Sub Up, 6 **Main Up/Sub Down** |
| TLE source | `SOURCE URL` (http only), default `http://www.csntechnologies.net/SAT/csnbare.txt`; also `nasabare.txt` mirror. Transponder DB separate, editable per transponder |
| Doppler | Computed on-device; `05` writes every `UPDATE INTERVAL` ms (500 recommended) when change exceeds `MIN FREQ CHANGE` Hz; also pushed to an SDR via Hamlib TCP |
| Network | 2.4 GHz WiFi; AP fallback `CSN_SAT_XXXX` at `192.168.4.1`; two saved networks |
| Relay | NO/NC output closes 3° before AOS until LOS |

## HTTP API

All calls are `GET` on port 80. Vendor: booleans are `-1` false / `1` true; poll `/track` no faster than every ~3 s (Zenith 3 s, SDRLoggerPlus 2 s with a 1.5 s cache). No CORS headers [U]; irrelevant for URLSession.

| Endpoint | Purpose | Source |
|---|---|---|
| `GET /track` | JSON tracking state (fields below) | vendor, Zenith, SDRLoggerPlus |
| `GET /status` | `/track` fields plus settings: `call`, `tz`, `mac`, `fw`, `serial`, `rigBaud`, `rigType`, `rigAddress`, `rigVFO`, `rigInterval`, `rigMinf`, `rigip`, `rigport`, `rotatotType` [sic], `parkAZ/EL`, `readyAZ/EL`, `toleranceAZ/EL`, `tledate`, `autotle`, `tleurl`, `ssid`, `qrzl`, `qrzp` (**QRZ password in clear**), `sats`, `groundTrack`, `postpass`, … | vendor; Zenith uses it as liveness probe |
| `GET /gtrack` | JSON array of ground-track points `{Lat, Lon (radians), El, footprint (km), time}` | vendor |
| `GET /?a=U\|<satname>` | Select / start tracking a satellite by name | Zenith `sat_proxy.php` |
| `GET /cmd?a=<cmd>` | Zenith sends `r` toggle radio enable, `v` toggle Lock VFO, `d` reset to transponder center, `z` park + stop, `A\|<uid>` select transponder, `h\|<tone>` PL tone. Vendor documents these at `/?a=…`; whether both paths work is [U] | Zenith `csn.js` |
| `GET /?a=<uid>` | Select active transponder (vendor form; Zenith uses `A\|<uid>`) [U which is current] | vendor |
| `GET /?a=d` | Reset radio to satellite center frequency | vendor |
| `GET /?a=c` | Toggle continuous mode | vendor |
| `GET /?a=F\|<hz>` / `GET /?a=f` | Set / read radio frequency (Hz) | vendor |
| `GET /?a=h\|<pl>` | Set PL tone | vendor |
| `GET /?a=g\|<catno;catno;…>` | Set favorite satellites | vendor |
| `GET /?a=I\|<0\|1>` | Check for firmware update (1 forces) | vendor |
| `GET /?a=j\|<n>` | Ground-track length (+hours / −orbits) | vendor |
| `GET /?a=b\|…`, `C\|…`, `E\|…`, `e\|…`, `k\|…`, `L\|…`, `l\|…`, `m\|…` | Add transponder / center freq / AOS alarm / radio / rotator / location / park-ready. **Parameter lists blank on vendor page** | vendor |
| `GET /?a=W\|<ssid>\|<pw>` | Join WiFi network | manual FAQ |
| `GET /<serial>` | Reset UI password lockout | manual FAQ |

### `/track` JSON fields

`mode` (1 tracking / 0 idle), `time` (UTC unix), `az`, `el` (**rotator** position; 0/0 without a rotator), `flipped`, `rotEnable`, `disableFlip`, `voltsAZ`, `voltsEL`, `continuous`, `CW`, `rigEnabled`, `msg`, `popup`, `lockVFO`, `power` (0–255), `pl_0` (uplink PL), `pl_1`, `mode_0`, `mode_1`, `tbw`, `sdrc`, `sdel`, `gpsen`, `gpsats`, `gpslock`, `gpsav`, `gpslat`, `gpslon`, `gpsgr`, `lat`, `lon`, `satAZ`, `satEL`, `satName` (**clients read lowercase `satname`; match case-insensitively** [U]), `aosAZ`, `losAZ`, `satecl`, `satLat`, `satLon` (**radians**), `satFootprint` (**diameter** km), `catno`, `aosTime`, `losTime` (unix), `rng` (km), `maxEL`, `ttaos`, `ttlos` (seconds), `afreq` (uid of active transponder), `freq[]` = `{uid, descr, upFreq, downFreq (center Hz), upMode, downMode, plu, pld, flags, fdwnr, fbw, dop_up, dop_down, off_up, off_down, sort}`. SDRLoggerPlus also reads `fw`, `satAlt`, `rssi` [U].

**Doppler-corrected frequencies** are not single fields. For the entry with `uid == afreq`: uplink = `upFreq + off_up + dop_up`, downlink = `downFreq + off_down + dop_down`.

## UDP broadcasts (port 9932, newline-terminated)

```
SAT,BOOT,<serial>,<fw>
SAT,START TRACK,<name>,<catno>
SAT,AOS,<az>
SAT,LOS,<az>
SAT,MAXEL,<el>
SAT,TRANSPONDER,<name>,<upHz>,<upMode>,<downHz>,<downMode>
SAT,STOP
SAT,QSO,<sat>,<call>,<grid>,<mode>,<comment>,<rstS>,<rstR>,<up>,<down>,<name>
```

Example QSO line: `SAT,QSO,LEDSAT,KC2SYF,fn30ha,PKT,Thanks!,59,59,435.311036,435.188964,Mike` (frequencies in **MHz** despite the doc saying Hz). Changelog also mentions a "periodic UDP tracking packet" (8.744) and a favorite-approaching-AOS broadcast (9.176); formats undocumented [U].

## Hamlib server (TCP 4532 rig, 4533 rotator)

Supported only: `F<hz>`, `f`, `M<mode>` (FM/AM/USB/LSB/CW, `-D` suffix = data), `V<x>` (Up/Down/A/B/TX/RX/Main/Sub), `P az el`, `p`. Commands are honored on either port. No PTT. "When tracking with a PC program do not simultaneously track with the S.A.T."

## PSTRotator server (UDP 12000 in / 12001 out)

`<PST><AZIMUTH>xxx.x</AZIMUTH></PST>`, `<PST><ELEVATION>…</ELEVATION></PST>`, `<PST>AZ?</PST>`, `<PST>EL?</PST>`, `<PST><STOP>1</STOP></PST>`; replies to sender on 12001.

## Logger push (`QSO LOG TYPE` + `QSO LOG IP`)

| Logger | Transport |
|---|---|
| Ham Radio Deluxe | UDP QSO forwarding |
| DXKeeper / DX Commander | Network ADIF record, DXKeeper on `<port>+1` (default 52001); Commander port 12080, wire format undocumented [U] |
| Log4OM | UDP `ADIF_MESSAGE` |
| N1MM | WSJT-X-style UDP |
| ACLog | TCP API, default 1100 |
| **MacLogger** | **WSJT-X "Log ADIF" UDP datagram, default port 2237** |

Built-in log: up to 100–128 QSOs; ADIF 3.1 export with `SAT_NAME` (LoTW-normalized: ISS→ARISS, HADES-R→SO-124…), `PROP_MODE=SAT`, `FREQ` (uplink) / `FREQ_RX` (downlink), `SAT_MODE` (UV/VU), `MY_GRIDSQUARE`, `MY_LAT/MY_LON`, `MODE=MFSK SUBMODE=FT4` when the transponder name contains "FT4". Firmware updates are refused while log entries exist.

## Radio integration with the IC-9700

- Wiring: S.A.T. `RIG CONTROL` → 9700 `[REMOTE]`. S.A.T. settings: Type "Icom 9700/9100", 19200, A2, VFO Type **Main-Up / Sub-Down**, Update Interval 500 ms. Radio: CI-V baud 19200, Transceive OFF, Auto Repeater ON. "Do not enable Satellite Mode on the Icom 9700."
- It writes both VFO freqs and modes (incl. `-D`, FM-N, DV, CW-R), PL, power, TBW, RIT per transponder, tuning step, and the radio clock. Changelog: "automatically enable the SUB vfo", "Set the spectrum scope back to Sub when switching to full duplex", "Turn DUP off". "Restore VFO" after a pass uses memory channel 99.
- Operator model: RIT for fine tuning; `LOCK VFO` moves uplink inversely when the dial moves the downlink; `ENABLE` (red) pauses all CI-V writes.
- **No CI-V passthrough.** DXLab: "S.A.T. directly and exclusively controls your transceiver."
- Coexistence with a Mac: the 9700's `CI-V USB Port = Unlink` (default) makes USB independent of REMOTE; LAN is a third independent path. Logical contention remains: the S.A.T. rewrites both VFOs every 500 ms while tracking. A second controller should stay read-only during a pass, command through the S.A.T. (`/?a=F|<hz>` or Hamlib `F`), or pause it (`?a=r`).

## Third-party clients (evidence for the API)

- Zenith — https://github.com/magicbug/Zenith (`js/csn.js`, `api/sat_proxy.php`)
- SDRLoggerPlus — https://github.com/N8SDR1/SDRLoggerPlus (`docs/design/sat-controller-design.md`, `Services/Sat/SatMessageParser.cs`, `SatControllerService.cs`)
- Hamlib `ROT_MODEL_SATROTCTL` (`rigs/dummy/netrotctl.c`, UNTESTED)
- gpredict (vendor-tested against ports 4532/4533)

## Open questions (probe the unit)

1. Is `/cmd?a=…` real, or does everything live at `/?a=…`? Transponder select `?a=<uid>` vs `?a=A|<uid>`?
2. Exact key casing in `/track` (`satName`/`satname`, `desct`/`descr`); existence of `fw`, `satAlt`, `rssi`.
3. Parameter lists for `b`, `C`, `E`, `e`, `k`, `L`, `l`, `m`.
4. Format of the periodic UDP tracking packet and the AOS-approach broadcast; whether a transponder/Doppler broadcast has shipped.
5. Whether the 9700's CI-V Transceive is global or per-port in Unlink mode.
6. Which VFO `?a=f` / Hamlib `f` returns, and whether Hamlib `V` retargets subsequent `F`.
7. DX Commander port-12080 wire protocol.
8. Whether `/status` is reachable without auth when the UI password is set.

## Sources

- Product: http://www.csntechnologies.net/sat
- Manual (sectioned): http://www.csntechnologies.net/sat/manual3 (API `?a=1&p=api.api`, UDP `?a=1&p=api.udpbroadcast`, Hamlib `?a=1&p=api.hamlibsrv`, PSTRotator `?a=1&p=api.pstrotator`, radio `?a=1&p=config.radioset`, loggers `?a=1&p=thirdparty.*`); older manual http://www.csntechnologies.net/sat/manual
- Changelog: http://www.csntechnologies.net/satchangelog
- DXLab: https://www.dxlabsuite.com/dxlabwiki/SAT_Interoperation ; https://www.dxlabsuite.com/commander/Help/Satellite%20Tracking.htm
- Hamlib: https://github.com/Hamlib/Hamlib (`rigs/dummy/netrotctl.c`, `include/hamlib/rotlist.h`)
- Reviews: https://www.onallbands.com/taking-a-close-look-at-the-self-contained-antenna-tracker-s-a-t-from-csn-technologies-video-overview-and-review/ ; https://www.hamradioworkbench.com/podcast/hrwb-270-satellite-tracking-with-csn-technologies
