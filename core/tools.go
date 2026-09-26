//go:build tools

// Keeps golang.org/x/mobile in go.mod: gomobile bind needs it, but no
// regular code imports it, so go mod tidy would drop it.
package kitecore

import _ "golang.org/x/mobile/bind"
