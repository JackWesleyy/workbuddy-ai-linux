#!/usr/bin/env bash
#
# Fetch the two upstream community toolchains at the exact commits this project
# was built and verified against, then apply our packaging patches on top.
#
# We deliberately do NOT vendor upstream code into this repository. Both
# upstream projects are MIT licensed and could legally be vendored, but keeping
# this repo as a thin, auditable layer means:
#
#   * no 1.3 GB of third-party build output in git history
#   * the provenance of every file stays obvious (upstream vs. ours)
#   * upstream fixes can be picked up by bumping the pinned commits below
#
# Layout produced:
#
#   upstream/port-tool/   LX2000WASD/workbuddy-international-linux  (DMG -> app)
#   upstream/deb-tool/    Xboxpig/workbuddy-desktop-linux           (app -> .deb)
#                         ^ our patches/deb-tool.patch applied in place
#
# Usage:
#   ./bootstrap.sh            fetch and patch
#   ./bootstrap.sh --force    re-fetch clean pinned checkouts (never deletes them)
#
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM="$ROOT/upstream"

# --------------------------------------------------------------- pinned ------
# Pinned commits, not branches. A branch would make builds non-reproducible the
# moment upstream force-pushes or rewrites history.
PORT_REPO="https://github.com/LX2000WASD/workbuddy-international-linux.git"
PORT_COMMIT="c2b731cf0fa566306c89697ef95c472d17525a93"

DEB_REPO="https://github.com/Xboxpig/workbuddy-desktop-linux.git"
DEB_COMMIT="66103bafff518ad17a64ca34dbdbee0d2085f4a3"

PATCH="$ROOT/patches/deb-tool.patch"
PORT_PATCH="$ROOT/patches/port-tool-sandbox.patch"
PORT_ASAR_PATCH="$ROOT/patches/port-tool-asar-grouped-unpack.patch"
PORT_NATIVE_PATCH="$ROOT/patches/port-tool-postpatch-native-purge.patch"
PORT_CREDENTIAL_PATCH="$ROOT/patches/port-tool-credential-bootstrap.patch"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

info() { echo "[bootstrap] $*" >&2; }
die()  { echo "[bootstrap] ERROR: $*" >&2; exit 1; }

for tool in git patch; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not installed"
done

# Fetch one repository at one exact commit. Existing worktrees are inspected
# before changing them. Dirty or unrelated directories are left untouched.
fetch_at_commit() {
    local dir="$1" repo="$2" commit="$3" name="$4"

    if [ -e "$dir" ]; then
        if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
            die "$name path exists but is not a Git worktree; preserving $dir"
        fi

        local actual origin
        actual="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
        if [ "$actual" = "$commit" ] && [ "$FORCE" -eq 0 ]; then
            info "$name already at ${commit:0:8}; preserving its worktree"
            return 0
        fi

        if [ -n "$(git -C "$dir" status --porcelain --untracked-files=all)" ]; then
            die "$name has local changes or untracked files; preserving it. Review $dir before retrying"
        fi
        origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
        if [ "$origin" != "$repo" ]; then
            die "$name origin does not match the pinned upstream; preserving $dir"
        fi
        info "$name is clean but not at the pinned commit; updating in place"
    else
        info "fetching $name @ ${commit:0:8}"
        mkdir -p "$dir"
        git -C "$dir" init -q
        git -C "$dir" remote add origin "$repo"
    fi

    # --depth 1 on an explicit SHA works on GitHub and avoids pulling history.
    if ! git -C "$dir" fetch -q --depth 1 origin "$commit" 2>/dev/null; then
        info "  shallow fetch of a bare SHA was refused; falling back to full fetch"
        git -C "$dir" fetch -q origin "$commit"
    fi
    git -C "$dir" -c advice.detachedHead=false checkout -q --detach "$commit" \
        || die "$name checkout failed; preserving current worktree at $dir"

    local actual
    actual="$(git -C "$dir" rev-parse HEAD)"
    [ "$actual" = "$commit" ] || die "$name landed on $actual, expected $commit"
    info "$name ready ($(git -C "$dir" rev-list --count HEAD 2>/dev/null || echo 1) commit(s))"
}

mkdir -p "$UPSTREAM"

fetch_at_commit "$UPSTREAM/port-tool" "$PORT_REPO" "$PORT_COMMIT" "port-tool"
fetch_at_commit "$UPSTREAM/deb-tool"  "$DEB_REPO"  "$DEB_COMMIT"  "deb-tool"

# ------------------------------------------------------------- patching ------
# The patch is idempotent: if it is already applied we say so instead of
# failing, so `bootstrap.sh` can be re-run safely at any time.
[ -f "$PATCH" ] || die "missing $PATCH"

if git -C "$UPSTREAM/deb-tool" apply --check "$PATCH" 2>/dev/null; then
    info "applying patches/deb-tool.patch"
    git -C "$UPSTREAM/deb-tool" apply "$PATCH"
    info "patch applied"
elif git -C "$UPSTREAM/deb-tool" apply --check --reverse "$PATCH" 2>/dev/null; then
    info "patches/deb-tool.patch already applied"
else
    die "patch does not apply cleanly and is not already applied.
  Upstream may have changed. Inspect:
    git -C upstream/deb-tool status
    git -C upstream/deb-tool apply --check -v patches/deb-tool.patch"
fi

[ -f "$PORT_ASAR_PATCH" ] || die "missing $PORT_ASAR_PATCH"
if git -C "$UPSTREAM/port-tool" apply --check "$PORT_ASAR_PATCH" 2>/dev/null; then
    info "applying patches/port-tool-asar-grouped-unpack.patch"
    git -C "$UPSTREAM/port-tool" apply "$PORT_ASAR_PATCH"
    info "ASAR compatibility patch applied"
elif git -C "$UPSTREAM/port-tool" apply --check --reverse "$PORT_ASAR_PATCH" 2>/dev/null; then
    info "patches/port-tool-asar-grouped-unpack.patch already applied"
else
    die "patch does not apply cleanly and is not already applied. Inspect:
  git -C upstream/port-tool status
  git -C upstream/port-tool apply --check -v patches/port-tool-asar-grouped-unpack.patch"
fi

# Keep Chromium's renderer and GPU sandbox enabled. The host kernel supports
# unprivileged user namespaces, so the generated launcher has no need to add
# Electron's --no-sandbox / --disable-gpu-sandbox escape hatches.
[ -f "$PORT_PATCH" ] || die "missing $PORT_PATCH"
if git -C "$UPSTREAM/port-tool" apply --check "$PORT_PATCH" 2>/dev/null; then
    info "applying patches/port-tool-sandbox.patch"
    git -C "$UPSTREAM/port-tool" apply "$PORT_PATCH"
    info "sandbox patch applied"
elif git -C "$UPSTREAM/port-tool" apply --check --reverse "$PORT_PATCH" 2>/dev/null; then
    info "patches/port-tool-sandbox.patch already applied"
else
    die "patch does not apply cleanly and is not already applied. Inspect:
  git -C upstream/port-tool status
  git -C upstream/port-tool apply --check -v patches/port-tool-sandbox.patch"
fi

[ -f "$PORT_NATIVE_PATCH" ] || die "missing $PORT_NATIVE_PATCH"
if git -C "$UPSTREAM/port-tool" apply --check "$PORT_NATIVE_PATCH" 2>/dev/null; then
    info "applying patches/port-tool-postpatch-native-purge.patch"
    git -C "$UPSTREAM/port-tool" apply "$PORT_NATIVE_PATCH"
    info "post-patch native audit applied"
elif git -C "$UPSTREAM/port-tool" apply --check --reverse "$PORT_NATIVE_PATCH" 2>/dev/null; then
    info "patches/port-tool-postpatch-native-purge.patch already applied"
else
    die "patch does not apply cleanly and is not already applied. Inspect:
  git -C upstream/port-tool status
  git -C upstream/port-tool apply --check -v patches/port-tool-postpatch-native-purge.patch"
fi

[ -f "$PORT_CREDENTIAL_PATCH" ] || die "missing $PORT_CREDENTIAL_PATCH"
if git -C "$UPSTREAM/port-tool" apply --check "$PORT_CREDENTIAL_PATCH" 2>/dev/null; then
    info "applying patches/port-tool-credential-bootstrap.patch"
    git -C "$UPSTREAM/port-tool" apply "$PORT_CREDENTIAL_PATCH"
    info "Linux credential bootstrap adapter applied"
elif git -C "$UPSTREAM/port-tool" apply --check --reverse "$PORT_CREDENTIAL_PATCH" 2>/dev/null; then
    info "patches/port-tool-credential-bootstrap.patch already applied"
else
    die "patch does not apply cleanly and is not already applied. Inspect:
  git -C upstream/port-tool status
  git -C upstream/port-tool apply --check -v patches/port-tool-credential-bootstrap.patch"
fi

# ------------------------------------------------------------- summary -------
echo >&2
info "upstream ready:"
echo "    port-tool  $(git -C "$UPSTREAM/port-tool" rev-parse --short HEAD)  LX2000WASD/workbuddy-international-linux" >&2
echo "    deb-tool   $(git -C "$UPSTREAM/deb-tool" rev-parse --short HEAD)  Xboxpig/workbuddy-desktop-linux (+ $(basename "$PATCH"))" >&2
echo >&2
info "next: ./build-latest-candidate.sh --app-only"
info "then: ./build-latest-candidate.sh --deb-only"
info "      ./install-user.sh  # install to ~/.local (no root needed)"
info "stable baseline: ./build.sh"
