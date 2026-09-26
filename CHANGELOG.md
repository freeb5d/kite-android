# Changelog

## ✨ v0.3.0 — v2rayNG-style ping: sort, remove failed, test one group

Ping now works like v2rayNG:

- **Sort by delay** — fastest servers first, failed ones last (in the **⋮** menu next to Ping).
- **Remove failed servers** — deletes every server that failed the last test, after asking.
- **Test one subscription** — ping just that group instead of everything.
- **Stop** — cancel a test that's running.
- **Results are remembered** — delays stay visible after restarting, until the next test.
- **Clear results** from the same menu.
- Subscription rows keep **sync** visible and move share/edit/delete/test into a **⋮** menu,
  so long subscription names fit on phones.
- **Update download progress** — in-app updates show a progress bar, the percentage and
  the MB downloaded, until Android's installer opens.

## ✨ v0.2.0 — Kite icon and ping modes

- **New app icon** — the Kite logo, as an adaptive icon that fits every launcher shape.
- **Ping: TCP · HTTP · Real delay** — a switch and a Ping button above the server list, same
  as desktop:
  - **TCP** — time to open a connection to the server's port (fastest; only proves it's
    reachable).
  - **HTTP** — time until the server answers a plain HTTP request.
  - **Real delay** — a real request through the server via a temporary xray-core connection;
    the only mode that proves the server really works.

## ✨ v0.1.3 — Scan QR codes

- The **+** dialog has a **Scan QR** button: point the camera at a server or subscription
  QR code and it's added directly. Works offline, without Google Play services. Hidden on
  TVs; the camera is optional, so the app still installs on devices without one.

## 🐛 v0.1.2 — VLESS encryption fix, for real this time

v0.1.1 was accidentally built with the previous version of the shared desktop code (the Go
module proxy returned a cached commit), so it didn't include the VLESS encryption fix. The
core is now pinned to an exact desktop release (v0.12.2) so every build uses known code.

## 🐛 v0.1.1 — Support VLESS post-quantum encryption

- Servers using xray-core's new VLESS encryption (`encryption=mlkem768x25519plus...`)
  connected but passed no traffic (the connection test failed with `EOF`): Kite always sent
  `encryption: none`. The link's value is now used.
- Log screen: **Errors only** view (opens by default when there are errors) and a **Copy**
  button, so the log can be shared easily.

## 🎉 v0.1.0 — First Android & Android TV release

- One universal APK for every phone, tablet and Android TV (ARM 32/64-bit, x86/x86_64).
- Same core as the desktop app: `vmess://`, `vless://`, `trojan://`, `ss://` links and
  subscriptions (base64 lists, Clash/Mihomo YAML, sing-box/Xray JSON, SIP008), with xray-core.
- **VPN mode** (all apps, through Android's VpnService) or **Proxy only** (local HTTP/SOCKS).
- Subscription groups with sync, share, edit, delete, usage/expiry and auto-sync.
- Share, rename and delete servers; ping all servers.
- Connection test (exit IP, country, delay), live and total traffic, xray log viewer.
- Persistent notification with a Disconnect button.
- Kill switch via Android's "Always-on VPN" + "Block connections without VPN".
- In-app updates from GitHub Releases.
- 8 languages, dark/light theme, full TV remote (D-pad) navigation.
