# CW Bridge Firmware — Setup Guide for macOS

This guide walks you through building and flashing the CW Bridge firmware
onto a CW Bridge rev 2 board (or, for the older prototypes, a Heltec WiFi Kit
32 v3.1 — note the current pin map targets the CW Bridge PCB), on a MacBook,
from scratch. It assumes
no prior experience with embedded development.

You will install some tools, plug in a board, and run a few commands. Plan on
**45–90 minutes** for the first build. After that, rebuilding is fast (~30
seconds).

---

## What You Need

**Hardware:**
- A MacBook (Apple Silicon or Intel — both work)
- A CW Bridge rev 2 board (`hardware/bridge/`) with its RUN/FLASH switch set to
  FLASH — or a Heltec WiFi Kit 32 v3.1 board (the ESP32-S3 model — the small board with
  the OLED screen and USB-C port)
- A USB-C cable that supports **data**, not just charging (most Apple-included
  cables work; some cheap "charge-only" cables don't)

**Time:** ~45 minutes for first-time setup, ~5 minutes per rebuild after that.

---

## Skip the build — grab a prebuilt firmware

If you just want to flash an official build without setting up the Rust
toolchain, every push to `main` produces a `cw-bridge-firmware` artifact:

- **Latest builds:** https://github.com/CarrierWaveApp/carrier_wave/actions/workflows/firmware.yml
- Click the most recent green run, scroll to **Artifacts**, download
  `cw-bridge-firmware`, and unzip. Then jump to **Step 7** to flash with
  `espflash`.

You'll still need `espflash` installed (Step 4) and a data-capable USB-C
cable. Everything else can be skipped.

---

## Step 1 — Open Terminal

1. Press `⌘ + Space` to open Spotlight.
2. Type `Terminal` and press Return.

A black-and-white window will open. This is where you'll type commands. To
run a command, copy it from this guide, paste it into Terminal, and press
Return.

> **Tip:** When a command finishes, you'll see a fresh prompt (a line ending
> in `$` or `%`). If something seems stuck for more than a few minutes, it's
> probably still working — let it finish.

---

## Step 2 — Install Homebrew

Homebrew is a tool that installs other tools. If you've already used it
before, skip ahead to Step 3.

Paste this into Terminal and press Return:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

It will ask for your Mac password (the one you use to log in). Type it and
press Return — **the password won't appear as you type, that's normal**.

When it finishes, it may print two extra commands and tell you to run them
("Run these next steps…"). **Do exactly what it says** — copy and paste those
two commands. They add Homebrew to your shell.

To confirm it worked:

```bash
brew --version
```

You should see something like `Homebrew 4.x.x`.

---

## Step 3 — Install Rust

Rust is the language the firmware is written in. Paste:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

When it asks `Proceed with standard installation (default - just press enter)?`,
press Return.

When it finishes, **close Terminal completely** (`⌘ + Q`) and reopen it. This
makes the new tools available.

To confirm:

```bash
rustc --version
```

You should see something like `rustc 1.80.0`.

---

## Step 4 — Install the Espressif Toolchain

The ESP32-S3 chip needs a special version of Rust. Two commands to get it.

First, install `espup` (the installer for Espressif tools):

```bash
cargo install espup --locked
```

This takes a few minutes. When it's done:

```bash
espup install
```

This downloads the Xtensa toolchain (~1 GB) from a handful of separate
Espressif GitHub release assets (Xtensa LLVM, GCC, GDB, etc.). Because it's
pulling several large binaries from different upstream URLs, a single moved
asset or flaky network blip can fail the whole install with errors like
`failed to download asset` or `404 Not Found`. If that happens:

1. **Just rerun it.** `espup install` is resumable — already-extracted
   components are skipped, so transient failures usually clear on the second
   or third attempt.
2. **Pin a known-good toolchain.** The default tracks the latest Espressif
   Rust release; if a new release deleted or relocated an asset, fall back to
   the previous one:
   ```bash
   espup install --toolchain-version 1.85.0.0
   ```
   (Check <https://github.com/esp-rs/rust-build/releases> for current tags.)
3. **Limit targets.** We only need ESP32-S3, so skipping the other archs
   reduces the surface area for a failed download:
   ```bash
   espup install --targets esp32s3
   ```

Once it succeeds it will print a path at the end that looks like:

```
Export these environment variables...
. /Users/yourname/export-esp.sh
```

You'll need to **source that file** every time you open a new Terminal window
to build the firmware. To make life easier, add it to your shell profile so
it loads automatically:

```bash
echo '. $HOME/export-esp.sh' >> ~/.zshrc
```

Then reload your shell:

```bash
source ~/.zshrc
```

---

## Step 5 — Install the Flashing Tool

`espflash` is the tool that uploads your built firmware to the board:

```bash
cargo install espflash --locked
```

This also takes a few minutes.

To confirm:

```bash
espflash --version
```

---

## Step 6 — Get the Code

If you don't already have the Carrier Wave repository cloned, do that now.
Otherwise, skip to Step 7.

```bash
cd ~
git clone https://github.com/CarrierWaveApp/carrier_wave.git
cd carrier_wave/firmware
```

If you already have the repo, just navigate to the firmware folder:

```bash
cd ~/projects/carrier_wave/firmware
```

(Replace `~/projects/carrier_wave` with wherever you cloned it.)

---

## Step 7 — Build the Firmware

From inside the `firmware/` folder:

```bash
cargo build --release
```

**The first build takes 5–10 minutes.** It will download dependencies, compile
the ESP-IDF framework, and build the firmware. You'll see lots of output —
that's expected.

When you see a line like:

```
Finished `release` profile [optimized] target(s) in 4m 12s
```

…the firmware is built.

> **If the build fails:** the most common cause is that you opened a new
> Terminal and forgot to source the Espressif environment. Run
> `source ~/export-esp.sh` and try again. If you added the line to `.zshrc`
> in Step 4, this should happen automatically.

---

## Step 8 — Plug in the Board

1. Plug the board into your MacBook with a **USB-C data cable** (CW Bridge:
   USB-C port J9, switch SW3 on FLASH, hold BOOT and pulse RESET first).
2. The OLED screen on the board may light up. If it doesn't, that's also fine
   — the board still works.

Confirm macOS sees the board:

```bash
ls /dev/cu.*
```

You should see something like `/dev/cu.usbserial-0001` or
`/dev/cu.usbmodem...` in the list. If you don't see anything that looks like
a USB device, your cable is probably charge-only — try another one.

---

## Step 9 — Flash the Firmware

This uploads the firmware to the board and shows the board's logs:

```bash
espflash flash --monitor target/xtensa-esp32s3-espidf/release/cw-bridge
```

`espflash` will:
1. Auto-detect the board's serial port
2. Erase the existing firmware
3. Upload the new firmware (~30 seconds)
4. Reset the board and show its log output

You'll see boot messages, then `CW Bridge` should appear on the OLED screen.

**To exit the monitor:** press `Ctrl + C`.

> **First-time security:** macOS may ask whether to allow `espflash` to
> access a "USB accessory." Click **Allow**.

---

## What "Working" Looks Like

After flashing, the board boots into the home screen on the OLED:

```
CW BRIDGE                v1.0
─────────────────────────────
   BLE      USB      RAD

         20 WPM

no cable                   RX
```

The status row shows whether BLE is connected, USB is plugged in, and a
radio is detected. Until you pair, BLE is off and `no cable` shows in the
footer.

The first time your iPhone or Mac tries to connect, the OLED switches to
the **PAIRING** screen:

```
PAIRING                  v1.0
─────────────────────────────
       Enter on phone:

           123456

         CW Bridge
```

Type that 6-digit code into the iOS/macOS pairing prompt. After that, the
phone reconnects silently — the OLED stays on the home screen.

---

## Rebuilding Later

Once everything is set up, the workflow is:

```bash
cd ~/projects/carrier_wave/firmware
cargo build --release
espflash flash --monitor target/xtensa-esp32s3-espidf/release/cw-bridge
```

Rebuilds after small code changes take ~30 seconds.

---

## Troubleshooting

**"command not found: cargo"**
You closed Terminal after installing Rust without reopening it, or you
skipped the "close and reopen Terminal" step in Step 3. Quit Terminal
(`⌘ + Q`) and reopen it.

**"command not found: rustup" after running `espup install`**
You skipped Step 3 (installing Rust). Go back and do it.

**Build fails with `failed to find tool. Is xtensa-esp32s3-elf-gcc installed?`**
The Espressif environment isn't loaded. Run:
```bash
source ~/export-esp.sh
```
…and try `cargo build --release` again.

**Build fails with `error: linker xtensa-esp32s3-elf-gcc not found`**
Same fix as above.

**`espup install` fails with "failed to download" / "404 Not Found" / asset URL errors**
`espup install` fetches several large toolchain assets (Xtensa LLVM, GCC, GDB,
etc.) from separate Espressif GitHub releases. A single moved or flaky asset
fails the whole run. Try, in order:
1. **Rerun** — `espup install` is resumable, so transient failures usually
   clear on the next attempt.
2. **Limit to our target** so there are fewer downloads:
   ```bash
   espup install --targets esp32s3
   ```
3. **Pin a previous toolchain version** if a new release relocated an asset:
   ```bash
   espup install --toolchain-version 1.85.0.0
   ```
   Find current tags at <https://github.com/esp-rs/rust-build/releases>.
4. **Wipe and retry** if a partial install left bad state:
   ```bash
   espup uninstall
   espup install --targets esp32s3
   ```

**`espflash` says "no serial ports found"**
- Your cable is charge-only — swap it for one that supports data.
- Try a different USB-C port on your MacBook.
- Confirm the board has power (OLED on, or LED lit).

**`espflash` connects but flashing fails partway**
Try running it again. ESP32 flashing occasionally has hiccups. If it fails
twice in a row, hold the `BOOT` button on the board (if it has one) while
running the flash command, then release after flashing starts.

**Board shows a different pairing code each time**
Normal. Each boot generates a fresh code until something pairs with it. Once
your phone or Mac is paired, the code stays consistent.

**My phone reconnected without asking for a passkey, even after I "forgot
this device" on the phone**

The bond is stored on **both** ends — phone and bridge. Forgetting on iOS
only deletes the phone's half, but iCloud Keychain often resyncs the
encryption key back to the phone moments later, so the silent reconnect
still works.

To force a true fresh pairing you must wipe the **bridge's** stored bonds
too:

```bash
espflash erase-flash
```

…then reflash (Step 9). The bridge will boot with no bonds, the phone will
fail to encrypt with its cached key, and the passkey prompt will appear
again. (Erasing flash is also the only way to evict bonds for phones you
no longer own.)

**Want to start over completely (erase everything, reset to factory)**
Same command:
```bash
espflash erase-flash
```
Then re-flash with the command in Step 9.

---

## What's Next

Once the bridge is flashed and showing its pairing code:

1. Open Carrier Wave on your iPhone or Mac.
2. Go to **Settings → Radio → Bridge**.
3. Tap **Pair New Bridge**.
4. Enter the 6-digit code shown on the OLED.
5. Plug a USB cable from the bridge's USB host port into your radio.
6. The app should auto-detect your radio within a few seconds.

If anything in this guide didn't work, check `CLAUDE.md` in this same folder
for the more technical documentation, or ask the project maintainer for help.
