#!/usr/bin/env bash
#
# Build a Debian package of the WorkBuddy AI international edition for Ubuntu,
# starting from the official macOS DMG.
#
# This is a thin, reproducible driver around two upstream community projects
# which ./bootstrap.sh fetches at pinned commits:
#
#   upstream/port-tool/   LX2000WASD/workbuddy-international-linux  (DMG -> app)
#   upstream/deb-tool/    Xboxpig/workbuddy-desktop-linux           (app -> .deb)
#
# Usage:
#   ./build-latest-candidate.sh                 convert + package
#   ./build-latest-candidate.sh --app-only      stop after the app tree
#   ./build-latest-candidate.sh --deb-only      package the existing app tree
#   ./build-latest-candidate.sh --no-bootstrap  require fetched toolchains
#
# Overridable environment:
#   DMG=/path/to/WorkBuddy.dmg               use a local DMG instead of downloading
#   DMG_SHA256=<official-feed-sha256>         expected DMG checksum
#   PKG_VERSION=5.8.4.41366630               product package version
#   BUILD_ID=73952edb                         build id from the official feed
#   ELECTRON_VERSION=37.10.3                 Linux Electron runtime to graft on
#   ELECTRON_ZIP_SHA256=<upstream-sha256>     expected Electron ZIP checksum
#   NODE_BIN_DIR=/path/to/node/bin          Node 20+ to run the toolchain with
#   WORK_ROOT=/path/to/workdir              where artifacts/ and logs/ live
#
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_ROOT="${WORK_ROOT:-$ROOT}"


PORT_TOOL="$ROOT/upstream/port-tool"
DEB_TOOL="$ROOT/upstream/deb-tool"

# ---------------------------------------------------------------- config ----
# Pinned to the version currently published by the official international
# update feed. Refresh with:
#   curl 'https://www.workbuddy.ai/v2/update?platform=workbuddy-darwin-x64'
PKG_VERSION="${PKG_VERSION:-5.8.4.41366630}"
BUILD_ID="${BUILD_ID:-73952edb}"
ELECTRON_VERSION="${ELECTRON_VERSION:-37.10.3}"
PACKAGE_NAME="workbuddy-ai"

# Isolate all mutable build state by release and build id.
APP_DIR="${APP_DIR:-$WORK_ROOT/artifacts/build/${PKG_VERSION}-${BUILD_ID}/app}"
TMP_DIR="${TMP_DIR:-$WORK_ROOT/artifacts/build/${PKG_VERSION}-${BUILD_ID}/tmp}"
NPM_CACHE="${NPM_CACHE:-$WORK_ROOT/artifacts/cache/npm/${PKG_VERSION}-${BUILD_ID}}"
LOG_DIR="${LOG_DIR:-$WORK_ROOT/logs/${PKG_VERSION}-${BUILD_ID}}"

DMG="${DMG:-$WORK_ROOT/artifacts/input/WorkBuddy-darwin-x64-${PKG_VERSION}-${BUILD_ID}.dmg}"
DMG_URL="https://codebuddy-1328495429.cos.accelerate.myqcloud.com/workbuddy/saas/darwin-x64/WorkBuddy-darwin-x64-${PKG_VERSION}-${BUILD_ID}.dmg"
# SHA256 from the official international update feed for this candidate.
# A mismatch aborts instead of silently building from different vendor bytes.
DMG_SHA256="${DMG_SHA256:-8404d7eeb2653ec49ca3f3bce4b69fd101ecf60bd1fd9f8472181108a11aa63e}"

ELECTRON_ZIP="${ELECTRON_ZIP:-$WORK_ROOT/artifacts/cache/electron-v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip}"
# npmmirror first: the GitHub release host is throttled hard from mainland
# China (~3 MB/min observed vs ~3.6 MB/s from the mirror).
ELECTRON_URL="${ELECTRON_URL:-https://npmmirror.com/mirrors/electron/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip}"
ELECTRON_ZIP_SHA256="${ELECTRON_ZIP_SHA256:-c0b4edd6bd9858cda4cf7ab299e69a2d3ecd2e5fcca78507bc0851ba35614660}"
KOFFI_VERSION="${KOFFI_VERSION:-2.16.2}"
KOFFI_SHA512="${KOFFI_SHA512:-sha512-owU0MRwv6xkrVqCd+33uw6BaYppkTRXbO/rVdJNI2dvZG0gzyRhYwW25eWtc5pauwK8TGh3AbkFONSezdykfSA==}"
KOFFI_TARBALL="${KOFFI_TARBALL:-$WORK_ROOT/artifacts/cache/npm-packages/koffi-${KOFFI_VERSION}.tgz}"
PKG_ROOT_OVERRIDE="${PKG_ROOT_OVERRIDE:-$WORK_ROOT/artifacts/package-root/${PKG_VERSION}-${BUILD_ID}}"
DIST_DIR_OVERRIDE="${DIST_DIR_OVERRIDE:-$WORK_ROOT/artifacts/packages}"

DO_APP=1
DO_DEB=1
DO_BOOTSTRAP=1
for arg in "$@"; do
    case "$arg" in
        --app-only)     DO_DEB=0 ;;
        --deb-only)     DO_APP=0 ;;
        --no-bootstrap) DO_BOOTSTRAP=0 ;;
        -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

info() { echo "[build] $*" >&2; }
die()  { echo "[build] ERROR: $*" >&2; exit 1; }

mkdir -p "$LOG_DIR" "$TMP_DIR" "$NPM_CACHE"

# ------------------------------------------------------------- bootstrap ----
ensure_upstream() {
    if [ -x "$PORT_TOOL/install.sh" ] && [ -f "$DEB_TOOL/scripts/build-deb.sh" ]; then
        return 0
    fi
    if [ "$DO_BOOTSTRAP" -eq 0 ]; then
        die "upstream toolchains missing in $ROOT/upstream and --no-bootstrap was given"
    fi
    info "upstream toolchains missing; running bootstrap.sh"
    bash "$ROOT/bootstrap.sh" || die "bootstrap failed"
    [ -x "$PORT_TOOL/install.sh" ] || die "port-tool/install.sh still missing after bootstrap"
    [ -f "$DEB_TOOL/scripts/build-deb.sh" ] || die "deb-tool/scripts/build-deb.sh still missing after bootstrap"
}

# ------------------------------------------------------------ node lookup ---
# The toolchain needs a Node 20+ on PATH. Prefer an explicit override, then
# whatever the caller already has, then a couple of common install locations.
resolve_node_bin_dir() {
    if [ -n "${NODE_BIN_DIR:-}" ]; then
        [ -x "$NODE_BIN_DIR/node" ] || die "NODE_BIN_DIR=$NODE_BIN_DIR has no node binary"
        return 0
    fi
    local cand
    for cand in \
        "$(dirname "$(command -v node 2>/dev/null || true)" 2>/dev/null)" \
        "$HOME/.workbuddy/binaries/node/versions/22.22.2/bin" \
        /usr/local/bin /usr/bin
    do
        [ -n "$cand" ] && [ -x "$cand/node" ] && { NODE_BIN_DIR="$cand"; return 0; }
    done
    die "no node found; install Node 20+ or set NODE_BIN_DIR"
}

# ------------------------------------------------------- environment fixes --
# Two host quirks break the upstream toolchain. Both are harmless no-ops on a
# normal machine, so they run unconditionally.
#
#   1. /dev/fd missing -> `done < <(...)` process substitution fails inside
#      port-tool's native-module rebuild (Phase 2). Recreate the usual symlink.
#   2. `rm` / `rmdir` / `unlink` exported as shell functions pointing at a
#      safe-delete wrapper -> they shadow /usr/bin/rm inside nested bash and
#      leave the purge incomplete. The build therefore runs the toolchain under
#      `env -i` with a PATH that contains only real system directories.
prepare_environment() {
    [ -e /dev/fd ] || die "/dev/fd is unavailable; refusing to modify /dev during a user build"
    if ! bash -c 'while IFS= read -r _l; do :; done < <(printf "x\n")' 2>/dev/null; then
        die "process substitution is broken; the native-module rebuild will fail"
    fi
}

# A sanitised PATH: system directories plus the chosen Node. Deliberately
# excludes anything that could carry shimmed coreutils.
clean_path() {
    echo "$NODE_BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}

# Repair a zero-length Linux Koffi placeholder from the exact npm release.
# The DMG contains Koffi 2.x sources and empty cross-platform placeholders.
repair_koffi_binary() {
    local app_dir="$1"
    local target="$app_dir/resources/app.asar.unpacked/node_modules/koffi/build/koffi/linux_x64/koffi.node"
    local pack_dir="$TMP_DIR/koffi-pack-$KOFFI_VERSION"
    local pack_log="$LOG_DIR/koffi-pack-$KOFFI_VERSION.log"
    local archive="$KOFFI_TARBALL"
    local staged="$TMP_DIR/koffi-linux-x64.node"
    local actual_sri

    if [ -f "$target" ] && file "$target" | grep -q 'ELF 64-bit LSB shared object, x86-64'; then
        info "Koffi Linux x64 module already contains an ELF binary"
        return 0
    fi

    mkdir -p "$(dirname "$target")" "$(dirname "$archive")"
    if [ ! -f "$archive" ]; then
        /usr/bin/rm -rf "$pack_dir"
        mkdir -p "$pack_dir"
        info "fetching Koffi $KOFFI_VERSION from the npm registry"
        env -i HOME="$HOME" PATH="$(clean_path)" \
            npm_config_cache="$NPM_CACHE" \
            npm_config_registry=https://registry.npmjs.org \
            "$NODE_BIN_DIR/npm" pack "koffi@$KOFFI_VERSION" \
            --pack-destination "$pack_dir" >"$pack_log" 2>&1 || {
            tail -30 "$pack_log" >&2
            die "Koffi npm package fetch failed; full log at $pack_log"
        }
        [ -f "$pack_dir/koffi-$KOFFI_VERSION.tgz" ] || die "npm pack did not produce Koffi $KOFFI_VERSION tarball"
        install -m 0644 "$pack_dir/koffi-$KOFFI_VERSION.tgz" "$archive"
    fi

    actual_sri="sha512-$(openssl dgst -sha512 -binary "$archive" | base64 -w0)"
    [ "$actual_sri" = "$KOFFI_SHA512" ] || die "Koffi npm tarball integrity mismatch (expected official SRI $KOFFI_SHA512, got $actual_sri)"
    tar -xOf "$archive" package/build/koffi/linux_x64/koffi.node > "$staged" || die "Koffi npm tarball has no Linux x64 module"
    file "$staged" | grep -q 'ELF 64-bit LSB shared object, x86-64' || die "Koffi package did not provide an x86_64 Linux ELF module"
    install -m 0644 "$staged" "$target"
    info "restored Koffi $KOFFI_VERSION Linux x64 N-API module (registry SRI verified)"
}

# Electron 37 must use the active Secret Service backend for safeStorage.
# Kali has libsecret and gnome-keyring installed, but its launcher may not
# identify the desktop environment consistently under X11/Wayland sessions.
patch_credential_storage_launcher() {
    local launcher="$1/start.sh"
    python3 - "$launcher" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
flag = "  --password-store=gnome-libsecret \\\n"
if flag not in source:
    anchor = 'exec "$APP_DIR/electron" \\\n'
    if source.count(anchor) != 1:
        raise SystemExit(f"launcher anchor missing or ambiguous: {path}")
    source = source.replace(anchor, anchor + flag, 1)
    path.write_text(source)
PY
    bash -n "$launcher" || die "patched launcher has invalid shell syntax"
}

# ------------------------------------------------------------- inputs -------
# TMPDIR points at the work directory, not /tmp. On hosts where /tmp is a small
# tmpfs, dpkg-deb fails mid-compression with "zstd write error: No space left
# on device" even though the output partition has plenty of room.
fetch_inputs() {
    if [ ! -f "$DMG" ]; then
        info "downloading official DMG ($(basename "$DMG_URL"))"
        mkdir -p "$(dirname "$DMG")"
        curl -fL --progress-bar -o "$DMG.part" "$DMG_URL" || die "DMG download failed"
        mv "$DMG.part" "$DMG"
    fi
    local actual
    actual="$(sha256sum "$DMG" | cut -d' ' -f1)"
    [ "$actual" = "$DMG_SHA256" ] || die "DMG sha256 mismatch
  expected $DMG_SHA256
  actual   $actual
  For a newer release, supply PKG_VERSION, BUILD_ID and the official-feed DMG_SHA256."
    info "DMG verified (sha256 ok)"

    if [ ! -f "$ELECTRON_ZIP" ]; then
        info "downloading Linux Electron runtime v$ELECTRON_VERSION"
        mkdir -p "$(dirname "$ELECTRON_ZIP")"
        curl -fL -o "$ELECTRON_ZIP.part" "$ELECTRON_URL" || die "Electron download failed"
        mv "$ELECTRON_ZIP.part" "$ELECTRON_ZIP"
    fi
    actual="$(sha256sum "$ELECTRON_ZIP" | cut -d' ' -f1)"
    [ "$actual" = "$ELECTRON_ZIP_SHA256" ] || die "Electron runtime sha256 mismatch
  expected $ELECTRON_ZIP_SHA256
  actual   $actual"
    info "Electron runtime verified (sha256 ok)"
}

# ---------------------------------------------------------- stage 1: app ----
build_app() {
    local log
    log="$LOG_DIR/convert-$(date +%Y%m%d-%H%M%S).log"
    info "converting DMG to a Linux app (log: $log)"
    /usr/bin/rm -rf "$APP_DIR"
    rm -rf "${TMP_DIR:?}"/*

    env -i \
        HOME="$HOME" \
        PATH="$(clean_path)" \
        LANG=C.UTF-8 \
        LC_ALL=C.UTF-8 \
        TMPDIR="$TMP_DIR" \
        npm_config_cache="$NPM_CACHE" \
        npm_config_registry=https://registry.npmmirror.com \
        ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ \
        WORKBUDDY_INSTALL_DIR="$APP_DIR" \
        WORKBUDDY_APP_ID="$PACKAGE_NAME" \
        WORKBUDDY_APP_DISPLAY_NAME="WorkBuddy AI (International)" \
        WORKBUDDY_ELECTRON_ZIP="$ELECTRON_ZIP" \
        bash "$PORT_TOOL/install.sh" "$DMG" >"$log" 2>&1 || {
        tail -30 "$log" >&2
        die "conversion failed; full log at $log"
    }

    repair_koffi_binary "$APP_DIR"
    [ -x "$APP_DIR/start.sh" ] || die "no start.sh produced"
    patch_credential_storage_launcher "$APP_DIR"
    [ -x "$APP_DIR/electron" ] || die "no electron runtime produced"
    [ -f "$APP_DIR/resources/app.asar" ] || die "no app.asar produced"
    [ -f "$APP_DIR/resources/app.asar.unpacked/cli/product.json" ] || \
        die "cli/product.json missing from the unpacked payload"
    info "Linux app ready: $APP_DIR ($(du -sh "$APP_DIR" | cut -f1))"
}

# --------------------------------------------------------- stage 2: .deb ----
build_deb() {
    [ -d "$APP_DIR" ] || die "no app directory; run without --deb-only first"
    repair_koffi_binary "$APP_DIR"

    # port-tool writes the icon as .workbuddy-linux/workbuddy.png; fall back to
    # the icon inside the unpacked payload if that is absent.
    local icon="" candidate
    for candidate in \
        "$APP_DIR/.workbuddy-linux/workbuddy.png" \
        "$APP_DIR/.workbuddy-linux/$PACKAGE_NAME.png" \
        "$APP_DIR/resources/app.asar.unpacked/resources/icon.png"
    do
        [ -f "$candidate" ] && { icon="$candidate"; break; }
    done
    [ -n "$icon" ] || die "no icon found for the desktop entry"

    local log
    log="$LOG_DIR/deb-$(date +%Y%m%d-%H%M%S).log"
    info "building .deb (log: $log)"

    env -i \
        HOME="$HOME" \
        PATH="$(clean_path)" \
        LANG=C.UTF-8 \
        LC_ALL=C.UTF-8 \
        TMPDIR="$TMP_DIR" \
        APP_DIR_OVERRIDE="$APP_DIR" \
        PKG_ROOT_OVERRIDE="$PKG_ROOT_OVERRIDE" \
        DIST_DIR_OVERRIDE="$DIST_DIR_OVERRIDE" \
        PACKAGE_ICON_SOURCE="$icon" \
        PACKAGE_NAME="$PACKAGE_NAME" \
        PACKAGE_DISPLAY_NAME="WorkBuddy AI" \
        PACKAGE_VERSION="$PKG_VERSION" \
        PACKAGE_WITH_UPDATER=0 \
        bash "$DEB_TOOL/scripts/build-deb.sh" >"$log" 2>&1 || {
        tail -30 "$log" >&2
        die "deb build failed; full log at $log"
    }

    local deb
    deb="$(find "$DIST_DIR_OVERRIDE" -maxdepth 1 -name "${PACKAGE_NAME}_*.deb" | sort -V | tail -1)"
    [ -n "$deb" ] || die "no .deb produced"

    info "package ready: $deb ($(du -h "$deb" | cut -f1))"
    echo "$deb"
}

# ------------------------------------------------------------------ main ----
ensure_upstream
resolve_node_bin_dir
prepare_environment
fetch_inputs
[ "$DO_APP" -eq 1 ] && build_app
if [ "$DO_DEB" -eq 1 ]; then
    build_deb
    info "install with:  sudo dpkg -i <path-to-deb>"
    info "or rootless:   ./install-user.sh"
fi
info "done"
