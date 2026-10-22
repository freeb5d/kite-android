module github.com/freeb5d/kite-android/core

go 1.27

// Shared link parser and xray config builder. Pinned to an exact desktop
// release: "@main" can resolve to a stale commit through the Go module proxy.
require github.com/freeb5d/kite v0.26.0

// v1.260327.0 with a crash fix in its TUN UDP handler (see udp_fullcone.go).
// Newer upstream releases have the fix but reject VLESS/Trojan without TLS.
replace github.com/xtls/xray-core => ./third_party/xray-core
