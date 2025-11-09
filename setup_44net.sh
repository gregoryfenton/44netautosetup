#!/bin/bash
set -e

#--banner start
# 44Net WireGuard Setup
# Author: /gregoryfenton
# GitHub: https://github.com/gregoryfenton
# Wiki: https://44net.wiki
# Portal: https://portal.44net.org
#--banner end

#############################
# CONFIGURATION VARIABLES
#############################
LOCAL_HOSTNAME="myhost"
REMOTE_HOSTNAME="remotehost"

WG_LOCAL_IP="44.x.y.w/30"
WG_REMOTE_IP="44.x.y.z/32"

REMOTE_PUBLIC_IP=""    # Optional for sanity check/ping

WG_PORT=51820
LAN_SUBNET="192.168.1.0/24"

NET_44_0="44.0.0.0/9"
NET_44_128="44.128.0.0/10"

WG_CONF="/etc/wireguard/wg0.conf"
IPTABLES_V4="/etc/iptables/rules.v4"
LOG_FILE="/var/log/44net-setup.log"

PRIVATE_KEY_FILE=""
PUBLIC_KEY_FILE=""
REMOTE_PUBLIC_KEY_FILE=""

DRY_RUN=false
SHOW_BANNER=true
INSTALL_REQUIRED=false
MODE="auto"

#############################
# REQUIRED COMMANDS
#############################
REQUIRED_COMMANDS=(wg wg-quick ip iptables iptables-restore sysctl mkdir cat grep tee echo date ping awk sed)
declare -A PKG_MAP=(
  ["wg"]="wireguard"
  ["wg-quick"]="wireguard"
  ["ip"]="iproute2"
  ["iptables"]="iptables"
  ["iptables-restore"]="iptables"
  ["sysctl"]="procps"
  ["mkdir"]="coreutils"
  ["cat"]="coreutils"
  ["grep"]="grep"
  ["tee"]="coreutils"
  ["echo"]="coreutils"
  ["date"]="coreutils"
  ["ping"]="iputils-ping"
  ["awk"]="gawk"
  ["sed"]="sed"
)

#############################
# LOGGING
#############################
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(timestamp)] $*" | tee -a "$LOG_FILE"; }

#############################
# ARG PARSING
#############################
usage() {
    echo "Usage: $0 [--private FILE|KEY] [--public FILE|KEY] [--remote-key FILE|KEY] [--mode local|remote] [--dry-run] [--install-required] [--no-banner]"
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --private) shift; PRIVATE_KEY_FILE="$1";;
            --public) shift; PUBLIC_KEY_FILE="$1";;
            --remote-key) shift; REMOTE_PUBLIC_KEY_FILE="$1";;
            --mode) shift; MODE="$1";;
            --dry-run) DRY_RUN=true;;
            --no-banner) SHOW_BANNER=false;;
            --install-required) INSTALL_REQUIRED=true;;
            *) usage;;
        esac
        shift
    done
}

#############################
# PREREQUISITE CHECK
#############################
install_missing_packages() {
    local missing_pkgs=()
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            local pkg="${PKG_MAP[$cmd]:-$cmd}"
            # Add pkg only if not already in missing_pkgs
            [[ ! " ${missing_pkgs[*]} " =~ " ${pkg} " ]] && missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        log "Required programs missing: ${missing_pkgs[*]}"
        if [[ "$INSTALL_REQUIRED" == true ]]; then
            log "Installing missing packages..."
            if command -v nala &>/dev/null; then
                [[ "$DRY_RUN" == true ]] && log "Dry-run: would install via nala: ${missing_pkgs[*]}" || sudo nala install -y "${missing_pkgs[@]}"
            else
                [[ "$DRY_RUN" == true ]] && log "Dry-run: would install via apt: ${missing_pkgs[*]}" || { sudo apt update; sudo apt install -y "${missing_pkgs[@]}"; }
            fi
        else
            echo "Required programs missing. Install them with:"
            if command -v nala &>/dev/null; then
                echo "nala install ${missing_pkgs[*]}"
            else
                echo "apt-get install ${missing_pkgs[*]}"
            fi
            exit 1
        fi
    else
        log "All required packages are present"
    fi
}

#############################
# BANNER
#############################
print_banner() {
cat <<EOF
=========================================
  44Net WireGuard Setup
  Author: /gregoryfenton
  GitHub: https://github.com/gregoryfenton
  Wiki: https://44net.wiki
  Portal: https://portal.44net.org
=========================================
EOF
}

#############################
# HELPER FUNCTIONS
#############################
read_key_or_file() {
    local val="$1" name="$2"
    if [[ -f "$val" ]]; then
        cat "$val"
    elif [[ "$val" =~ ^[A-Za-z0-9+/=]{32,}$ ]]; then
        echo "$val"
    else
        log "Invalid $name: neither file nor valid key string"
        exit 1
    fi
}

validate_ip() {
    local ip="$1"
    if ! [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        log "Invalid IP/CIDR: $ip"
        exit 1
    fi
}

ping_check() {
    local target="$1"
    ping -c 1 -W 2 "$target" &>/dev/null || log "Warning: cannot reach $target"
}

#############################
# CLIENT MANAGEMENT (REMOTE)
#############################
add_client() {
    local name="$1" pub="$2" ips="$3"
    log "Adding client $name ($ips)"
    if [[ "$DRY_RUN" == true ]]; then
        echo "Dry-run: wg set wg0 peer $pub allowed-ips $ips"
    else
        wg set wg0 peer "$pub" allowed-ips "$ips"
        echo -e "\n[Peer]\n# $name\nPublicKey = $pub\nAllowedIPs = $ips" >> "$WG_CONF"
    fi
}

remove_client() {
    local name="$1"
    log "Removing client $name"
    if [[ "$DRY_RUN" == true ]]; then
        echo "Dry-run: removing peer $name (look up public key in config)"
    else
        local peer_pub
        peer_pub=$(awk -v n="$name" '/\[Peer\]/{p=0} $0 ~ n{p=1} p && /PublicKey/{print $3}' "$WG_CONF")
        [[ -n "$peer_pub" ]] && wg set wg0 peer "$peer_pub" remove
        sed -i "/# $name/,/\[Peer\]/ { /# $name/! { /[Peer]/!d } }" "$WG_CONF"
    fi
}

replace_client() {
    local name="$1" pub="$2" ips="$3"
    log "Replacing client $name"
    remove_client "$name"
    add_client "$name" "$pub" "$ips"
}

manage_client() {
    local action client_name client_pub allowed_ips
    while true; do
        echo "Select client action: [1] Add [2] Replace [3] Remove [Q] Quit"
        read -rp "> " action
        case "$action" in
            1|Add|add)
                read -rp "Enter client name: " client_name
                read -rp "Enter client public key: " client_pub
                read -rp "Enter allowed IPs (comma-separated, e.g., 44.x.y.z/32): " allowed_ips
                add_client "$client_name" "$client_pub" "$allowed_ips"
                ;;
            2|Replace|replace)
                read -rp "Enter client name to replace: " client_name
                read -rp "Enter new client public key: " client_pub
                read -rp "Enter new allowed IPs: " allowed_ips
                replace_client "$client_name" "$client_pub" "$allowed_ips"
                ;;
            3|Remove|remove)
                read -rp "Enter client name to remove: " client_name
                remove_client "$client_name"
                ;;
            Q|q|quit)
                break
                ;;
            *)
                echo "Invalid option";;
        esac
    done
}

#############################
# MAIN FLOW
#############################
parse_args "$@"
$SHOW_BANNER && print_banner
install_missing_packages

# Detect mode automatically if not forced
[[ "$MODE" == "auto" ]] && [[ "$(hostname)" == "$LOCAL_HOSTNAME" ]] && MODE="local"
[[ "$MODE" == "auto" ]] && [[ "$(hostname)" == "$REMOTE_HOSTNAME" ]] && MODE="remote"
log "Running in $MODE mode"

# Validate IPs
validate_ip "$WG_LOCAL_IP"
validate_ip "$WG_REMOTE_IP"
[[ -n "$REMOTE_PUBLIC_IP" ]] && validate_ip "$REMOTE_PUBLIC_IP"
[[ -n "$LAN_SUBNET" ]] && validate_ip "$LAN_SUBNET"

# Read/generate keys
[[ -n "$PRIVATE_KEY_FILE" ]] && PRIVATE_KEY=$(read_key_or_file "$PRIVATE_KEY_FILE" "private key")
[[ -n "$PUBLIC_KEY_FILE" ]] && PUBLIC_KEY=$(read_key_or_file "$PUBLIC_KEY_FILE" "public key")
[[ -n "$REMOTE_PUBLIC_KEY_FILE" ]] && REMOTE_PUBLIC_KEY=$(read_key_or_file "$REMOTE_PUBLIC_KEY_FILE" "remote public key")

# Generate missing keys if necessary
if [[ -z "$PRIVATE_KEY" ]]; then
    log "Generating private key..."
    [[ "$DRY_RUN" == false ]] && { umask 0077; mkdir -p /etc/wireguard; wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey; }
    PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
    PUBLIC_KEY=$(cat /etc/wireguard/publickey)
elif [[ -z "$PUBLIC_KEY" ]]; then
    log "Generating public key from existing private key..."
    [[ "$DRY_RUN" == false ]] && echo "$PRIVATE_KEY" | wg pubkey > /etc/wireguard/publickey
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
fi

# Write wg0.conf
log "Writing WireGuard config..."
if [[ "$DRY_RUN" == true ]]; then
cat <<EOF
[Interface]
Address = $WG_LOCAL_IP
ListenPort = $WG_PORT
PrivateKey = $PRIVATE_KEY

[Peer]
PublicKey = $REMOTE_PUBLIC_KEY
AllowedIPs = $NET_44_0,$NET_44_128,$WG_REMOTE_IP
PersistentKeepalive = 25
EOF
else
    mkdir -p "$(dirname "$WG_CONF")"
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
fi

# Routes
log "Setting 44Net routes..."
[[ "$DRY_RUN" == false ]] && { ip route add $NET_44_0 dev wg0 || true; ip route add $NET_44_128 dev wg0 || true; }

# Iptables
if [[ -n "$LAN_SUBNET" ]]; then
    log "Updating iptables..."
    [[ "$DRY_RUN" == false ]] && {
        mkdir -p "$(dirname "$IPTABLES_V4")"
        [[ -f "$IPTABLES_V4" ]] && cp "$IPTABLES_V4" "$IPTABLES_V4.bak"
        cat >> "$IPTABLES_V4" <<EOF

*nat
-A POSTROUTING -s $LAN_SUBNET -o wg0 -d $NET_44_0 -j MASQUERADE
-A POSTROUTING -s $LAN_SUBNET -o wg0 -d $NET_44_128 -j MASQUERADE
COMMIT

*filter
-A FORWARD -s $LAN_SUBNET -o wg0 -d $NET_44_0 -i vmbr0 -j ACCEPT
-A FORWARD -s $LAN_SUBNET -o wg0 -d $NET_44_128 -i vmbr0 -j ACCEPT
-A FORWARD -i wg0 -o vmbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i wg0 -o vmbr0 -d $LAN_SUBNET -j ACCEPT
COMMIT
EOF
        iptables-restore < "$IPTABLES_V4"
    }
fi

# Enable IP forwarding
log "Enabling IP forwarding..."
[[ "$DRY_RUN" == false ]] && { sysctl -w net.ipv4.ip_forward=1; grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf; }

# Enable wg0
if [[ "$DRY_RUN" == false ]]; then
    log "Bringing up WireGuard interface..."
    systemctl enable wg-quick@wg0
    systemctl restart wg-quick@wg0
fi

# Sanity ping
if [[ "$MODE" == "local" ]]; then
    ping_check "$WG_REMOTE_IP"
    ping_check "44.0.0.1"
elif [[ "$MODE" == "remote" ]]; then
    ping_check "44.0.0.1"
fi

# Remote client management
if [[ "$MODE" == "remote" ]]; then
    log "Remote gateway client management starting..."
    manage_client
fi

log "=== 44Net WireGuard setup completed successfully ==="
