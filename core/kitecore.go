// Package kitecore is the Go side of Kite for Android, compiled into an
// Android library with gomobile. It reuses the desktop app's link parser
// (github.com/freeb5d/kite/pkg/profile) and xray config builder
// (pkg/xrayconf), and runs xray-core in-process.
//
// gomobile only passes simple types across the boundary, so servers and
// results travel as JSON strings.
package kitecore

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"runtime/debug"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"

	"github.com/freeb5d/kite/pkg/probe"
	"github.com/freeb5d/kite/pkg/profile"
	"github.com/freeb5d/kite/pkg/xrayconf"
)

// Local proxy ports while connected (both modes), so other apps can use
// Kite as an HTTP/SOCKS proxy too.
const (
	HTTPPort  = 10809
	SOCKSPort = 10808
)

func init() {
	// Go's resolver reads /etc/resolv.conf, which Android doesn't have, so
	// name lookups would fail. The app is excluded from its own VPN, so
	// these queries go out directly.
	net.DefaultResolver = &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			d := net.Dialer{Timeout: 5 * time.Second}
			conn, err := d.DialContext(ctx, network, "1.1.1.1:53")
			if err != nil {
				return d.DialContext(ctx, network, "8.8.8.8:53")
			}
			return conn, nil
		},
	}
}

// --- links & subscriptions ---

// ParseLink parses one share link and returns the server as JSON.
func ParseLink(link string) (string, error) {
	s, err := profile.ParseLink(link)
	if err != nil {
		return "", err
	}
	return toJSON(s)
}

// ShareLink turns a server (JSON) back into its standard share link.
func ShareLink(serverJSON string) (string, error) {
	var s profile.Server
	if err := json.Unmarshal([]byte(serverJSON), &s); err != nil {
		return "", err
	}
	return profile.ShareLink(s)
}

type subscriptionResult struct {
	Servers     []profile.Server           `json:"servers"`
	Notes       []string                   `json:"notes"`
	Name        string                     `json:"name"`
	Usage       *profile.SubscriptionUsage `json:"usage,omitempty"`
	UpdateHours int                        `json:"updateHours"`
	Skipped     int                        `json:"skipped"`
}

// FetchSubscription downloads and parses a subscription URL (base64 link
// list, Clash YAML, sing-box/Xray JSON, SIP008), returning JSON with the
// servers plus the provider's name/usage/update-interval headers.
func FetchSubscription(subURL string) (string, error) {
	req, err := http.NewRequest(http.MethodGet, strings.TrimSpace(subURL), nil)
	if err != nil {
		return "", fmt.Errorf("invalid subscription URL: %w", err)
	}
	req.Header.Set("User-Agent", "Kite/1.0 (compatible; v2rayNG/1.9)")
	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("fetching subscription: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("subscription server returned HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 5<<20))
	if err != nil {
		return "", fmt.Errorf("reading subscription: %w", err)
	}

	servers, notes, errs := profile.ParseSubscription(string(body))
	if len(servers) == 0 {
		if len(errs) > 0 {
			return "", fmt.Errorf("no valid servers found in subscription: %w", errs[0])
		}
		return "", errors.New("no valid servers found in subscription")
	}

	res := subscriptionResult{Servers: servers, Notes: notes, Skipped: len(errs)}
	if u, err := url.Parse(subURL); err == nil {
		res.Name = u.Host
	}
	if title := strings.TrimSpace(resp.Header.Get("Profile-Title")); title != "" {
		if enc, ok := strings.CutPrefix(title, "base64:"); ok {
			if dec, err := decodeB64(enc); err == nil {
				title = dec
			}
		}
		if title = strings.TrimSpace(title); title != "" {
			res.Name = title
		}
	}
	if usage, ok := profile.ParseSubscriptionUserinfo(resp.Header.Get("Subscription-Userinfo")); ok {
		res.Usage = &usage
	}
	res.UpdateHours, _ = strconv.Atoi(strings.TrimSpace(resp.Header.Get("Profile-Update-Interval")))
	return toJSON(res)
}

// --- connection ---

var (
	mu       sync.Mutex
	instance *core.Instance
	upCount  stats.Counter
	dnCount  stats.Counter
)

// Start connects to server (JSON). tunFd is the VpnService tunnel file
// descriptor, or -1 for proxy-only mode (local HTTP/SOCKS, no VPN).
func Start(serverJSON string, tunFd int, logPath string) error {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil {
		return errors.New("already connected")
	}

	var s profile.Server
	if err := json.Unmarshal([]byte(serverJSON), &s); err != nil {
		return err
	}
	if tunFd >= 0 {
		// xray-core's Android TUN inbound reads the fd from here.
		os.Setenv("XRAY_TUN_FD", strconv.Itoa(tunFd))
	}
	cfg, err := xrayconf.Build(s, xrayconf.Options{
		HTTPPort:  HTTPPort,
		SOCKSPort: SOCKSPort,
		TUN:       tunFd >= 0,
		LogPath:   logPath,
	})
	if err != nil {
		return err
	}
	config, err := serial.LoadJSONConfig(bytes.NewReader(cfg))
	if err != nil {
		return fmt.Errorf("invalid generated xray-core config: %w", err)
	}
	inst, err := core.New(config)
	if err != nil {
		return err
	}
	if err := inst.Start(); err != nil {
		_ = inst.Close()
		return err
	}
	instance = inst
	upCount, dnCount = nil, nil
	if sm, ok := inst.GetFeature(stats.ManagerType()).(stats.Manager); ok && sm != nil {
		upCount = counter(sm, "outbound>>>proxy>>>traffic>>>uplink")
		dnCount = counter(sm, "outbound>>>proxy>>>traffic>>>downlink")
	}
	return nil
}

// Stop disconnects. Safe to call when not connected.
func Stop() error {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		return nil
	}
	err := instance.Close()
	instance, upCount, dnCount = nil, nil, nil
	return err
}

// IsRunning reports whether xray-core is running.
func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return instance != nil
}

// Traffic returns {"uplink":n,"downlink":n} cumulative bytes this session.
func Traffic() string {
	mu.Lock()
	defer mu.Unlock()
	var up, down int64
	if upCount != nil {
		up = upCount.Value()
	}
	if dnCount != nil {
		down = dnCount.Value()
	}
	return fmt.Sprintf(`{"uplink":%d,"downlink":%d}`, up, down)
}

// TestConnection makes a real request through the tunnel (via the local
// HTTP proxy) and returns {"ip","country","delayMs"} as seen by Cloudflare.
func TestConnection() (string, error) {
	if !IsRunning() {
		return "", errors.New("not connected")
	}
	proxyURL, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", HTTPPort))
	client := &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL)}}
	start := time.Now()
	resp, err := client.Get("https://www.cloudflare.com/cdn-cgi/trace")
	if err != nil {
		return "", fmt.Errorf("request through proxy failed: %w", err)
	}
	defer resp.Body.Close()
	delay := time.Since(start).Milliseconds()
	body, _ := io.ReadAll(resp.Body)

	result := map[string]any{"delayMs": delay}
	for _, line := range strings.Split(string(body), "\n") {
		if v, ok := strings.CutPrefix(line, "ip="); ok {
			result["ip"] = strings.TrimSpace(v)
		}
		if v, ok := strings.CutPrefix(line, "loc="); ok {
			result["country"] = strings.TrimSpace(v)
		}
	}
	if result["ip"] == nil {
		return "", errors.New("unexpected response from connectivity check")
	}
	return toJSON(result)
}

// Ping measures a server's delay in ms. mode is "tcp", "http" or "real"
// (a real request through a temporary xray-core instance) -- the same
// measurement the desktop app uses (github.com/freeb5d/kite/pkg/probe).
func Ping(serverJSON, mode string) (int, error) {
	var s profile.Server
	if err := json.Unmarshal([]byte(serverJSON), &s); err != nil {
		return 0, err
	}
	return probe.Ping(s, mode)
}

// CoreVersion returns the embedded xray-core version.
func CoreVersion() string {
	if info, ok := debug.ReadBuildInfo(); ok {
		for _, dep := range info.Deps {
			if dep.Path == "github.com/xtls/xray-core" {
				return strings.TrimPrefix(dep.Version, "v")
			}
		}
	}
	return "unknown"
}

// --- helpers ---

func counter(m stats.Manager, name string) stats.Counter {
	if c := m.GetCounter(name); c != nil {
		return c
	}
	c, _ := m.RegisterCounter(name)
	return c
}

func toJSON(v any) (string, error) {
	b, err := json.Marshal(v)
	return string(b), err
}
