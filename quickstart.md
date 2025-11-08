WireGuard 44Net Quickstart Reference
1. Setup Variables

Adjust these at the top of the script before running, or export them in your shell:

# Hostnames
LOCAL_HOSTNAME="labby"
REMOTE_HOSTNAME="z230"

# WireGuard IPs
WG_LOCAL_IP="44.131.40.1/30"
WG_REMOTE_IP="44.131.40.2/32"
WG_PORT=51820

# Optional LAN subnet for NAT (leave empty if standalone)
LAN_SUBNET="192.168.1.0/24"

# 44Net ranges
NET_44_0="44.0.0.0/9"
NET_44_128="44.128.0.0/10"

# Key files (optional)
PRIVATE_KEY_FILE="/root/privkey"
PUBLIC_KEY_FILE="/root/pubkey"
REMOTE_PUBLIC_KEY_FILE="/root/remote.pub"

2. Install & Run Setup Script
chmod +x setup-44net.sh
sudo ./setup-44net.sh


Optional parameters if using pre-generated keys:

sudo ./setup-44net.sh \
  --private /root/privkey \
  --public /root/pubkey \
  --remote-key /root/remote.pub


If keys are not provided, the script prompts for the remote public key.

3. Verify WireGuard
wg show
systemctl status wg-quick@wg0

4. Test Connectivity

From the server:

ping -c 3 44.0.0.1
ping -c 3 44.128.0.1


From a LAN client (if NAT configured):

ping 44.0.0.1
ping 44.128.0.1

5. Firewall & NAT Rules

Persistent iptables rules are stored in:

/etc/iptables/rules.v4


NAT rules for LAN to 44Net:

POSTROUTING -s <LAN_SUBNET> -o wg0 -d 44.0.0.0/9 -j MASQUERADE
POSTROUTING -s <LAN_SUBNET> -o wg0 -d 44.128.0.0/10 -j MASQUERADE


FORWARD rules:

Allow LAN -> 44Net (outbound)
Allow 44Net -> LAN (inbound, RELATED,ESTABLISHED)

6. IP Forwarding

Ensure IP forwarding is enabled persistently:

sysctl -w net.ipv4.ip_forward=1
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

7. Service Management
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
sudo systemctl restart wg-quick@wg0   # if needed

8. Advanced / Optional

Use specific 44Net subnets instead of full /8 if part of the space is sold:

NET_44_0="44.0.0.0/9"
NET_44_128="44.128.0.0/10"


File-based key exchange:

--private /path/to/privkey --public /path/to/pubkey --remote-key /path/to/remote.pub


Check routes:

ip route show


Reload iptables rules:

sudo iptables-restore < /etc/iptables/rules.v4

9. Notes

Tunnel only allows 44Net traffic; normal internet remains separate.

LAN NAT optional; leave LAN_SUBNET empty if standalone server.

Key exchange can be manual (interactive prompt) or via files.

Persistent and fully automated after script runs.
