module github.com/freeb5d/kite-android/core

go 1.27

// Shared link parser and xray config builder. Pinned to an exact desktop
// release: "@main" can resolve to a stale commit through the Go module proxy.
require github.com/freeb5d/kite v0.22.1
