#!/usr/bin/env python3
"""Prepare a NEW candidate build.sh for No1Hoo/workbuddy-ai-linux.

Inputs are a locally acquired official international Intel DMG and a matching
Linux Electron runtime ZIP. This is a build-config preparer, not a tested port.
It does not install, run, delete, or replace any application.
"""
import argparse
import hashlib
import re
import sys
from pathlib import Path


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, required=True, help='A working copy of No1Hoo/workbuddy-ai-linux')
    p.add_argument('--base-script', default='build.sh', help='Existing stable build driver to use as a template')
    p.add_argument('--output', type=Path, help='Candidate script path (default: <repo>/build-latest-candidate.sh)')
    p.add_argument('--dmg', type=Path, required=True, help='Official workbuddy.ai darwin-x64 DMG')
    p.add_argument('--dmg-sha256', help='Expected DMG SHA256 from the official update feed')
    p.add_argument('--electron-version', required=True, help='Electron version confirmed from the new DMG')
    p.add_argument('--electron-zip', type=Path, required=True, help='Matching Linux Electron runtime ZIP')
    p.add_argument('--electron-sha256', help='Expected Electron ZIP SHA256 from Electron SHASUMS256.txt')
    p.add_argument('--koffi-version', required=True, help='Koffi version found in the DMG package metadata')
    p.add_argument('--koffi-sha512', required=True, help='npm registry SRI for koffi@VERSION')
    args = p.parse_args()

    repo = args.repo.expanduser().resolve()
    dmg = args.dmg.expanduser().resolve()
    runtime = args.electron_zip.expanduser().resolve()
    original = (repo / args.base_script).resolve()
    output = (args.output or Path('build-latest-candidate.sh')).expanduser()
    if not output.is_absolute():
        output = repo / output
    output = output.resolve()
    if not original.is_file():
        p.error(f'base script does not exist: {original}')
    if not dmg.is_file() or not runtime.is_file():
        p.error('DMG or Electron ZIP does not exist')
    m = re.fullmatch(r'WorkBuddy-darwin-x64-(\d+(?:\.\d+){3})-([0-9a-fA-F]{8})\.dmg', dmg.name)
    if not m:
        p.error('DMG filename does not match official WorkBuddy-darwin-x64-VERSION-BUILD.dmg convention')
    ver, bid = m.groups()
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:\.\d+)?', args.electron_version):
        p.error('Invalid Electron version')
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', args.koffi_version):
        p.error('Invalid Koffi version')
    if not re.fullmatch(r'sha512-[A-Za-z0-9+/]{86}==?', args.koffi_sha512):
        p.error('Invalid Koffi npm SHA512 integrity value')
    expected_zip = f'electron-v{args.electron_version}-linux-x64.zip'
    if runtime.name != expected_zip:
        p.error(f'Electron ZIP filename should be {expected_zip}')
    if output == original:
        p.error('candidate output must not overwrite its base build script')
    if output.exists():
        p.error(f'Refusing to overwrite existing {output}')

    text = original.read_text(encoding='utf-8')
    candidate_command = f'./{output.name}'
    text = re.sub(r'(?m)^#   \./build\.sh(?=\s)', f'#   {candidate_command}', text)
    text = text.replace('update DMG_SHA256 in build.sh.', 'supply the official-feed DMG_SHA256 when invoking this candidate script.')

    fd_repair = '''    if [ ! -e /dev/fd ] && [ -w /dev ]; then
        info "recreating /dev/fd"
        ln -sfn /proc/self/fd /dev/fd
    fi'''
    if text.count(fd_repair) != 1:
        p.error('Could not find the /dev/fd host workaround; inspect build.sh manually')
    text = text.replace(
        fd_repair,
        '    [ -e /dev/fd ] || die "/dev/fd is unavailable; refusing to modify /dev during a user build"',
        1,
    )

    dmg_sha = sha256(dmg)
    electron_sha = sha256(runtime)
    for label, expected, actual in (
        ('DMG', args.dmg_sha256, dmg_sha),
        ('Electron ZIP', args.electron_sha256, electron_sha),
    ):
        if expected:
            expected = expected.lower()
            if not re.fullmatch(r'[0-9a-f]{64}', expected):
                p.error(f'Invalid {label} SHA256')
            if expected != actual:
                p.error(f'{label} SHA256 mismatch: expected {expected}, got {actual}')

    # Keep each release's application tree, temp files, npm cache, logs and
    # Electron runtime independent. The stable build.sh remains untouched.
    old_paths = '''APP_DIR="$WORK_ROOT/app"\nTMP_DIR="$WORK_ROOT/.tmp"\nNPM_CACHE="$WORK_ROOT/.npmcache"\nLOG_DIR="$WORK_ROOT/logs"'''
    if text.count(old_paths) != 1:
        p.error('Expected the standard WORK_ROOT output path block exactly once; inspect build.sh manually')
    text = text.replace(old_paths, '', 1)
    path_block = '''# Isolate all mutable build state by release and build id.\nAPP_DIR="${APP_DIR:-$WORK_ROOT/artifacts/build/${PKG_VERSION}-${BUILD_ID}/app}"\nTMP_DIR="${TMP_DIR:-$WORK_ROOT/artifacts/build/${PKG_VERSION}-${BUILD_ID}/tmp}"\nNPM_CACHE="${NPM_CACHE:-$WORK_ROOT/artifacts/cache/npm/${PKG_VERSION}-${BUILD_ID}}"\nLOG_DIR="${LOG_DIR:-$WORK_ROOT/logs/${PKG_VERSION}-${BUILD_ID}}"'''
    package_marker = 'PACKAGE_NAME="workbuddy-ai"\n'
    if text.count(package_marker) != 1:
        p.error('Could not find the PACKAGE_NAME config marker')
    text = text.replace(package_marker, package_marker + '\n' + path_block + '\n', 1)

    koffi_config = f'''KOFFI_VERSION="${{KOFFI_VERSION:-{args.koffi_version}}}"
KOFFI_SHA512="${{KOFFI_SHA512:-{args.koffi_sha512}}}"
KOFFI_TARBALL="${{KOFFI_TARBALL:-$WORK_ROOT/artifacts/cache/npm-packages/koffi-${{KOFFI_VERSION}}.tgz}}"
PKG_ROOT_OVERRIDE="${{PKG_ROOT_OVERRIDE:-$WORK_ROOT/artifacts/package-root/${{PKG_VERSION}}-${{BUILD_ID}}}}"
DIST_DIR_OVERRIDE="${{DIST_DIR_OVERRIDE:-$WORK_ROOT/artifacts/packages}}"'''
    runtime_marker = 'ELECTRON_ZIP_SHA256="${ELECTRON_ZIP_SHA256:-'
    runtime_lines = [line for line in text.splitlines() if line.startswith(runtime_marker)]
    if len(runtime_lines) != 1:
        p.error('Could not find the Electron runtime checksum config line')
    text = text.replace(runtime_lines[0], runtime_lines[0] + '\n' + koffi_config, 1)

    native_repair = r'''# Repair a zero-length Linux Koffi placeholder from the exact npm release.
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
}'''
    clean_path_end = '    echo "$NODE_BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\n}'
    if text.count(clean_path_end) != 1:
        p.error('Could not find clean_path() end marker')
    text = text.replace(clean_path_end, clean_path_end + '\n\n' + native_repair, 1)

    before_app_check = '    [ -x "$APP_DIR/start.sh" ] || die "no start.sh produced"'
    if text.count(before_app_check) != 1:
        p.error('Could not find app validation marker')
    text = text.replace(before_app_check, '    repair_koffi_binary "$APP_DIR"\n' + before_app_check, 1)

    before_deb_check = '    [ -d "$APP_DIR" ] || die "no app directory; run without --deb-only first"'
    if text.count(before_deb_check) != 1:
        p.error('Could not find deb validation marker')
    text = text.replace(before_deb_check, before_deb_check + '\n    repair_koffi_binary "$APP_DIR"', 1)

    app_override_line = '        APP_DIR_OVERRIDE="$APP_DIR" \\\n'
    if text.count(app_override_line) != 1:
        p.error('Could not find the package build environment marker')
    text = text.replace(
        app_override_line,
        app_override_line + '        PKG_ROOT_OVERRIDE="$PKG_ROOT_OVERRIDE" \\\n        DIST_DIR_OVERRIDE="$DIST_DIR_OVERRIDE" \\\n',
        1,
    )

    old_deb_lookup = '    deb="$(find "$DEB_TOOL/dist" -maxdepth 1 -name "${PACKAGE_NAME}_*.deb" | sort -V | tail -1)"'
    if text.count(old_deb_lookup) != 1:
        p.error('Could not find the package output lookup; inspect build.sh manually')
    text = text.replace(
        old_deb_lookup,
        '    deb="$(find "$DIST_DIR_OVERRIDE" -maxdepth 1 -name "${PACKAGE_NAME}_*.deb" | sort -V | tail -1)"',
        1,
    )

    stale_dmg_comment = '''# sha256 of the DMG above, verified against both the upstream PKGBUILD and a
# live download. A mismatch aborts the build rather than silently producing a
# package from something unexpected.'''
    current_dmg_comment = '''# SHA256 from the official international update feed for this candidate.
# A mismatch aborts instead of silently building from different vendor bytes.'''
    if text.count(stale_dmg_comment) != 1:
        p.error('Could not find the DMG checksum comment; inspect build.sh manually')
    text = text.replace(stale_dmg_comment, current_dmg_comment, 1)

    patterns = [
        (r'(?m)^PKG_VERSION="\$\{PKG_VERSION:-[^\n\"]+\}"$', f'PKG_VERSION="${{PKG_VERSION:-{ver}}}"'),
        (r'(?m)^BUILD_ID="\$\{BUILD_ID:-[^\n\"]+\}"$', f'BUILD_ID="${{BUILD_ID:-{bid}}}"'),
        (r'(?m)^ELECTRON_VERSION="\$\{ELECTRON_VERSION:-[^\n\"]+\}"$', f'ELECTRON_VERSION="${{ELECTRON_VERSION:-{args.electron_version}}}"'),
        (r'(?m)^DMG_SHA256="[0-9a-f]{64}"$', f'DMG_SHA256="${{DMG_SHA256:-{dmg_sha}}}"'),
        (r'(?m)^ELECTRON_ZIP_SHA256="\$\{ELECTRON_ZIP_SHA256:-[0-9a-f]{64}\}"$', f'ELECTRON_ZIP_SHA256="${{ELECTRON_ZIP_SHA256:-{electron_sha}}}"'),
    ]
    for pattern, replacement in patterns:
        text, count = re.subn(pattern, lambda _m: replacement, text)
        if count != 1:
            p.error(f'Expected exactly one match for {pattern}; got {count}. Upstream build.sh changed; inspect manually.')
    # Do not reuse v5.5.2's generic cache file or Electron ZIP silently.
    # Keep the candidate portable: use a release-scoped input cache by default,
    # while still allowing DMG=/path/to/local.dmg at invocation time.
    pattern = r'(?m)^DMG="\$\{DMG:-[^\n]+\}"$'
    default_dmg = f'$WORK_ROOT/artifacts/input/WorkBuddy-darwin-x64-{ver}-{bid}.dmg'
    text, count = re.subn(pattern, lambda _m: 'DMG="${DMG:-' + default_dmg + '}"', text)
    if count != 1:
        p.error('Could not find the DMG cache line')
    pattern = r'(?m)^ELECTRON_ZIP="\$\{ELECTRON_ZIP:-[^\n]+\}"$'
    zip_default = '$WORK_ROOT/artifacts/cache/electron-v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip'
    text, count = re.subn(pattern, lambda _m: 'ELECTRON_ZIP="${ELECTRON_ZIP:-' + zip_default + '}"', text)
    if count != 1:
        p.error('Could not find the Electron ZIP cache line')
    output.write_text(text, encoding='utf-8')
    output.chmod(0o755)
    print('CANDIDATE PREPARED (not built or installed):', output)
    print('Version:', ver, 'Build:', bid, 'Electron:', args.electron_version)
    print('Koffi:', args.koffi_version, '(npm integrity pinned)')
    print('DMG SHA256:', dmg_sha)
    if args.dmg_sha256:
        print('DMG SHA256 matches official update feed')
    print('Electron ZIP SHA256:', electron_sha)
    if args.electron_sha256:
        print('Electron ZIP SHA256 matches official SHASUMS256.txt')
    print('Review with: diff -u', original, output)
    print('Then in that candidate workspace:', candidate_command, '--app-only')
    print('IMPORTANT: local SHA256 detects changes; it does not prove vendor authenticity.')
    print('IMPORTANT: inspect build logs, native module ABI, OAuth deep links and sandbox behavior before replacing the working 5.5.2 installation.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
