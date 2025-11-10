#!/usr/bin/env bash
##################################################
# 44Net WireGuard Setup          ▌ ▌▌ ▌▙ ▌   ▐   #
# Author: /gregoryfenton         ▚▄▌▚▄▌▌▌▌▞▀▖▜▀  #
# Wiki: https://44net.wiki         ▌  ▌▌▝▌▛▀ ▐ ▖ #
# Portal: https://portal.44net.org ▘  ▘▘ ▘▝▀▘ ▀  #
# Discussion: https://ardc.groups.io/g/44net     #
# GitHub: https://github.com/gregoryfenton       #
##################################################

set -euo pipefail

# Timestamp for the run (used in logs, messages)
RUN_TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"

########################################
# DEFAULT PARAMETERS (can be overridden by INI)
########################################
# Network
LOCAL_HOSTNAME="myhost"
REMOTE_HOSTNAME="remotehost"
WG_LOCAL_IP="44.x.y.w/30"
WG_REMOTE_IP="44.x.y.z/32"
WG_REMOTE_INET=""                  # optional remote internet IP
WG_PORT=51820
LAN_SUBNET="192.168.1.0/24"
NET_44_0="44.0.0.0/9"
NET_44_128="44.128.0.0/10"

# Paths
WG_CONF="/etc/wireguard/wg0.conf"
IPTABLES_V4="/etc/iptables/rules.v4"
LOG_FILE="/var/log/44net-setup.log"
INI_FILE="/etc/44net-setup.ini"

# Keys
PRIVATE_KEY_FILE=""
PUBLIC_KEY_FILE=""
REMOTE_PUBLIC_KEY_FILE=""

# Options
COLOR=1
DRY_RUN=0

# Internal
WG_INTERFACE="wg0"

########################################
# Helper: Load INI file
# Usage: load_ini
# Parses key=value lines, overrides defaults
########################################
load_ini() {
    if [[ ! -f "$INI_FILE" ]]; then
        return
    fi
    while IFS='=' read -r key val; do
        key="$(echo "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        val="$(echo "${val:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
        [[ -z "$key" ]] && continue
        [[ "$key" =~ ^# ]] && continue
        case "$key" in
            LOCAL_HOSTNAME) LOCAL_HOSTNAME="$val";;
            REMOTE_HOSTNAME) REMOTE_HOSTNAME="$val";;
            WG_LOCAL_IP) WG_LOCAL_IP="$val";;
            WG_REMOTE_IP) WG_REMOTE_IP="$val";;
            WG_REMOTE_INET) WG_REMOTE_INET="$val";;
            WG_PORT) WG_PORT="$val";;
            LAN_SUBNET) LAN_SUBNET="$val";;
            NET_44_0) NET_44_0="$val";;
            NET_44_128) NET_44_128="$val";;
            WG_CONF) WG_CONF="$val";;
            IPTABLES_V4) IPTABLES_V4="$val";;
            LOG_FILE) LOG_FILE="$val";;
            INI_FILE) INI_FILE="$val";;
            PRIVATE_KEY_FILE) PRIVATE_KEY_FILE="$val";;
            PUBLIC_KEY_FILE) PUBLIC_KEY_FILE="$val";;
            REMOTE_PUBLIC_KEY_FILE) REMOTE_PUBLIC_KEY_FILE="$val";;
            COLOR) COLOR="$val";;
            DRY_RUN) DRY_RUN="$val";;
        esac
    done < <(sed -e 's/[[:space:]]*=[[:space:]]*/=/' -e 's/\r$//' "$INI_FILE")
}

########################################
# Helper: timestamp
# Usage: timestamp
# Returns YYYY-MM-DD HH:MM:SS
########################################
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

########################################
# Helper: colour_echo
# Usage: colour_echo <level> <message>
# Levels: normal, notice, debug, alert, critical
# Sends to screen with optional ANSI colors, logs to file
########################################
colour_echo() {
    local level="$1"; shift
    local msg="$*"
    local color_code=""
    if [[ "$COLOR" -eq 1 ]]; then
        case "$level" in
            normal) color_code="\e[0m";;
            notice) color_code="\e[34m";;
            debug) color_code="\e[36m";;
            alert) color_code="\e[33;1m";;
            critical) color_code="\e[41;37;1m";;
            *) color_code="\e[0m";;
        esac
        echo -e "${color_code}[$(timestamp)] $msg\e[0m"
    else
        echo "[$(timestamp)] $msg"
    fi
    # Log without color
    printf "[%s] %s\n" "$(timestamp)" "$msg" >>"$LOG_FILE" 2>/dev/null || true
}

########################################
# Helper: run_or_echo
# Usage: run_or_echo <command>
# Executes command unless DRY_RUN=1
########################################
run_or_echo() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        colour_echo notice "[DRY_RUN] $*"
    else
        colour_echo debug "EXEC: $*"
        eval "$*"
    fi
}

########################################
# Helper: read_key_or_file
# Usage: read_key_or_file <key_or_path>
# Returns key string (reads first line if file)
########################################
read_key_or_file() {
    local input="$1"
    if [[ -z "$input" ]]; then
        echo ""
        return
    fi
    if [[ -f "$input" ]]; then
        sed -n '1p' "$input" | tr -d '\r\n'
    else
        if [[ "$input" =~ ^[A-Za-z0-9+/=]+$ ]]; then
            echo "$input"
        else
            colour_echo critical "Invalid key or file path: $input"
            exit 1
        fi
    fi
}

########################################
# Helper: validate_ip
# Usage: validate_ip <ip>
# Returns 0 if valid IPv4, 1 if invalid
########################################
validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[12][0-9]|3[0-2]))?$ ]]; then
        return 0
    else
        return 1
    fi
}

########################################
# Dependency check
# Usage: check_required_cmds
# Ensures required programs are installed
########################################
check_required_cmds() {
    local missing=()
    declare -A PKG_MAP=( ["wg"]="wireguard" ["iptables"]="iptables" ["ip"]="iproute2" ["grep"]="grep" ["awk"]="awk" ["sed"]="sed" ["ping"]="iputils-ping" ["systemctl"]="systemd" )
    for cmd in wg iptables ip grep awk sed ping systemctl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("${PKG_MAP[$cmd]:-$cmd}")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        colour_echo alert "Required programs missing: ${missing[*]}"
        echo "Install with:"
        if command -v nala >/dev/null 2>&1; then
            echo "  sudo nala install ${missing[*]}"
        else
            echo "  sudo apt-get update && sudo apt-get install ${missing[*]}"
        fi
        exit 1
    fi
}
########################################
# Write WireGuard config
# Usage: write_wg_conf
# Creates /etc/wireguard/wg0.conf from keys and params
########################################
write_wg_conf() {
    colour_echo notice "Generating WireGuard config at $WG_CONF"

    local priv_key
    priv_key="$(read_key_or_file "$PRIVATE_KEY_FILE")"
    if [[ -z "$priv_key" ]]; then
        colour_echo notice "No private key provided, generating ephemeral key"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            priv_key="__DRY_RUN_PRIVATE_KEY__"
            colour_echo notice "[DRY_RUN] wg genkey"
        else
            priv_key="$(wg genkey)"
        fi
    fi

    local pub_key
    if [[ -n "$PUBLIC_KEY_FILE" ]]; then
        pub_key="$(read_key_or_file "$PUBLIC_KEY_FILE")"
    else
        if [[ "$DRY_RUN" -eq 1 ]]; then
            pub_key="__DRY_RUN_PUBLIC_KEY__"
        else
            pub_key="$(printf '%s' "$priv_key" | wg pubkey)"
        fi
    fi

    local remote_pub
    remote_pub="$(read_key_or_file "$REMOTE_PUBLIC_KEY_FILE")"

    local cfg="[Interface]
Address = ${WG_LOCAL_IP}
ListenPort = ${WG_PORT}
PrivateKey = ${priv_key}

[Peer]
PublicKey = ${remote_pub}
AllowedIPs = ${WG_REMOTE_IP}
"

    [[ -n "$WG_REMOTE_INET" ]] && cfg+="Endpoint = ${WG_REMOTE_INET}:${WG_PORT}"$'\n'

    if [[ "$DRY_RUN" -eq 1 ]]; then
        colour_echo notice "[DRY_RUN] Would write WireGuard config to $WG_CONF:"
        printf '%s\n' "$cfg"
    else
        umask 077
        mkdir -p "$(dirname "$WG_CONF")"
        printf '%s\n' "$cfg" >"$WG_CONF"
        chmod 600 "$WG_CONF"
        colour_echo notice "WireGuard config written to $WG_CONF"
    fi
}

########################################
# Add IP routes
# Usage: add_routes
# Adds 44Net CIDRs and peer IP to WG interface
########################################
add_routes() {
    local routes=( "$NET_44_0" "$NET_44_128" "${WG_REMOTE_IP}" )
    for r in "${routes[@]}"; do
        [[ -z "$r" ]] && continue
        if ip route show | grep -qw "$r"; then
            colour_echo notice "Route $r already exists"
            continue
        fi
        colour_echo notice "Adding route $r via $WG_INTERFACE"
        run_or_echo "ip route add $r dev $WG_INTERFACE"
    done
}

########################################
# Add iptables MASQUERADE rules
# Usage: add_iptables_rules
########################################
add_iptables_rules() {
    local rules=(
        "POSTROUTING -s $LAN_SUBNET -o $WG_INTERFACE -d $NET_44_0 -j MASQUERADE"
        "POSTROUTING -s $LAN_SUBNET -o $WG_INTERFACE -d $NET_44_128 -j MASQUERADE"
    )
    for r in "${rules[@]}"; do
        if iptables -t nat -S 2>/dev/null | grep -Fq "$r"; then
            colour_echo notice "iptables rule exists: $r"
        else
            colour_echo notice "Adding iptables rule: $r"
            run_or_echo "iptables -t nat -A ${r#POSTROUTING }"
        fi
    done

    # Persist if IPTABLES_V4 exists
    if [[ -n "$IPTABLES_V4" && -d "$(dirname "$IPTABLES_V4")" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            colour_echo notice "[DRY_RUN] Would save iptables to $IPTABLES_V4"
        else
            iptables-save > "$IPTABLES_V4" || colour_echo alert "Failed to save $IPTABLES_V4"
            colour_echo notice "Saved iptables to $IPTABLES_V4"
        fi
    fi
}

########################################
# Enable wg-quick service
# Usage: enable_wg_service
########################################
enable_wg_service() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        colour_echo notice "[DRY_RUN] Would enable/start wg-quick@$WG_INTERFACE.service"
    else
        run_or_echo "systemctl daemon-reload"
        run_or_echo "systemctl enable --now wg-quick@$WG_INTERFACE.service"
        sleep 1
        if systemctl is-active --quiet wg-quick@"$WG_INTERFACE".service; then
            colour_echo notice "Service wg-quick@$WG_INTERFACE is active"
        else
            colour_echo alert "Service failed to start"
        fi
    fi
}

########################################
# Disable wg-quick service
# Usage: disable_wg_service
########################################
disable_wg_service() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        colour_echo notice "[DRY_RUN] Would stop/disable wg-quick@$WG_INTERFACE.service"
    else
        run_or_echo "systemctl stop wg-quick@$WG_INTERFACE.service || true"
        run_or_echo "systemctl disable wg-quick@$WG_INTERFACE.service || true"
    fi
}

########################################
# CLEAN
# Usage: clean
# Removes wg config, routes, iptables, disables service
########################################
clean() {
    colour_echo notice "Cleaning 44Net configuration..."
    disable_wg_service

    if [[ -f "$WG_CONF" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            colour_echo notice "[DRY_RUN] Would remove $WG_CONF"
        else
            rm -f "$WG_CONF"
            colour_echo notice "Removed $WG_CONF"
        fi
    fi

    local routes=( "$NET_44_0" "$NET_44_128" "${WG_REMOTE_IP}" )
    for r in "${routes[@]}"; do
        [[ -z "$r" ]] && continue
        while ip route show | grep -qw "$r"; do
            colour_echo notice "Deleting route $r"
            run_or_echo "ip route del $r" || break
            sleep 0.2
        done
    done

    local patterns=(
        "-s $LAN_SUBNET -o $WG_INTERFACE -d $NET_44_0 -j MASQUERADE"
        "-s $LAN_SUBNET -o $WG_INTERFACE -d $NET_44_128 -j MASQUERADE"
    )
    for pat in "${patterns[@]}"; do
        while iptables -t nat -S 2>/dev/null | grep -Fq "POSTROUTING $pat"; do
            colour_echo notice "Deleting iptables rule: POSTROUTING $pat"
            run_or_echo "iptables -t nat -D POSTROUTING $pat" || break
            sleep 0.2
        done
    done

    colour_echo notice "CLEAN completed"
}
########################################
# Interactive menu
# Usage: interactive_menu
# Provides a TUI to select actions instead of CLI args
########################################
interactive_menu() {
    while true; do
        echo
        colour_echo notice "44Net Setup Interactive Menu:"
        echo "1) Setup 44Net"
        echo "2) Clean 44Net"
        echo "3) Show current configuration"
        echo "4) Exit"
        read -rp "Enter choice [1-4]: " choice
        case "$choice" in
            1) 
                colour_echo notice "Running 44Net setup..."
                write_wg_conf
                enable_wg_service
                add_routes
                add_iptables_rules
                ;;
            2)
                colour_echo notice "Running CLEAN..."
                clean
                ;;
            3)
                colour_echo notice "Current configuration:"
                echo "WG Interface: $WG_INTERFACE"
                echo "WG Local IP: $WG_LOCAL_IP"
                echo "WG Remote IP: $WG_REMOTE_IP"
                echo "LAN Subnet: $LAN_SUBNET"
                echo "WireGuard config file: $WG_CONF"
                ;;
            4) colour_echo notice "Exiting interactive menu"; break ;;
            *) colour_echo alert "Invalid choice: $choice";;
        esac
    done
}

########################################
# Self-update
# Usage: self_update <url> [dest]
# Downloads latest version of script from GitHub or URL
########################################
self_update() {
    local url="${1:-https://raw.githubusercontent.com/gregoryfenton/44netautosetup/main/setup_44net.sh}"
    local dest="${2:-$SCRIPT_FILE}"
    colour_echo notice "Updating script from $url"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        colour_echo notice "[DRY_RUN] curl -o $dest $url"
    else
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL "$url" -o "$dest" || { colour_echo alert "Failed to download $url"; return 1; }
            chmod +x "$dest"
            colour_echo notice "Script updated to $dest"
        else
            colour_echo alert "curl not installed, cannot self-update"
            return 1
        fi
    fi
}

########################################
# Set color for a log level
# Usage: set_color <level> <color>
# Stores in INI and runtime array
########################################
declare -A COLOR_MAP
set_color() {
    local level="$1"
    local color="$2"
    COLOR_MAP["$level"]="$color"
    colour_echo notice "Setting color for $level to $color"
    # Write/update INI
    if [[ -f "$INI_FILE" ]]; then
        if grep -q "^COLOR_$level=" "$INI_FILE"; then
            sed -i "s/^COLOR_$level=.*/COLOR_$level=$color/" "$INI_FILE"
        else
            echo "COLOR_$level=$color" >>"$INI_FILE"
        fi
    else
        echo "COLOR_$level=$color" >"$INI_FILE"
    fi
}

########################################
# Load colors from INI
########################################
load_colors() {
    [[ -f "$INI_FILE" ]] || return
    while IFS='=' read -r key val; do
        key="$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ "$key" =~ ^COLOR_ ]] || continue
        local level="${key#COLOR_}"
        COLOR_MAP["$level"]="$val"
    done < "$INI_FILE"
}

########################################
# Generate INI template with comments
# Usage: generate_ini_template <file>
########################################
generate_ini_template() {
    local file="${1:-$INI_FILE}"
    cat >"$file" <<'EOF'
###########################################################
# 44Net WireGuard Setup INI Template
# Edit values below to override defaults
###########################################################

# NETWORK PARAMETERS
LOCAL_HOSTNAME=myhost      # This machine's hostname for identification
REMOTE_HOSTNAME=remotehost # Remote peer hostname
WG_LOCAL_IP=44.x.y.w/30    # Local tunnel IP (CIDR)
WG_REMOTE_IP=44.x.y.z/32   # Remote tunnel IP
WG_REMOTE_INET=             # Optional public IP of remote for Endpoint
WG_PORT=51820              # WireGuard listen port
LAN_SUBNET=192.168.1.0/24 # Local LAN subnet for NAT

# 44NET ROUTING
NET_44_0=44.0.0.0/9
NET_44_128=44.128.0.0/10

# FILE PATHS
WG_CONF=/etc/wireguard/wg0.conf
IPTABLES_V4=/etc/iptables/rules.v4
LOG_FILE=/var/log/44net-setup.log

# KEYS
PRIVATE_KEY_FILE=           # path to private key file or inline key
PUBLIC_KEY_FILE=            # path to public key file or inline key
REMOTE_PUBLIC_KEY_FILE=     # remote peer public key or path

# OPTIONS
COLOR=1                    # enable (1) or disable (0) color output
DRY_RUN=0                  # enable dry-run (1 = do not execute commands)

# COLORS - optional, specify colors per level, e.g. red, green, blue
# Example: COLOR_alert=red
# Valid color names depend on terminal (e.g., red, green, yellow, blue, magenta, cyan)
COLOR_normal=none
COLOR_notice=blue
COLOR_debug=cyan
COLOR_alert=yellow
COLOR_critical=red
EOF
    colour_echo notice "INI template written to $file"
}
########################################
# CLI argument parsing
# Supports --clean, --dry-run, --no-color, --color, --help, --set-color/--set-colour
########################################
parse_cli_args() {
    CLEAN_MODE=0
    DRY_RUN="${DRY_RUN:-0}"
    COLOR="${COLOR:-1}"  # default to color enabled
    SET_COLOR_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --clean) CLEAN_MODE=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --no-color) COLOR=0; shift ;;
            --color) COLOR=1; shift ;;
            --set-color|--set-colour)
                if [[ -n "$2" && -n "$3" ]]; then
                    SET_COLOR_ARGS+=("$2:$3")
                    shift 3
                else
                    colour_echo alert "$1 requires two arguments: level and color"; exit 2
                fi
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --interactive|-i)
                INTERACTIVE_MENU=1
                shift
                ;;
            *) colour_echo alert "Unknown argument: $1"; usage; exit 2 ;;
        esac
    done
}

########################################
# Apply any --set-color arguments to runtime and INI
########################################
apply_set_color_args() {
    for arg in "${SET_COLOR_ARGS[@]:-}"; do
        local lvl="${arg%%:*}"
        local col="${arg##*:}"
        set_color "$lvl" "$col"
    done
}

########################################
# Load colors into global map before any output
########################################
initialize_colors() {
    load_colors
    # Override COLOR variable
    [[ "$COLOR" -eq 1 ]] || return
    # Populate colour_echo mappings from COLOR_MAP
    # Note: ANSI escape codes mapping
    declare -gA COLOR_ANSI
    for lvl in "${!COLOR_MAP[@]}"; do
        case "${COLOR_MAP[$lvl]}" in
            red) COLOR_ANSI[$lvl]="\e[31m" ;;
            green) COLOR_ANSI[$lvl]="\e[32m" ;;
            yellow) COLOR_ANSI[$lvl]="\e[33m" ;;
            blue) COLOR_ANSI[$lvl]="\e[34m" ;;
            magenta) COLOR_ANSI[$lvl]="\e[35m" ;;
            cyan) COLOR_ANSI[$lvl]="\e[36m" ;;
            white) COLOR_ANSI[$lvl]="\e[37m" ;;
            none|*) COLOR_ANSI[$lvl]="\e[0m" ;;
        esac
    done
}

########################################
# Wrap previous colour_echo to use dynamic color codes
########################################
colour_echo() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(timestamp)"
    if [[ "${COLOR:-0}" -eq 0 ]]; then
        echo "[$ts] $msg"
    else
        local code="${COLOR_ANSI[$level]:-$'\e[0m'}"
        echo -e "${code}[$ts] $msg\e[0m"
    fi
    # Log to file without color codes
    printf "[%s] %s\n" "$ts" "$msg" >>"$LOG_FILE" 2>/dev/null || true
}

########################################
# MAIN ENTRY
########################################
main() {
    parse_cli_args "$@"
    initialize_colors
    apply_set_color_args

    # ensure logfile exists
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        colour_echo notice "[DRY_RUN] Logging to $LOG_FILE"
    else
        mkdir -p "$(dirname "$LOG_FILE")" || true
        touch "$LOG_FILE" || true
    fi

    print_banner

    if [[ "$CLEAN_MODE" -eq 1 ]]; then
        colour_echo notice "Running in CLEAN mode..."
        check_required_cmds || true
        clean
        colour_echo notice "CLEAN completed. Exiting."
        exit 0
    fi

    if [[ "${INTERACTIVE_MENU:-0}" -eq 1 ]]; then
        interactive_menu
        exit 0
    fi

    # Normal setup sequence
    colour_echo notice "Starting 44Net setup..."
    check_required_cmds

    # Validate mandatory variables
    if [[ -z "$LAN_SUBNET" || -z "$WG_LOCAL_IP" || -z "$WG_REMOTE_IP" ]]; then
        colour_echo critical "LAN_SUBNET, WG_LOCAL_IP, and WG_REMOTE_IP must be set (script/env/INI)"
        exit 1
    fi

    # WireGuard config and service
    write_wg_conf
    enable_wg_service

    sleep 1
    if ip link show "$WG_INTERFACE" >/dev/null 2>&1; then
        colour_echo notice "Interface $WG_INTERFACE is present."
    else
        colour_echo alert "Interface $WG_INTERFACE not detected after starting wg-quick."
    fi

    add_routes
    add_iptables_rules

    colour_echo notice "Setup complete."

    # Ping verification
    if [[ "${DRY_RUN:-0}" -eq 0 && -n "$WG_REMOTE_IP" ]]; then
        peer_ip="${WG_REMOTE_IP%%/*}"
        if [[ -n "$peer_ip" ]]; then
            colour_echo notice "Pinging WireGuard peer $peer_ip (1 ICMP)..."
            if ping -c 1 -w 2 "$peer_ip" >/dev/null 2>&1; then
                colour_echo notice "Ping to $peer_ip succeeded."
            else
                colour_echo alert "Ping to $peer_ip failed. This may be normal depending on remote firewall."
            fi
        fi
    fi
}

# Invoke main with all CLI args
main "$@"
