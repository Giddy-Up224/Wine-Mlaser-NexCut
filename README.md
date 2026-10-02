# Wine-Mlaser
> [!WARNING] 
> 🚧 Work in Progress

Running **Mlaser** (NexCut) — the control software for the **Gweike M3 Ultra / CF1390** laser cutter — on Linux under Wine.

Tested and working: full UI, machine control, Modbus TCP to the controller.

| | |
|---|---|
| Software | Mlaser `v0.0.0.52` (internal name **NexCut**, vendor SC2000 / au3tech.cn) |
| Host | Linux Mint 22.3 (Ubuntu 24.04 base), kernel 6.17 |
| Wine | 9.0 (distro package) |
| Binary | PE32 (32-bit) MFC application |

---

## TL;DR

Extract the vendor's application first; this repository does not include it.
Use the folder that actually contains `MainApp.exe` (some archives have nested folders).

```bash
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y wine wine32:i386 winetricks

./scripts/setup-wine-mlaser.sh "/path/to/extracted/Mlaser" --cjk-fonts
./scripts/mlaser
```

Run setup and launch as your normal desktop user, not with `sudo`.
`--cjk-fonts` is optional; it installs fonts for Chinese UI text.
Setup can be rerun and preserves the app files and existing Technology data.
It refuses an existing 64-bit prefix or a non-symlink `C:/Mlaser` directory rather
than overwriting it. To use a different prefix, set an absolute `WINEPREFIX`
for both commands.

For a dedicated laser Ethernet connection, include network configuration in setup:

```bash
nmcli connection show
./scripts/setup-wine-mlaser.sh "/path/to/extracted/Mlaser" \
    --network "Wired connection 1" --address 10.1.1.100
```

Choose the connection attached to the laser, not your internet connection.
This changes and activates an existing NetworkManager profile and may interrupt
traffic on it. Only the network step requests sudo; it clears the IPv4 gateway
and prevents the laser connection from becoming the default route.
Without `--network`, setup does not change networking.

Restore that connection to DHCP with:

```bash
./scripts/setup-wine-mlaser.sh --revert-network "Wired connection 1"
```

This restores DHCP defaults, not a backup of any previous custom static settings.
Use `./scripts/setup-wine-mlaser.sh --help` for all options.

The two things that actually matter for the app: **`mfc42`** and **running from `C:`**.

---

## The three problems, and their fixes

### 1. 32-bit prefix required

`MainApp.exe` is PE32 — 32-bit. A default win64 prefix can run it, but a clean `WINEARCH=win32` prefix avoids a class of MFC issues:

```bash
export WINEPREFIX=~/.wine-mlaser WINEARCH=win32
wineboot --init
```

`wine32:i386` must be installed, and i386 multiarch enabled (`dpkg --add-architecture i386`).

### 2. Missing `MFC42.DLL`

The app bundles MFC 10 (`mfc100u.dll`, `msvcr100.dll`), but three of its own components are older VC6-era builds that need **MFC 4.2**:

```
err:module:import_dll Library MFC42.DLL (needed by Dxf2Grp.dll) not found
err:module:import_dll Library Dxf2Grp.dll (needed by AutoNest.dll) not found
err:module:import_dll Library AutoNest.dll (needed by Module\CADModule.dll) not found
```

Fix:

```bash
winetricks -q mfc42
```

This pulls `mfc42.dll` / `mfc42u.dll` out of the VC6 redistributable. The bundled `vcredist_x86.exe` does **not** cover this — it's VC++ 2010.

### 3. "Failed to create Technology folder" — run it from `C:`

This is the non-obvious one.

The app builds its parameter-database paths with a **leading backslash**:

```
\Technology\Fiber
\Technology\CO2
```

A leading backslash means *root of the current drive*. Launch the app from anywhere under your home directory and Wine maps that to **`Z:`**, which is `/`. The app then tries to create **`/Technology`** at your filesystem root, fails (not writable), and shows:

> Failed to create Technology folder.

**Fix — run it from the `C:` drive**, where it can write:

```bash
ln -s /path/to/Mlaser-v0.0.0.52 "$WINEPREFIX/drive_c/Mlaser"
mkdir -p "$WINEPREFIX/drive_c/Technology/Fiber" "$WINEPREFIX/drive_c/Technology/CO2"
wine start /wait /d 'C:\Mlaser' 'C:\Mlaser\MainApp.exe'
```

A symlink keeps your real files where they are. The launcher explicitly sets the
Windows working directory to `C:\Mlaser`, so it does not rely on Wine interpreting
a Linux working directory through a symlink. `\Technology` now resolves to
`~/.wine-mlaser/drive_c/Technology`. The launcher also recreates missing Technology
directories before starting the app.

**Newer beta builds use a different location.** File tracing of
`Mlaser-v0.0.1.51_Beta` showed Technology access under
`%LOCALAPPDATA%\NexCut\Technology`, which on this Wine profile is
`C:\users\laser\AppData\Local\NexCut\Technology`. Creating only
`C:\Technology` is not sufficient for that build. Setup and launch now ask Wine
for `%LOCALAPPDATA%` and create the full `NexCut/Technology/Fiber` and
`NexCut/Technology/CO2` directory trees there as well. Existing data is preserved;
no administrator privileges or writable Linux root folder are needed.

---

## Networking — do NOT use the built-in "Set IP"

The **ADVANCED → Set IP** button launches `File/IPSet.exe`, which **crashes under Wine**:

```
Unhandled exception: unimplemented function mprapi.dll.MprConfigGetFriendlyName
```

Wine ships `mprapi.dll` as a stub with no implementation. There is no winetricks verb or DLL override that fixes this.

**It does not matter.** `IPSet.exe` imports no socket library at all (no `ws2_32.dll`) — it cannot communicate with the laser. Its entire function is:

```
netsh interface ip set address name="<adapter>" source=static addr=10.1.1.<n> mask=255.255.255.0 gateway=10.1.1.1
```

It sets **your PC's** IP address. That's all it has ever done.

Even patched, it could not work: Wine's bundled `netsh.exe` is a stub, and Wine has no privileged path to reconfigure a Linux network interface.

**Do it natively instead:**

```bash
sudo nmcli con mod "Wired connection 1" \
    ipv4.method manual \
    ipv4.addresses 10.1.1.100/24 \
    ipv4.gateway "" \
    ipv4.never-default yes
sudo nmcli con up "Wired connection 1"
ping -c3 10.1.1.168
```

`ipv4.never-default yes` is important — without it NetworkManager may hand the default route to the isolated laser subnet and kill your internet. Do **not** set `ipv4.gateway`, despite `ipAdd.ini` listing `10.1.1.1`.

The setup script performs these network steps with `--network`. Revert with
`./scripts/setup-wine-mlaser.sh --revert-network "Wired connection 1"`.

### Machine endpoints (from `File/ipAdd.ini`)

| Device | Address | Protocol |
|---|---|---|
| Motion controller (MCC) | `10.1.1.168:502` | Modbus TCP |
| Z-follower (ZF) | `10.1.1.169:502` | Modbus TCP |
| Laser source | `10.1.1.170:10001` | raw TCP |

Modbus TCP is plain sockets — Wine passes it straight to the kernel, no special handling.

---

## What works / what doesn't

| Feature | Status |
|---|---|
| Main UI, ribbon, all tabs | ✅ |
| Axis / laser / gas / IO parameter editing | ✅ |
| Import / export of cutting parameters | ✅ |
| Modbus TCP to controller | ✅ |
| **ADVANCED → Set IP** | ❌ `mprapi` stub — use `nmcli` |
| `Report/report.exe` (Qt 5.15.2) | ⚠️ untested |

---

## Vendor telemetry

Worth knowing before you put this machine on your main LAN. See [`docs/binary-analysis.md`](docs/binary-analysis.md) for detail.

`MainApp.exe` imports `WINHTTP.dll` and contains a hardcoded vendor endpoint over **plain HTTP**:

```
http://www.au3tech.cn/key/
```

stored directly adjacent to the `MonitorIP` / `MonitorPort` strings. And `File/ipAdd.ini` configures:

```ini
MonitorIP=47.104.17.21
MonitorPort=9001
MonitorReconnInterval=300000     # every 5 minutes
```

| Endpoint | Resolves to | Host |
|---|---|---|
| `MonitorIP` (config) | `47.104.17.21` | Alibaba Cloud, no PTR |
| `au3tech.cn` (hardcoded) | `123.56.242.109` | Alibaba Cloud, Beijing |

`47.104.17.21` is **not** compiled in — it comes from `ipAdd.ini`, so it can be changed or blanked. The `au3tech.cn` URL is in the binary.

Not necessarily malicious for this class of industrial machine, but it is unsolicited outbound traffic to a third party. Firewall it if that matters to you. `scripts/watch-vendor.sh` logs exactly what is sent.

---

## Scripts

| Script | Purpose |
|---|---|
| `scripts/setup-wine-mlaser.sh` | Setup: prefix, mfc42, symlink, folders, optional fonts and network configuration |
| `scripts/mlaser` | Launcher (explicit Windows `C:` working directory so `\Technology` resolves) |
| `scripts/watch-vendor.sh` | Capture + attribute traffic to the vendor servers |

The former `laser-network.sh` functionality is now included in setup via
`--network` and `--revert-network`. The vendor-monitoring script is unchanged.

---

## Licence

Documentation and scripts: MIT. Mlaser/NexCut itself is proprietary vendor software and is **not** included here.
