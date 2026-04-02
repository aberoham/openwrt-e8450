# Building a Custom Tailscale Package for OpenWrt 24.10

## Why OpenWrt 24.10 is Stuck on Tailscale 1.80.3

### The Go Version Wall

The sole reason is a **Go compiler version constraint** on the stable branch:

| | OpenWrt 24.10 | OpenWrt 25.12 | OpenWrt master |
|---|---|---|---|
| **Go version** | 1.23.12 (frozen) | 1.26.1 | 1.26.x |
| **Tailscale** | 1.80.3 | 1.94.1 | 1.94.2 |

Tailscale v1.82.0 bumped its `go.mod` from `go 1.23.1` to `go 1.24.0`. Since OpenWrt's
stable branch policy only allows patch-level updates to the Go compiler (1.23.6 → 1.23.12),
**no version of Tailscale newer than 1.80.3 can compile** on the 24.10 toolchain.

### The Community Debate

This triggered months of debate in the OpenWrt packages repo:

- **PR #26177** — Backport Go 1.24 to 24.10. Rejected by Go maintainer: major version
  bumps violate stable branch policy and risk breaking other Go packages.
- **PR #25062** — Drop tailscale from the package feed entirely. Brad Fitzpatrick from
  Tailscale offered to ship a vendored Go toolchain. Never merged.
- **PR #26201** — Per-package binary Go versions. Closed.
- **PR #26310** — GOTOOLCHAIN override per package. Closed.
- **PR #28309** — Multi-version Go support (`golang1.25/host`, `golang1.26/host`).
  **Merged to master Jan 2026**, backported to 25.12 only. Explicitly "Do not backport to 24.10."

**Bottom line**: 24.10 will never get a Tailscale update. The branch reaches end-of-life
September 2026.

### OpenWrt 25.12 Ships Tailscale 1.94.1

OpenWrt 25.12.2 (released March 27, 2026) includes Go 1.26.1 and Tailscale 1.94.1.
However, Tailscale is not in the pre-built binary package feed — it must be compiled
from source using the OpenWrt SDK (Go packages are too large for the binary CDN).

## Why the OpenWrt Binary is 23MB vs Tailscale's 38+29MB

Three techniques combine for a ~3x size reduction:

### 1. Combined Binary Mode (`ts_include_cli`)

OpenWrt builds **only `tailscaled`** with the `ts_include_cli` build tag, which embeds
the CLI into the daemon. `tailscale` is then a symlink to `tailscaled` (the binary
detects `argv[0]` to switch modes). Tailscale's official distribution ships two separate
binaries that don't support this mode.

### 2. Feature Omission Build Tags

Unused code is excluded at compile time:

| Build Tag | Removes | Size Impact |
|---|---|---|
| `ts_omit_aws` | AWS integration | Moderate |
| `ts_omit_bird` | BIRD routing daemon support | Small |
| `ts_omit_tap` | TAP device support | Small |
| `ts_omit_kube` | Kubernetes operator/proxy | Large |
| `ts_omit_completion` | Shell tab-completions | Small |
| `ts_omit_systray` | Desktop system tray GUI | Moderate |
| `ts_omit_taildrop` | Taildrop file sharing | Moderate |
| `ts_omit_tpm` | TPM hardware attestation | Small |

The 24.10 Makefile uses the first 6 tags. The master/25.12 Makefile adds `ts_omit_systray`,
`ts_omit_taildrop`, and `ts_omit_tpm`.

### 3. External Linking + Strip

OpenWrt's Go build infrastructure uses:
- `CGO_ENABLED=1` with `-linkmode external` — produces an externally-linked ELF binary
- `$(TARGET_CROSS)strip --strip-all` — removes debug info, DWARF symbols, and comments

Tailscale's official static binary is pure-Go (`CGO_ENABLED=0`), statically linked, and
ships **unstripped with full debug info**. Standard `strip` is ineffective on pure-Go
binaries — the equivalent is `-ldflags="-s -w"` at build time.

**Combined effect**: ~23MB (OpenWrt) vs ~67MB (official static, two binaries).

## Key Fixes Between 1.80.3 and 1.96.4

Relevant to the E8450 as a subnet router / exit node:

| Version | Fix | Relevance |
|---|---|---|
| **1.96.2** | **Firewall rules correctly mark traffic, fixing reverse path filtering drops** | **HIGH** — likely cause of hairpin issues |
| **1.96.2** | UPnP works during long-lived port mapping with hard NAT | High for NAT traversal |
| **1.94.2** | Memory leak from high network map response rates | High for 512MB RAM router |
| **1.92.5** | TPM/state encryption rolled back to off-by-default | Prevents startup failures on TPM-less devices |
| **1.92.3** | **WireGuard configuration panic fix** | **HIGH** — could cause kernel crash |
| **1.90.9** | Deadlock during event bursts | High for stability |
| **1.90.8** | Security fix TS-2025-008 (signing check bypass) | Medium |
| **1.90.4** | Deadlock checking network availability | High for stability |
| **1.90.3** | Startup fix for no-router-configuration environments | Medium |
| **1.86.2** | Deadlock and port mapping crash fixes | High for stability |
| **1.82.5** | CUBIC congestion control panic fix | Medium |
| **1.82.0** | NAT traversal DERP fallback improvement | Medium |

The **WireGuard panic (fixed in 1.92.3)** and the **reverse path filtering fix (1.96.2)**
are the most likely candidates for the March 20 kernel crash, especially if traffic was
being hairpinned through the exit node.

## Build Plan

### What We're Building

A custom `tailscaled` binary for aarch64 (Cortex-A53) that:
- Matches the OpenWrt package recipe exactly
- Uses Tailscale v1.96.4 source
- Includes all OpenWrt build tags (combined binary, feature omission)
- Is stripped for minimal size
- Drops into the existing OpenWrt init script / config without changes

### Target Build Command

The core `go build` command, derived from the OpenWrt Makefile:

```bash
CGO_ENABLED=0 \
GOOS=linux \
GOARCH=arm64 \
go build \
  -tags "ts_include_cli,ts_omit_aws,ts_omit_bird,ts_omit_completion,ts_omit_kube,ts_omit_systray,ts_omit_taildrop,ts_omit_tap,ts_omit_tpm" \
  -ldflags "-s -w -X 'tailscale.com/version.longStamp=1.96.4-1 (OpenWrt-custom)' -X tailscale.com/version.shortStamp=1.96.4" \
  -o tailscaled \
  tailscale.com/cmd/tailscaled
```

Notes:
- We use `CGO_ENABLED=0` for a fully static binary (no musl dependency), paired with
  `-ldflags="-s -w"` for stripping (since `strip --strip-all` doesn't work on pure-Go).
- OpenWrt uses `CGO_ENABLED=1` + external linking + cross-strip, but CGO=0 with `-s -w`
  produces equivalent or smaller binaries and avoids needing a C cross-compiler.
- The `ts_include_cli` tag is critical — it enables the combined binary mode where
  `tailscale` works as a symlink to `tailscaled`.

### Dockerfile

```dockerfile
FROM golang:1.26-bookworm

ARG TAILSCALE_VERSION=1.96.4

WORKDIR /build

# Download and extract tailscale source
RUN curl -sL "https://github.com/tailscale/tailscale/archive/refs/tags/v${TAILSCALE_VERSION}.tar.gz" \
    | tar xz --strip-components=1

# Build the combined binary for aarch64
RUN CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=arm64 \
    go build \
      -tags "ts_include_cli,ts_omit_aws,ts_omit_bird,ts_omit_completion,ts_omit_kube,ts_omit_systray,ts_omit_taildrop,ts_omit_tap,ts_omit_tpm" \
      -ldflags "-s -w \
        -X 'tailscale.com/version.longStamp=${TAILSCALE_VERSION}-1 (OpenWrt-custom)' \
        -X tailscale.com/version.shortStamp=${TAILSCALE_VERSION}" \
      -o /out/tailscaled \
      tailscale.com/cmd/tailscaled

# Verify
RUN file /out/tailscaled && ls -lh /out/tailscaled
```

### Build Script (`scripts/build_tailscale.sh`)

```bash
#!/bin/bash
#
# Build a custom Tailscale binary for OpenWrt E8450 (aarch64)
# Uses the same build tags and flags as the official OpenWrt package
#
# Usage:
#   ./scripts/build_tailscale.sh [version]
#   ./scripts/build_tailscale.sh 1.96.4
#
# Requires: Docker
# Output:   private/binaries/tailscaled-<version>-aarch64

set -euo pipefail

VERSION="${1:-1.96.4}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/private/binaries"

BUILD_TAGS="ts_include_cli,ts_omit_aws,ts_omit_bird,ts_omit_completion,ts_omit_kube,ts_omit_systray,ts_omit_taildrop,ts_omit_tap,ts_omit_tpm"

echo "=== Building Tailscale ${VERSION} for aarch64 ==="
echo "Build tags: ${BUILD_TAGS}"

mkdir -p "${OUTPUT_DIR}"

docker build --platform linux/amd64 \
  --build-arg "TAILSCALE_VERSION=${VERSION}" \
  -f "${SCRIPT_DIR}/Dockerfile.tailscale" \
  -t "tailscale-builder:${VERSION}" \
  "${SCRIPT_DIR}"

# Extract the binary from the image
CONTAINER_ID=$(docker create "tailscale-builder:${VERSION}")
docker cp "${CONTAINER_ID}:/out/tailscaled" "${OUTPUT_DIR}/tailscaled-${VERSION}-aarch64"
docker rm "${CONTAINER_ID}" > /dev/null

echo ""
echo "=== Build complete ==="
ls -lh "${OUTPUT_DIR}/tailscaled-${VERSION}-aarch64"
echo ""
echo "To deploy:"
echo "  1. Copy to router:  cat ${OUTPUT_DIR}/tailscaled-${VERSION}-aarch64 | ssh root@ROUTER 'cat > /tmp/tailscaled_new && chmod +x /tmp/tailscaled_new'"
echo "  2. Test version:    ssh root@ROUTER '/tmp/tailscaled_new --version'"
echo "  3. Stop tailscale:  ssh root@ROUTER '/etc/init.d/tailscale stop'"
echo "  4. Replace binary:  ssh root@ROUTER 'mv /tmp/tailscaled_new /usr/sbin/tailscaled'"
echo "  5. Verify symlink:  ssh root@ROUTER 'ls -la /usr/sbin/tailscale'  # should point to tailscaled"
echo "  6. Start tailscale: ssh root@ROUTER '/etc/init.d/tailscale start'"
echo "  7. Check status:    ssh root@ROUTER 'tailscale status'"
```

### Testing Procedure

#### 1. Build Verification (on build host)

```bash
# Build the binary
./scripts/build_tailscale.sh 1.96.4

# Check output size — should be ~18-25MB (similar to OpenWrt's 23MB)
ls -lh private/binaries/tailscaled-1.96.4-aarch64

# Verify it's the right architecture
file private/binaries/tailscaled-1.96.4-aarch64
# Expected: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, ...stripped
```

#### 2. Router Smoke Test (non-destructive)

```bash
# Transfer to /tmp (RAM, does not touch overlay)
cat private/binaries/tailscaled-1.96.4-aarch64 | \
  ssh root@ROUTER 'cat > /tmp/tailscaled_new && chmod +x /tmp/tailscaled_new'

# Verify it runs on the router hardware
ssh root@ROUTER '/tmp/tailscaled_new --version'
# Expected: 1.96.4 ...

# Verify combined binary mode works (critical!)
ssh root@ROUTER 'ln -sf /tmp/tailscaled_new /tmp/tailscale_new && /tmp/tailscale_new version'
# Expected: should print version info (NOT "does not take non-flag arguments")
```

#### 3. Live Replacement

```bash
# Stop current tailscale
ssh root@ROUTER '/etc/init.d/tailscale stop'

# Swap binary (overlay write)
ssh root@ROUTER 'cp /tmp/tailscaled_new /usr/sbin/tailscaled'

# Verify symlink still points correctly
ssh root@ROUTER 'ls -la /usr/sbin/tailscale'

# Start and verify
ssh root@ROUTER '/etc/init.d/tailscale start'
ssh root@ROUTER 'tailscale status'
ssh root@ROUTER 'tailscale version'
```

#### 4. Validation Checks

```bash
# Confirm exit node and subnet routing still work
ssh root@ROUTER 'tailscale status --json | grep -E "ExitNode|Subnet"'

# Check firewall rules are applied
ssh root@ROUTER 'nft list ruleset | grep tailscale | head -5'

# Monitor logs for errors
ssh root@ROUTER 'logread -f | grep tailscale'
# Watch for 5 minutes — look for panics, deadlocks, or repeated errors

# Check memory usage
ssh root@ROUTER 'ps w | grep tailscaled | grep -v grep'
ssh root@ROUTER 'free -m'
```

#### 5. Rollback Plan

If anything goes wrong:
```bash
# Reinstall the OpenWrt package version (1.80.3)
ssh root@ROUTER 'opkg install --force-reinstall tailscale'
ssh root@ROUTER '/etc/init.d/tailscale start'
```

## Future Considerations

### Upgrading to OpenWrt 25.12

This is the "proper" long-term fix:
- Ships Go 1.26.1 + Tailscale 1.94.1 natively
- Kernel 6.12.71 (much newer than 24.10's 6.6.x)
- However, 25.12.2 is only 5 days old — let it mature first
- The E8450 UBI is well-supported on 25.12

### Keeping Tailscale Updated

Once we have the build script, updating is trivial:
```bash
./scripts/build_tailscale.sh 1.98.0  # or whatever the latest is
# Then deploy as above
```

### Binary Size Budget

With 84MB overlay and ~10MB used by config/packages, a ~20-25MB tailscaled binary
leaves ~50MB free — comfortable headroom.
