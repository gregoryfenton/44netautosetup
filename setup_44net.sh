#!/bin/bash
set -euo pipefail

#--banner start
###########################################
# 44Net WireGuard Setup Script
# Author: /gregoryfenton
# GitHub: https://github.com/gregoryfenton
# Wiki:   https://44net.wiki
# Portal: https://portal.44net.org
# Purpose: Configure local or remote 44Net WireGuard gateway
###########################################
#--banner end

# Global Variables
RUN_TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="/var/log/setup_44net.log"

SHOW_BANNER=true
DRY_RUN=false
MODE=""

# Hostnames
LOCAL_HOSTNAME="myhost"
REMOTE_HOSTNAME="remotehost"

# WireGuard addresses
WG_LOCAL_IP="44.1.2.2/30"
WG_REMOTE_IP="44.1.2.1/32"
WG_REMOTE_PUBLIC_IP="203.0.113.5"
WG_PORT=51820

# Optional LAN subnet
LAN_SUBNET="192.168.1.0/24"

# 44Net ranges
NET_44_0="44.0.0.0/9"
NET_44_128="44.128.0.0/10"

# Paths
WG_CONF="/etc/wireguard/wg0.conf"
IPTABLES_V4="/etc/iptables/rules.v4"

# Key parameters (file path or encoded string)
PRIVATE_KEY_PARAM=""
PUBLIC_KEY_PARAM=""
REMOTE_PUBLIC_KEY_PARAM=""

# Functions
log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $*"
    exit 1
}

print_banner() {
    sed -n '/#--banner start/,/#--banner end/p' "$0"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --private)
                shift; PRIVATE_KEY_PARAM="$1";;
            --public)
                shift; PUBLIC_KEY_PARAM="$1";;
            --remote-key)
                shift; REMOTE_PUBLIC_KEY_PARAM="$1";;
            --dry-run)
                DRY_RUN=true;;
            --mode)
                shift; MODE="$1";;
            --no-banner)
                SHOW_BANNER=false;;
            *)
                error_exit "Unknown argument: $1";;
        esac
        shift
    done
}

validate_ip() {
    local ip=$1
    if ! [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        return 1
    fi
    return 0
}

validate_vars() {
    local errors=()
    for var in WG_LOCAL_IP WG_REMOTE_IP; do
        if ! validate_ip "${!var}"; then
            errors+=("$var (${!var}) is not valid")
        fi
    done
    [[ -n "$LAN_SUBNET" ]] && ! validate_ip "$LAN_SUBNET" && errors+=("LAN_SUBNET ($LAN_SUBNET) invalid")
    for var in NET_44_0 NET_44_128; do
        if ! validate_ip "${!var}"; then
            errors+=("$var (${!var}) invalid")
        fi
    done
    if [[ ${#errors[@]} -gt 0 ]]; then
        log "Sanity check failed:"
        for e in "${errors[@]}"; do log " - $e"; done
        exit 1
    fi
}

read_key_or_file() {
    local param="$1"
    local varname="$2"
    if [[ -f "$param" ]]; then
        eval "$varname=\"$(cat "$param")\""
    elif [[ "$param" =~ ^[A-Za-z0-9+/=]{32,}$ ]]; then
        eval "$varname=\"$param\""
    else
        error_exit "$varname parameter invalid"
    fi
}

generate_keys() {
    if [[ -f /etc/wireguard/privatekey ]]; then
        PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
        log "Loaded existing private key."
    else
        PRIVATE_KEY=$(wg genkey)
        $DRY_RUN || echo "$PRIVATE_KEY" > /etc/wireguard/privatekey
        log "Generated new private key."
    fi

    if [[ -f /etc/wireguard/publickey ]]; then
        PUBLIC_KEY=$(cat /etc/wireguard/publickey)
    else
        PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
        $DRY_RUN || echo "$PUBLIC_KEY" > /etc/wireguard/publickey
        log "Generated public key from private key."
    fi
}

write_wg_conf() {
    local content="[Interface]
Address = $WG_LOCAL_IP
ListenPort = $WG_PORT
PrivateKey = $PRIVATE_KEY

[Peer]
PublicKey = $REMOTE_PUBLIC_KEY_PARAM
AllowedIPs = $NET_44_0,$NET_44_128,$WG_REMOTE_IP
PersistentKeepalive = 25"

    if $DRY_RUN; then
        log "Dry-run: would write $WG_CONF:"
        echo "$content"
    else
        echo "$content" > "$WG_CONF"
        chmod 600 "$WG_CONF"
        log "WireGuard configuration written to $WG_CONF"
    fi
}

setup_routes() {
    if $DRY_RUN; then
        log "Dry-run: would add routes $NET_44_0,$NET_44_128 via wg0"
    else
        ip route add $NET_44_0 dev wg0 2>/dev/null || true
        ip route add $NET_44_128 dev wg0 2>/dev/null || true
        log "Routes for 44Net ranges added."
    fi
}

# Basic iptables insertion
setup_iptables() {
    if [[ -z "$LAN_SUBNET" ]]; then
        log "No LAN subnet defined; skipping NAT"
        return
    fi

    local rules="# 44Net NAT
-A POSTROUTING -s $LAN_SUBNET -o wg0 -d $NET_44_0 -j MASQUERADE
-A POSTROUTING -s $LAN_SUBNET -o wg0 -d $NET_44_128 -j MASQUERADE
# 44Net FORWARD
-A FORWARD -s $LAN_SUBNET -o wg0 -d $NET_44_0 -i vmbr0 -j ACCEPT
-A FORWARD -s $LAN_SUBNET -o wg0 -d $NET_44_128 -i vmbr0 -j ACCEPT
-A FORWARD -i wg0 -o vmbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i wg0 -o vmbr0 -d $LAN_SUBNET -j ACCEPT"

    if $DRY_RUN; then
        log "Dry-run: would append rules to $IPTABLES_V4:"
        echo "$rules"
    else
        mkdir -p $(dirname "$IPTABLES_V4")
        touch "$IPTABLES_V4"
        grep -v "# 44Net NAT" "$IPTABLES_V4" > "$IPTABLES_V4.tmp" || true
        echo "$rules" >> "$IPTABLES_V4.tmp"
        mv "$IPTABLES_V4.tmp" "$IPTABLES_V4"
        iptables-restore < "$IPTABLES_V4"
        log "iptables updated with 44Net rules."
    fi
}

enable_ip_forwarding() {
    if $DRY_RUN; then
        log "Dry-run: would enable net.ipv4.ip_forward"
    else
        sysctl -w net.ipv4.ip_forward=1
        grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        log "IP forwarding enabled."
    fi
}

# Ping verification
ping_tests() {
    if ! ip link show wg0 up &>/dev/null; then
        log "wg0 interface down; skipping 44Net ping tests."
        return
    fi
    if [[ "$MODE" == "local" ]]; then
        ping -c 2 $WG_REMOTE_PUBLIC_IP || log "Warning: cannot reach remote gateway"
        ping -c 2 44.0.0.1 || log "Warning: cannot reach 44Net main gateway"
    else
        ping -c 2 44.0.0.1 || log "Warning: remote cannot reach 44Net main gateway"
    fi
}

# ===========================
# MAIN
# ===========================

parse_args "$@"

$SHOW_BANNER && print_banner

validate_vars
generate_keys

# Mode auto-detect
MODE=${MODE:-}
if [[ -z "$MODE" ]]; then
    if [[ "$(hostname)" == "$LOCAL_HOSTNAME" ]]; then MODE="local"
    elif [[ "$(hostname)" == "$REMOTE_HOSTNAME" ]]; then MODE="remote"
    else error_exit "Unknown hostname; expected $LOCAL_HOSTNAME or $REMOTE_HOSTNAME"; fi
fi
log "Running in $MODE mode"

write_wg_conf
setup_routes
setup_iptables
enable_ip_forwarding
ping_tests

log "=== 44Net WireGuard setup completed successfully ==="
