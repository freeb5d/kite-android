# Changelog

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
