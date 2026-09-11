# Binary analysis — Mlaser / NexCut v0.0.0.52

Static analysis only (`file`, `strings`, import tables). No disassembly, no dynamic instrumentation.

## Hashes

| File | Size | SHA256 |
|---|---|---|
| `MainApp.exe` | 18 MB | `fc1802e1eb77462d209435379ca7b5d793658d73e7c3386331945b70598900e2` |
| `File/IPSet.exe` | 25 KB | `050e20ea6ab0377c6b5a2b85c146dd8a9a7286829fc9c4e8e68993c6bba74b1d` |
| `Report/report.exe` | 44 MB | `9c69201342e8931f4b7b889358c3a1e53e1d272cc239f40b9add79c92d4e2e36` |

---

## `MainApp.exe` — the control application

PE32 GUI, MFC, built with Visual Studio 2010.

**Leaked build path:**
```
D:\SC2000\NexCut\NexCut_X1_Http\Release\MainApp.pdb
```
Real product name is **NexCut**; `_Http` marks the HTTP-enabled build variant.

**Network imports:** `WINHTTP.dll`

**Hardcoded endpoint**, positioned immediately adjacent to the `MonitorIP` / `MonitorPort` strings:
```
http://www.au3tech.cn/key/
```
Plain HTTP, not HTTPS. The `/key/` path suggests licensing or activation.

**IPs found in the binary:** `10.1.1.168`, `10.1.1.169` (the machine's own controllers), `127.0.0.1`. The monitoring IP `47.104.17.21` is **not** compiled in — it is read from `File/ipAdd.ini`.

Remaining IP-shaped strings (`50.60.60.50`, `61.61.61.1`, `72.61.70.70` …) are coincidental byte sequences in binary data, not real addresses.

---

## `File/IPSet.exe` — benign, and useless under Wine

PE32 console, 25 KB, Visual Studio 2010.

**Imports:** `KERNEL32`, `IPHLPAPI`, `MPRAPI`, `MSVCP100`, `MSVCR100`

**No `ws2_32.dll`, no `wininet`, no `urlmon`.** A binary with no socket library cannot send anything anywhere. This is the strongest single statement that can be made about it.

**Entire function**, reconstructed from its strings:
```
netsh interface ip set address name="<adapter>" source=static addr=10.1.1.<n> mask=255.255.255.0 gateway=10.1.1.1
```
It calls `GetAdaptersInfo` / `GetInterfaceInfo` / `MprConfigGetFriendlyName` to resolve the adapter's display name, then `system()` to run that command.

Only IPs present: `10.1.1.1`, `255.255.255.0`.

No download-and-execute, no registry persistence, no scheduled tasks, no process injection.

**Incidental leak** — release build shipped with the developer's PDB path:
```
c:\users\zzy\documents\visual studio 2010\Projects\IPSet\Release\IPSet.pdb
```

**Under Wine** it raises on `mprapi.dll.MprConfigGetFriendlyName`, which Wine ships as an unimplemented stub. Irrelevant in practice — see README; use `nmcli`.

---

## `Report/report.exe` — Qt, clean

PE32 GUI, **Qt 5.15.2**, MSVC 2015+ runtime.

Network-capable (`WS2_32`, `WinInet`, `UrlMon` present), but no vendor endpoints found.

### False positive worth documenting

`strings` pulls ~637 domains out of this binary — `0emm.com`, `3utilities.com`, `adobeaemcloud.com`, `africa.com`, `accesscam.org` and so on. These look alarming and are **not** targets.

They are **Qt's bundled public-suffix list**, used by `QNetworkCookieJar` to decide which cookie domains are valid. Every Qt application that links QtNetwork contains it.

The only real URLs are certificate CRL/OCSP endpoints (`crl3.digicert.com`, `ocsp.digicert.com`, `crl.microsoft.com`) and Qt project boilerplate — all standard Authenticode/TLS infrastructure.

Qt's own build paths are likewise present and normal:
```
C:\Users\qt\work\qt\qtbase\plugins\imageformats\qgif.pdb
```

---

## Summary

| Binary | Verdict |
|---|---|
| `IPSet.exe` | Benign. Cannot network — no socket imports. Sets local IP via `netsh`. |
| `report.exe` | Benign. Qt app; the scary domain list is Qt's public-suffix list. |
| `MainApp.exe` | Functional, but **phones home** — WinHTTP, hardcoded `au3tech.cn` over plain HTTP, plus a configurable 5-minute monitoring beacon. |

Nothing here looks like malware. The telemetry is vendor monitoring, disclosed to no one, over unencrypted HTTP.
