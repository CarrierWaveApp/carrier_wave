---
title: "Satellites"
description: "Pass prediction, Doppler tuning, rotators, duplex radios, and the CW Sat Bridge"
weight: 16
showToc: true
---

The satellite pointing screen predicts passes for the active amateur satellites, shows where to point, and keeps your radios on the Doppler-corrected frequencies. Orbits come from SatNOGS TLEs and transponder data; your observer location is your grid square.

## Pointing and Doppler

Select a satellite to see the live azimuth and elevation, the sky-plot track, AOS/LOS times, and the Doppler-corrected downlink and pre-corrected uplink frequencies. The tuning readout stays visible while you steer.

## Rotator & Trackers

Open **Rotator & Trackers** from the satellite tab menu or the pointing screen. Carrier Wave looks for CSN Technologies S.A.T. units and WA4MCM PSR-100 Mk2 rotors on your network automatically (at launch, when the satellites tab opens, on network changes, and every few minutes) and asks before linking a new one. A rotator you already use is re-linked silently.

- **Add by address** probes a unit and works out its type from how it answers. Enter a whole network such as `192.168.20.0/24` to include a rotor on another VLAN; that network is remembered and swept from then on.
- **Point & Track** on the sky view slews the linked rotator onto the selected satellite and turns Follow on.
- **Manual controls**: a jog pad with a 1°, 5° or 15° step, go-to azimuth/elevation, Park and Stop. Jog buttons repeat while held. Any manual move turns Follow off so the antenna never fights the tracker.
- The sheet shows the desired target (the satellite's live az/el, or the rise azimuth before AOS) next to the pointing you have commanded.

PSR-100 Mk2 rotors are driven through their built-in web server, which crosses VLANs and needs no UDP setup.

## Duplex Radios

For FM satellites, **Duplex Radios** binds one CW Bridge to the uplink handheld and one to the downlink handheld. Choose **Auto** (both radios follow the pass prediction) or **Manual downlink** (tune the downlink by ear and the uplink follows your correction), set the uplink CTCSS tone per satellite (SO-50, ISS, AO-91, AO-92 and PO-101 are preset), and start tuning. Quansheng UV-K1 / UV-K5 V3 radios running the F4HWN CAT build are supported over USB-C through the bridge.

## Send to Bridge

With a CW Sat Bridge connected, long-press a pass in **Upcoming Passes** to build the Doppler schedule, upload it to the bridge, and arm it. The control sheet shows upload progress, the executor's live state and frequencies, a downlink/uplink VFO flip, and an abort button. The bridge flies the pass on its own clock, so the phone can go to sleep.
