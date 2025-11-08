#!/bin/bash
set -e

#############################
# CONFIGURATION VARIABLES
#############################

# Hostnames
LOCAL_HOSTNAME="myhost"
REMOTE_HOSTNAME="remotehost"

# WireGuard addresses
WG_LOCAL_IP="44.x.y.w/30" # eg. 44.1.2.3/24 (your entire given 44. range)
WG_REMOTE_IP="44.x.y.z/32"# single IP address for your internet facing server
WG_PORT=51820

# Optional LAN subnet (leave empty for standalone server)
LAN_SUBNET="192.168.1.0/24"  # leave "" if no LAN clients

# 44Net ranges
NET_44_0="44.0.0.0/9" # 44net is split into two distinct ranges
NET_44_128="44.128.0.0/10"

# Paths
WG_CONF="/etc/wireguard/wg0.conf"
IPTABLES_V4="/etc/iptables/rules.v4"
LOG_FILE="/var/log/wireguard-setup.log"

# Key files (can be overridden via parameters)
PRIVATE_KEY_FILE=""
PUBLIC_KEY_FILE=""

#############################
# HELPER FUNCTIONS
#############################

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

usage() {
    echo "Usage: $0 [--public PUBFILE --private PRIVFILE] [--remote-key REMOTE_PUBFILE]"
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --public)
                shift; PRIVATE_KEY_FILE="$1";;
            --private)
                shift; PUBLIC_KEY_FILE="$1";;
            --remote-key)
                shift; REMOTE_PUBLIC_KEY_FILE="$1";;
            *)
                usage;;
        esac
        shift
    done
}

install_packages() {
    log "Installing WireGuard and dependencies..."
    if command -v nala >/dev/null; then
        nala update
        nala install -y wireguard iptables-persistent iproute2 resolvconf
    else
        apt update
        apt install -y wireguard iptables-persistent iproute2 resolvconf
    fi
}

generate_keys() {
    if [[ -n "$PRIVATE_KEY_FILE" && -n "$PUBLIC_KEY_FILE" ]]; then
        log "Using keys from provided files..."
        PRIVATE_KEY=$(cat "$PRIVATE_KEY_FILE")
        PUBLIC_KEY=$(cat "$PUBLIC_KEY_FILE")
    elif [[ -f /etc/wireguard/privatekey && -f /etc/wireguard/publickey ]]; then
        log "Using existing keys in /etc/wireguard..."
        PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
        PUBLIC_KEY=$(cat /etc/wireguard/publickey)
    else
        log "Generating new WireGuard keys..."
        mkdir -p /etc/wireguard
        umask 0077
        wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
        PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
        PUBLIC_KEY=$(cat /etc/wireguard/publickey)
    fi
}

get_remote_key() {
    if [[ -n "$REMOTE_PUBLIC_KEY_FILE" && -f "$REMOTE_PUBLIC_KEY_FILE" ]]; then
        REMOTE_PUBLIC_KEY=$(cat "$REMOTE_PUBLIC_KEY_FILE")
    else
        read -rp "Enter remote peer's Public Key: " REMOTE_PUBLIC_KEY
    fi

    if [[ -z "$REMOTE_PUBLIC_KEY" ]]; then
        log "ERROR: Remote public key not provided. Aborting."
        exit 1
    fi
}

write_wg_conf() {
    log "Writing WireGuard configuration..."
    mkdir -p $(dirname "$WG_CONF")
    cat > "$WG_CONF" <<EOF
[Interface]
Address = $WG_LOCAL_IP
ListenPort = $WG_PORT
PrivateKey = $PRIVATE_KEY

[Peer]
PublicKey = $REMOTE_PUBLIC_KEY
AllowedIPs = $NET_44_0,$NET_44_128,$WG_REMOTE_IP
PersistentKeepalive = 25
EOF
    chmod 600 "$WG_CONF"
}

setup_routes() {
    log "Adding persistent routes for 44Net..."
    ip route add $NET_44_0 dev wg0 || true
    ip route add $NET_44_128 dev wg0 || true
}

setup_iptables() {
    if [[ -z "$LAN_SUBNET" ]]; then
        log "No LAN subnet defined, skipping NAT/forwarding."
        return
    fi

    log "Setting up iptables NAT and FORWARD rules..."
    mkdir -p $(dirname "$IPTABLES_V4")

    cat > "$IPTABLES_V4" <<EOF
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]

# NAT traffic from LAN to 44Net
-A POSTROUTING -s $LAN_SUBNET -o wg0 -d $NET_44_0 -j MASQUERADE
-A POSTROUTING -s $LAN_SUBNET -o wg0 -d $NET_44_128 -j MASQUERADE

COMMIT

*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Outbound from LAN to 44Net
-A FORWARD -s $LAN_SUBNET -o wg0 -d $NET_44_0 -i vmbr0 -j ACCEPT
-A FORWARD -s $LAN_SUBNET -o wg0 -d $NET_44_128 -i vmbr0 -j ACCEPT

# Return traffic
-A FORWARD -i wg0 -o vmbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Optional new connections from WG to LAN
-A FORWARD -i wg0 -o vmbr0 -d $LAN_SUBNET -j ACCEPT

COMMIT
EOF
    iptables-restore < "$IPTABLES_V4"
}

enable_ip_forwarding() {
    log "Enabling IP forwarding persistently..."
    sysctl -w net.ipv4.ip_forward=1
    grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

enable_service() {
    log "Enabling wg-quick@wg0 service..."
    systemctl enable wg-quick@wg0
    systemctl restart wg-quick@wg0
}

update_hosts() {
    log "Updating /etc/hosts with remote host..."
    grep -q "$WG_REMOTE_IP" /etc/hosts || echo "$WG_REMOTE_IP    $REMOTE_HOSTNAME" >> /etc/hosts
}

#############################
# MAIN SCRIPT
#############################

parse_args "$@"
install_packages
generate_keys
get_remote_key
write_wg_conf
setup_routes
setup_iptables
enable_ip_forwarding
enable_service
update_hosts

log "=== WireGuard 44Net setup completed successfully! ==="
