#!/bin/bash
set -euo pipefail

########################################
# BANNER PARSING (top of file)
########################################
BANNER_START="#--banner start"
BANNER_END="#--banner end"
SCRIPT_FILE="${BASH_SOURCE[0]}"
BANNER_CONTENT=""
READ_BANNER=0
while IFS= read -r line; do
    [[ "$line" == "$BANNER_START" ]] && READ_BANNER=1 && continue
    [[ "$line" == "$BANNER_END" ]] && READ_BANNER=0 && break
    [[ $READ_BANNER -eq 1 ]] && BANNER_CONTENT+="$line"$'\n'
done < "$SCRIPT_FILE"

########################################
# DEFAULT PARAMETERS (can be overridden by INI file)
########################################
# WireGuard local/remote addresses
LOCAL_HOSTNAME="myhost"
REMOTE_HOSTNAME="remotehost"
WG_LOCAL_IP="44.x.y.w/30"
WG_REMOTE_IP="44.x.y.z/32"
WG_REMOTE_INET=""
WG_PORT=51820
LAN_SUBNET="192.168.1.0/24"

# 44Net ranges
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

# Optional
COLOR=0
DRY_RUN=0

########################################
# UTILITY FUNCTIONS
########################################
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

colour_echo() {
    local level="$1"
    local msg="$2"
    local color_code=""
    [[ $COLOR -eq 0 ]] && echo "[$(timestamp)] $msg" && return
    case "$level" in
        normal) color_code="\e[0m";;
        notice) color_code="\e[34m";;
        debug) color_code="\e[36m";;
        alert) color_code="\e[33;1m";;
        critical) color_code="\e[41;37;1m";;
        *) color_code="\e[0m";;
    esac
    echo -e "${color_code}[$(timestamp)] $msg\e[0m"
}

run_or_echo() {
    if [[ $DRY_RUN -eq 1 ]]; then
        colour_echo notice "[DRY_RUN] $*"
    else
        eval "$@"
    fi
}

read_key_or_file() {
    local input="$1"
    if [[ -f "$input" ]]; then
        cat "$input"
    elif [[ "$input" =~ ^[A-Za-z0-9+/=]+$ ]]; then
        echo "$input"
    else
        colour_echo critical "Invalid key/file: $input"
        exit 1
    fi
}

check_required_cmds() {
    local missing=()
    declare -A PKG_MAP=( ["wg"]="wireguard" ["iptables"]="iptables" ["ip"]="iproute2" ["grep"]="grep" ["awk"]="awk" ["sed"]="sed" ["ping"]="iputils-ping" )
    for cmd in wg iptables ip grep awk sed ping; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("${PKG_MAP[$cmd]:-$cmd}")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        colour_echo alert "Required programs missing: ${missing[*]}"
        echo "Install with:"
        if command -v nala &>/dev/null; then
            echo "nala install ${missing[*]}"
        else
            echo "apt-get install ${missing[*]}"
        fi
        exit 1
    fi
}

duplicate_rule_check() {
    local rule="$1"
    local table="${2:-nat}"
    local line
    line="$(iptables -t "$table" -S | grep -F "$rule" || true)"
    local count
    count=$(echo "$line" | wc -l)
    if [[ "$count" -gt 1 ]]; then
        local firstline
        firstline="${line%%$'\n'*}"
        colour_echo alert "Duplicate iptables rule found for ${firstline} ($count times)"
    fi
}

########################################
# CLEAN FUNCTION
########################################
clean() {
    colour_echo notice "Cleaning 44Net configuration..."
    # stop service
    systemctl stop wg-quick@wg0.service || true
    systemctl disable wg-quick@wg0.service || true
    # remove wg config
    [[ -f "$WG_CONF" ]] && rm -f "$WG_CONF"
    # remove routes iteratively
    for r in "$NET_44_0" "$NET_44_128" "$WG_REMOTE_IP"; do
        while ip route show | grep -q "$r"; do
            run_or_echo "ip route del $r"
        done
    done
    # remove iptables rules iteratively
    for r in "POSTROUTING -s $LAN_SUBNET -o wg0 -d $NET_44_0 -j MASQUERADE" "POSTROUTING -s $LAN_SUBNET -o wg0 -d $NET_44_128 -j MASQUERADE"; do
        while iptables -t nat -S | grep -Fq "$r"; do
            run_or_echo "iptables -t nat -D ${r#POSTROUTING }"
        done
    done
    colour_echo notice "Clean completed successfully."
}

########################################
# MAIN EXECUTION
########################################
print_banner() { echo -e "$BANNER_CONTENT"; }
print_banner

check_required_cmds

colour_echo notice "Running 44Net setup script..."
# further implementation of key generation, wg config, routes, iptables, logging, DRY_RUN, etc.
# ...

logfile="$LOG_FILE"
run_or_echo "touch $logfile"
colour_echo notice "Logging to $logfile"

colour_echo notice "Setup complete."
