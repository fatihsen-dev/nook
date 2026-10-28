#!/bin/sh
set -eu

APP_NAME="Nook"
RELEASES_URL="${NOOK_RELEASES_URL:-https://github.com/fatihsen-dev/nook/releases/latest/download}"
SYSTEM_APPLICATIONS_DIR="/Applications"
USER_APPLICATIONS_DIR="$HOME/Applications"
BIN_DIR="${NOOK_BIN_DIR:-$HOME/.local/bin}"
COMMAND_LINE_NAME="nookctl"
MINIMUM_MACOS_MAJOR=14

log() { printf '  %s\n' "$1"; }
err() { printf 'error: %s\n' "$1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "this installer needs '$1'"; }

find_install_dir() {
    if [ -n "${NOOK_INSTALL_DIR:-}" ]; then
        echo "$NOOK_INSTALL_DIR"
        return
    fi
    for directory in "$SYSTEM_APPLICATIONS_DIR" "$USER_APPLICATIONS_DIR"; do
        if [ -d "${directory}/${APP_NAME}.app" ]; then
            echo "$directory"
            return
        fi
    done
    echo "$USER_APPLICATIONS_DIR"
}

warn_about_other_copies() {
    for directory in "$SYSTEM_APPLICATIONS_DIR" "$USER_APPLICATIONS_DIR"; do
        [ "$directory" != "$INSTALL_DIR" ] || continue
        [ -d "${directory}/${APP_NAME}.app" ] || continue
        log "another copy is still in ${directory}; delete ${directory}/${APP_NAME}.app so Spotlight shows one Nook"
    done
}

main() {
    echo ""
    echo "  nook installer"
    echo ""

    [ "$(uname -s)" = "Darwin" ] || err "Nook runs on macOS only"
    macos_version="$(sw_vers -productVersion)"
    [ "${macos_version%%.*}" -ge "$MINIMUM_MACOS_MAJOR" ] || err "Nook needs macOS ${MINIMUM_MACOS_MAJOR} or later (found ${macos_version})"
    need curl
    need shasum
    need ditto

    INSTALL_DIR="$(find_install_dir)"
    if [ -d "$INSTALL_DIR" ] && [ ! -w "$INSTALL_DIR" ]; then
        err "cannot write to ${INSTALL_DIR}; delete ${INSTALL_DIR}/${APP_NAME}.app or set NOOK_INSTALL_DIR to another folder"
    fi

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    log "downloading ${APP_NAME}..."
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 300 "${RELEASES_URL}/${APP_NAME}.zip" -o "${tmp}/${APP_NAME}.zip" \
        || err "download failed from ${RELEASES_URL}/${APP_NAME}.zip"
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 "${RELEASES_URL}/${APP_NAME}.zip.sha256" -o "${tmp}/${APP_NAME}.zip.sha256" \
        || err "checksum download failed from ${RELEASES_URL}/${APP_NAME}.zip.sha256"

    expected="$(tr -d '[:space:]' < "${tmp}/${APP_NAME}.zip.sha256" | tr '[:upper:]' '[:lower:]')"
    actual="$(shasum -a 256 "${tmp}/${APP_NAME}.zip" | awk '{ print $1 }')"
    [ "${#expected}" -eq 64 ] || err "the release checksum is not a SHA-256 value"
    [ "$expected" = "$actual" ] || err "checksum mismatch: expected ${expected}, got ${actual}"
    log "checksum verified"

    ditto -x -k "${tmp}/${APP_NAME}.zip" "${tmp}/unpacked"
    [ -d "${tmp}/unpacked/${APP_NAME}.app" ] || err "the archive does not contain ${APP_NAME}.app"

    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        log "quitting the running ${APP_NAME}..."
        osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || pkill -x "$APP_NAME" || true
        sleep 1
    fi

    mkdir -p "$INSTALL_DIR"
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    mv "${tmp}/unpacked/${APP_NAME}.app" "${INSTALL_DIR}/${APP_NAME}.app"
    xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null || true
    log "installed ${INSTALL_DIR}/${APP_NAME}.app"
    warn_about_other_copies

    command_line_tool="${INSTALL_DIR}/${APP_NAME}.app/Contents/MacOS/${COMMAND_LINE_NAME}"
    if [ -x "$command_line_tool" ]; then
        mkdir -p "$BIN_DIR"
        ln -sf "$command_line_tool" "${BIN_DIR}/${COMMAND_LINE_NAME}"
        log "linked ${BIN_DIR}/${COMMAND_LINE_NAME}"
        case ":${PATH}:" in
            *":${BIN_DIR}:"*) ;;
            *) log "add ${BIN_DIR} to your PATH to run ${COMMAND_LINE_NAME}: echo 'export PATH=\"${BIN_DIR}:\$PATH\"' >> ~/.zshrc" ;;
        esac
    fi

    if ! xcrun --find swift >/dev/null 2>&1; then
        echo ""
        log "Nook builds nooklets with the Swift toolchain, which was not found."
        log "Install Xcode from the App Store, or run: xcode-select --install"
    fi

    echo ""
    log "open it from ${INSTALL_DIR} or run: open \"${INSTALL_DIR}/${APP_NAME}.app\""
    echo ""
}

main "$@"
