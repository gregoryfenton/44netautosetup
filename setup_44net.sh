#!/bin/bash
set -e

#================================================#
# 44Net WireGuard Setup          ▌ ▌▌ ▌▙ ▌   ▐   #
# Author: /gregoryfenton         ▚▄▌▚▄▌▌▌▌▞▀▖▜▀  #
# Wiki: https://44net.wiki         ▌  ▌▌▝▌▛▀ ▐ ▖ #
# Portal: https://portal.44net.org ▘  ▘▘ ▘▝▀▘ ▀  #
# Discussion: https://ardc.groups.io/g/44net     #
# GitHub: https://github.com/gregoryfenton       #
#================================================#

#############################
# Defaults (INI-overridable)
#############################
INI_FILE="/etc/44net.conf"
DRY_RUN=0
COLOR=0
NO_BANNER=0
UPDATE=0
CLEAN=0

# Paths
WG_CONF="/etc/wireguard/wg0.conf"
IPTABLES_V4="/etc/iptables/rules.v4"
LOG_FILE="/var/log/44net-setup.log"
PRIVATE_KEY_FILE="/etc/wireguard/privatekey"
PUBLIC_KEY_FILE="/etc/wireguard/publickey"

# Safe default variables
LOCAL_HOSTNAME=""
REMOTE_HOSTNAME=""
WG_LOCAL_IP=""
WG_REMOTE_IP=""
WG_PORT=51820
LAN_SUBNET=""
NET_44_0="44.0.0.0/9"
NET_44_128="44.128.0.0/10"
REMOTE_PUBLIC_KEY_FILE=""

#############################
# Load INI
#############################
[ -f "$INI_FILE" ] && source "$INI_FILE"

#############################
# Utility functions
#############################
log() {
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    if [ "$COLOR" -eq 1 ]; then
        echo -e "\e[32m[$ts]\e[0m $*" | tee -a "$LOG_FILE"
    else
        echo "[$ts] $*" | tee -a "$LOG_FILE"
    fi
}

log_warn() {
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    if [ "$COLOR" -eq 1 ]; then
        echo -e "\e[33m[$ts]\e[0m $*" | tee -a "$LOG_FILE"
    else
        echo "[$ts] $*" | tee -a "$LOG_FILE"
    fi
}

run_or_echo() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] $*"
    else
        eval "$@"
    fi
}

print_banner() {
    [ "$NO_BANNER" -eq 1 ] && return
cat <<'EOF'
##################################################
# 44Net WireGuard Setup          ▌ ▌▌ ▌▙ ▌   ▐   #
# Author: /gregoryfenton         ▚▄▌▚▄▌▌▌▌▞▀▖▜▀  #
# Wiki: https://44net.wiki         ▌  ▌▌▝▌▛▀ ▐ ▖ #
# Portal: https://portal.44net.org ▘  ▘▘ ▘▝▀▘ ▀  #
# Discussion: https://ardc.groups.io/g/44net     #
# GitHub: https://github.com/gregoryfenton       #
##################################################
EOF
}

#############################
# Command-line parsing
#############################
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --color|--colour) COLOR=1 ;;
        --no-banner) NO_BANNER=1 ;;
        --update) UPDATE=1 ;;
        --clean) CLEAN=1 ;;
        --config) shift; INI_FILE="$1"; source "$INI_FILE" ;;
        *) log_warn "Unknown option: $1" ;;
    esac
    shift
done

#############################
# Required command check
#############################
REQUIRED_COMMANDS=(wg ip iptables iproute2 curl grep sed awk systemctl ping)
PKG_MAP=( ["wg"]="wireguard" ["iptables"]="iptables-persistent" ["ip"]="iproute2" ["curl"]="curl" ["grep"]="grep" ["sed"]="sed" ["awk"]="awk" ["systemctl"]="systemd" ["ping"]="iputils-ping" )

missing_pkgs=()
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        missing_pkgs+=("${PKG_MAP[$cmd]:-$cmd}")
    fi
done

if [ ${#missing_pkgs[@]} -gt 0 ]; then
    log_warn "Required programs missing: ${missing_pkgs[*]}"
    exit 1
fi

#############################
# Key handling
#############################
read_key_or_file() {
    local val="$1"
    if [[ -f "$val" ]]; then
        cat "$val"
    elif [[ "$val" =~ ^[A-Za-z0-9+/=]+$ ]]; then
        echo "$val"
    else
        log_warn "Invalid key or file: $val"
        exit 1
    fi
}

generate_keys() {
    if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
        log "Generating private key..."
        run_or_echo "wg genkey | tee '$PRIVATE_KEY_FILE' | wg pubkey > '$PUBLIC_KEY_FILE'"
    elif [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
        log "Generating public key from existing private key..."
        run_or_echo "wg pubkey < '$PRIVATE_KEY_FILE' > '$PUBLIC_KEY_FILE'"
    fi
}

#############################
# WireGuard config
#############################
write_wg_conf() {
    log "Writing WireGuard config..."
cat > "$WG_CONF" <<EOF
[Interface]
Address = $WG_LOCAL_IP
ListenPort = $WG_PORT
PrivateKey = $(read_key_or_file "$PRIVATE_KEY_FILE")

[Peer]
PublicKey = $(read_key_or_file "$REMOTE_PUBLIC_KEY_FILE")
AllowedIPs = $NET_44_0,$NET_44_128,$WG_REMOTE_IP
PersistentKeepalive = 25
EOF
}

#############################
# Routes and forwarding
#############################
setup_routes() {
    log "Adding 44Net routes..."
    run_or_echo "ip route add $NET_44_0 dev wg0 || true"
    run_or_echo "ip route add $NET_44_128 dev wg0 || true"
}

enable_ip_forwarding() {
    log "Enabling IP forwarding..."
    run_or_echo "sysctl -w net.ipv4.ip_forward=1"
}

bring_up_interface() {
    log "Bringing up WireGuard..."
    run_or_echo "systemctl enable wg-quick@wg0 && systemctl restart wg-quick@wg0"
}

#############################
# Non-destructive iptables insertion
#############################
update_iptables() {
    log "Updating iptables..."
    mkdir -p $(dirname "$IPTABLES_V4")
    tmpfile=$(mktemp)
    if [[ -f "$IPTABLES_V4" ]]; then
        grep -v '# 44Net rules' "$IPTABLES_V4" > "$tmpfile"
    fi
    cat >> "$tmpfile" <<EOF
# 44Net rules
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s $LAN_SUBNET -o wg0 -d $NET_44_0 -j MASQUERADE
-A POSTROUTING -s $LAN_SUBNET -o wg0 -d $NET_44_128 -j MASQUERADE
COMMIT

*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A FORWARD -s $LAN_SUBNET -o wg0 -d $NET_44_0 -i vmbr0 -j ACCEPT
-A FORWARD -s $LAN_SUBNET -o wg0 -d $NET_44_128 -i vmbr0 -j ACCEPT
-A FORWARD -i wg0 -o vmbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i wg0 -o vmbr0 -d $LAN_SUBNET -j ACCEPT
COMMIT
EOF
    run_or_echo "cp '$tmpfile' '$IPTABLES_V4' && iptables-restore < '$IPTABLES_V4'"
    rm -f "$tmpfile"
}

#############################
# Cleanup
#############################
cleanup_44net() {
    log "Starting --clean"
    run_or_echo "wg-quick down wg0 || true"
    run_or_echo "rm -f '$WG_CONF' '$PRIVATE_KEY_FILE' '$PUBLIC_KEY_FILE'"
    run_or_echo "ip route del $NET_44_0 dev wg0 || true"
    run_or_echo "ip route del $NET_44_128 dev wg0 || true"
    run_or_echo "iptables-restore < <(grep -v '# 44Net rules' '$IPTABLES_V4') || true"
    log "44Net cleanup completed"
}

#############################
# Self-update
#############################
self_update() {
    local tmp=$(mktemp)
    if curl -fsSL "https://raw.githubusercontent.com/gregoryfenton/44netautosetup/main/setup_44net.sh" -o "$tmp"; then
        if ! cmp -s "$0" "$tmp"; then
            log "New version detected. Updating..."
            run_or_echo "cp '$tmp' '$0' && chmod +x '$0'"
            log "Script updated. Re-run to use latest version."
            rm -f "$tmp"
            exit 0
        else
            log "Already at latest version."
        fi
    else
        log_warn "Update check failed."
    fi
    rm -f "$tmp"
}

#############################
# Main
#############################
print_banner

[ "$UPDATE" -eq 1 ] && self_update
[ "$CLEAN" -eq 1 ] && { cleanup_44net; exit 0; }

generate_keys
write_wg_conf
setup_routes
enable_ip_forwarding
update_iptables
bring_up_interface

log "=== 44Net WireGuard setup completed successfully ==="
