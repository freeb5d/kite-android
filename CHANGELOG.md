# Changelog

## 🐛 v0.7.1 — SSH default port

- A new SSH server added manually starts on port 22.

## 🔐 v0.7.0 — SSH servers

- **SSH** — use any SSH server as a proxy: password or private key (with optional
  passphrase), and optional host-key verification. Works in VPN and proxy mode; DNS is
  resolved over TCP through the tunnel.
- `ssh://user:password@host:port#name` links import (also from QR codes) and share; SSH
  servers can be added manually and edited.
- SSH carries TCP only — apps that try UDP (e.g. QUIC) fall back to TCP automatically.

## 🚀 v0.6.0 — Hysteria2 support

- **Hysteria2** — `hysteria2://` and `hy2://` links (and Hysteria2 entries in Clash, sing-box
  and Xray subscriptions) now import and connect, with Salamander obfuscation, port hopping,
  custom SNI and certificate pinning. Scan them from a QR code too.
- The server editor supports Hysteria2, and it can be added manually.
- Pinging a Hysteria2 server always measures real delay, since it runs over UDP (QUIC).

## 📺 v0.5.3 — Clearer focus on Android TV

- The control selected with the remote is now clearly highlighted with a strong tint and a
  bright outline, so it's easy to see where you are on the TV.
- The connect button is back to the Kite blue while connected.

## 🟢 v0.5.2 — Green connect button

- The connect button turns a soft green with a gentle glow while connected.

## 🎨 v0.5.1 — New app icon and TV banner

- Sharper, full-size app icon that fills the launcher shape on every phone.
- New Android TV home-screen banner with the Kite logo and name.

## 📺 v0.5.0 — Send configs from phone to TV

- **Send to TV** — on Android TV, tap the new QR button to show a code. On your phone,
  choose **Send to TV** from any server or subscription menu and scan it: the config
  arrives on the TV over your local Wi-Fi, no typing needed. Scanning the code with a
  normal camera app opens a small page where links can be pasted too.
- **More accurate TCP / HTTP ping** — the server's hostname is resolved before timing,
  and TCP ping takes the best of two handshakes, so values match the real network path.
- Fixed the connection log sometimes filling with binary data after reconnecting in VPN
  mode.

## 🔤 v0.4.2 — Vazirmatn font for Persian

- Persian now uses the **Vazirmatn** font across the whole app for clearer, more natural text.

## 🐛 v0.4.1 — Subscription list fix and tidier ping bar

- Fixed subscriptions showing **0 servers**: with sorting off, the list shown under a
  subscription was emptied on screen (the servers themselves were never lost).
- The ping bar fits on phones: TCP / HTTP / Real delay on one line, with compact Ping and
  menu buttons.
- Slightly more compact connect button, so more of the server list fits on screen.

## ✨ v0.4.0 — Edit servers and add them manually

- **Server editor** — "Edit" in a server's menu opens a full-screen editor: name, address,
  port; UUID / password / method depending on the protocol, VLESS flow and encryption, VMess
  cipher; transport (TCP with optional HTTP header, WebSocket, gRPC) with host, path and
  service name; security (none, TLS, REALITY) with SNI, fingerprint, ALPN, public key,
  short ID and spiderX.
- **Add manually** — the add dialog can create a new VLESS, VMess, Trojan or Shadowsocks
  server from scratch in the same editor.

## 🐛 v0.3.1 — Accurate real delay and connection test

**Real delay** and **Test connection** reported several hundred ms too much: they timed the
very first request through the server, which is mostly one-off setup (TCP plus the TLS /
REALITY handshakes). Both now send a warm-up request first and report the second one over
the already-open connection, comparable with other V2Ray clients.

## ✨ v0.3.0 — Ping: sort by delay, remove failed servers, test one subscription

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
