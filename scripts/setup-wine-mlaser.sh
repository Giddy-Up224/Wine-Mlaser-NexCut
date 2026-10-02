#!/bin/bash
set -euo pipefail

usage() {
	printf '%s\n' \
		"Usage: $0 APP_PATH [--cjk-fonts] [--network CONNECTION] [--address IP]" \
		"       $0 --revert-network CONNECTION" \
		"" \
		"APP_PATH can be the extracted application folder or its MainApp.exe file." \
		"Run as your normal desktop user. Network changes use sudo when needed." \
		"WINEPREFIX defaults to \$HOME/.wine-mlaser; it must be a 32-bit prefix." \
		"--network configures an existing dedicated laser connection (default IP: 10.1.1.100)." \
		"--revert-network restores DHCP on that connection without setting up Wine."
}

fail() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

APPDIR=""
CONNECTION=""
ADDRESS="10.1.1.100"
CJK_FONTS=false
REVERT_NETWORK=false
ADDRESS_SET=false
while (( $# )); do
	case "$1" in
		--help|-h) usage; exit 0 ;;
		--cjk-fonts) CJK_FONTS=true; shift ;;
		--network|--revert-network|--address)
			(( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail "$1 requires a value"
			case "$1" in
				--network) CONNECTION="$2" ;;
				--revert-network) CONNECTION="$2"; REVERT_NETWORK=true ;;
				--address) ADDRESS="$2"; ADDRESS_SET=true ;;
			esac
			shift 2
			;;
		-*) fail "Unknown option: $1 (see --help)" ;;
		*) [[ -z "$APPDIR" ]] || fail "Only one application directory may be supplied"
			 APPDIR="$1"; shift ;;
	esac
done

if "$REVERT_NETWORK"; then
	[[ -z "$APPDIR" ]] && ! "$CJK_FONTS" && ! "$ADDRESS_SET" || fail "Use --revert-network on its own"
else
	[[ -n "$APPDIR" ]] || { usage >&2; exit 1; }
	if [[ -f "$APPDIR" && "${APPDIR##*/}" = MainApp.exe ]]; then
		APPDIR="$(dirname -- "$APPDIR")"
	fi
	[[ -f "$APPDIR/MainApp.exe" ]] || fail "MainApp.exe not found at $APPDIR; provide the extracted application folder or its MainApp.exe file"
	(( EUID != 0 )) || fail "Run setup without sudo so Wine uses your desktop account"
	! "$ADDRESS_SET" || [[ -n "$CONNECTION" ]] || fail "--address requires --network"
	[[ "$ADDRESS" =~ ^10\.1\.1\.([0-9]{1,3})$ ]] || fail "Address must be in the laser's 10.1.1.0/24 subnet"
	HOST_NUMBER="${BASH_REMATCH[1]}"
	(( 10#$HOST_NUMBER >= 1 && 10#$HOST_NUMBER <= 254 )) || fail "Address must be a usable host address"
	case "$((10#$HOST_NUMBER))" in
		168|169|170) fail "That address is already assigned to a laser device" ;;
	esac
	for dependency in wine wineboot winepath winetricks; do
		command -v "$dependency" >/dev/null || fail "Missing $dependency. On Ubuntu/Mint, run: sudo dpkg --add-architecture i386; sudo apt update; sudo apt install wine wine32:i386 winetricks"
	done
	export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-mlaser}"
	[[ "$WINEPREFIX" = /* ]] || fail "WINEPREFIX must be an absolute path"
	[[ ! -f "$WINEPREFIX/system.reg" ]] || grep -q '^#arch=win32' "$WINEPREFIX/system.reg" || fail "Existing prefix is not win32; choose a new WINEPREFIX rather than deleting it"
	[[ ! -e "$WINEPREFIX/drive_c/Mlaser" || -L "$WINEPREFIX/drive_c/Mlaser" ]] || fail "C:/Mlaser already exists and is not a symlink; move it aside yourself or choose another prefix"
	APPDIR="$(readlink -f -- "$APPDIR")"
	export WINEARCH=win32
fi

if [[ -n "$CONNECTION" ]]; then
	command -v nmcli >/dev/null || fail "Network configuration requires NetworkManager (nmcli)"
	nmcli connection show "$CONNECTION" >/dev/null || fail "NetworkManager connection not found: $CONNECTION"
	(( EUID == 0 )) || command -v sudo >/dev/null || fail "Network changes require sudo"
fi

if ! "$REVERT_NETWORK"; then
	printf '==> Creating/checking 32-bit prefix at %s\n' "$WINEPREFIX"
	wineboot --init
	printf '==> Installing MFC 4.2\n'
	winetricks -q mfc42
	if "$CJK_FONTS"; then
		winetricks -q cjkfonts
	fi
	printf '==> Linking the app onto C: and creating Technology folders\n'
	ln -sfnT -- "$APPDIR" "$WINEPREFIX/drive_c/Mlaser"
	mkdir -p -- "$WINEPREFIX/drive_c/Technology/Fiber" "$WINEPREFIX/drive_c/Technology/CO2"
	WINDOWS_LOCAL_APPDATA="$(wine cmd /c 'echo %LOCALAPPDATA%')"
	WINDOWS_LOCAL_APPDATA="${WINDOWS_LOCAL_APPDATA//$'\r'/}"
	[[ -n "$WINDOWS_LOCAL_APPDATA" && "$WINDOWS_LOCAL_APPDATA" != '%LOCALAPPDATA%' ]] || fail "Wine did not provide LOCALAPPDATA"
	LOCAL_APPDATA="$(winepath -u "$WINDOWS_LOCAL_APPDATA")"
	[[ "$LOCAL_APPDATA" = /* ]] || fail "Wine returned an invalid Local AppData path"
	mkdir -p -- "$LOCAL_APPDATA/NexCut/Technology/Fiber" "$LOCAL_APPDATA/NexCut/Technology/CO2"
fi

network_command() {
	if (( EUID == 0 )); then
		nmcli "$@"
	else
		sudo nmcli "$@"
	fi
}

if [[ -n "$CONNECTION" ]]; then
	if "$REVERT_NETWORK"; then
		network_command connection modify "$CONNECTION" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.never-default no
	else
		network_command connection modify "$CONNECTION" ipv4.method manual ipv4.addresses "$ADDRESS/24" ipv4.gateway "" ipv4.never-default yes
	fi
	network_command connection up "$CONNECTION"
	if "$REVERT_NETWORK"; then
		printf 'Restored DHCP on %s.\n' "$CONNECTION"
	else
		printf 'Configured %s at %s/24 without a default gateway.\n' "$CONNECTION" "$ADDRESS"
		if command -v ping >/dev/null; then
			for endpoint in 10.1.1.168 10.1.1.169 10.1.1.170; do
				if ping -c1 -W1 "$endpoint" >/dev/null 2>&1; then
					printf '%s: reachable\n' "$endpoint"
				else
					printf '%s: no ping reply (not proof of a connection failure)\n' "$endpoint"
				fi
			done
		fi
	fi
fi

if ! "$REVERT_NETWORK"; then
	printf 'Setup complete. Launch with: WINEPREFIX=%q %q\n' "$WINEPREFIX" "$(dirname -- "$(readlink -f -- "$0")")/mlaser"
fi
