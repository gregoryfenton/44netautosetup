# WireGuard 44Net Setup Guide

This guide explains how to configure a WireGuard tunnel to access the 44Net (ARDC) IP space.  
It supports both standalone servers and LAN gateway setups.

## Overview
### The setup:
* Establishes a secure WireGuard VPN between two peers.
* Routes all traffic destined for 44Net through the tunnel.
* Optionally NATs LAN subnet traffic through the tunnel.
* Provides persistent routes and service startup.
* Supports interactive or file-based key configuration.

This guide uses a generic Bash script (setup-44net.sh) to automate the process.

## Prerequisites

* Ubuntu/Debian server (or derivative) with root access.
* Optional LAN network to NAT for (e.g., 192.168.1.0/24).
* Internet access to install WireGuard and dependencies.
* Basic familiarity with Linux networking.

## Configuration Variables
At the top of the script, you can customize:
| Variable | Description | Example |
|-----|-----|-----|
|LOCAL_HOSTNAME|Hostname of this machine|labby|
|REMOTE_HOSTNAME|Hostname of remote peer|z230|
|WG_LOCAL_IP	WireGuard tunnel IP of this host|44.131.40.1/30|
|WG_REMOTE_IP WireGuard tunnel IP of remote peer|44.131.40.2/32|
|WG_PORT	Listening port for WireGuard|51820|
|LAN_SUBNET|Local subnet to NAT through tunnel (leave empty for standalone server)|192.168.1.0/24|
|NET_44_0|Lower 2/3 of ARDC space|44.0.0.0/9|
|NET_44_128|Upper 1/3 of ARDC space|44.128.0.0/10|
|PRIVATE_KEY_FILE|Optional: path to local private key|/root/privkey|
|PUBLIC_KEY_FILE|Optional: path to local public key|/root/pubkey|
|REMOTE_PUBLIC_KEY_FILE|Optional: remote peer public key file|/root/remote.pub|

## Running the Script
Make the script executable:
```
chmod +x setup-44net.sh
```
Run it as root:
```
sudo ./setup-44net.sh
```
Options (if using files):
```
sudo ./setup-44net.sh --private mypriv.key --public mypub.key --remote-key remote.pub
```
If no key files are provided, the script will prompt for the remote peer’s public key.
## Script Actions
When executed, the script performs:
**1. Installs packages:**
```
wireguard iptables-persistent iproute2 resolvconf
```
**2. Generates or loads keys** for WireGuard:
* Creates ```/etc/wireguard/privatekey``` and ```/etc/wireguard/publickey```.
* Sets secure permissions.

**3. Writes the WireGuard configuration** (```/etc/wireguard/wg0.conf```):
* Sets local IP, port, private key.
* Adds peer with remote public key and AllowedIPs for 44Net.
* Keeps the connection alive (PersistentKeepalive = 25).

**4. Adds routes** for the 44Net ranges.

**5. Configures iptables:**

* NATs traffic from LAN to 44Net (if LAN subnet provided).
* Sets FORWARD rules allowing outbound and inbound traffic for 44Net.
* Drops invalid packets.

**6. Enables IP forwarding** persistently.

**7. Enables and starts** the ```wg-quick@wg0``` systemd service.

**8. Updates** ```/etc/hosts``` with the remote host entry.  
## Testing the Setup
**1.** Check WireGuard status:
```
wg show
```
**2.** Test connectivity:
```
ping -c 3 44.0.0.1
ping -c 3 44.128.0.1
```
**3.** From a LAN client (if NAT is configured):
```
ping 44.0.0.1
```
Notes

The tunnel **does not forward general internet traffic**, only 44Net addresses.

For a **LAN gateway**, ensure the LAN subnet is correctly defined in ```LAN_SUBNET```.

NAT is only applied if ```LAN_SUBNET``` is set.

All key and configuration files are **stored securely** in ```/etc/wireguard```.

The script handles **persistent routing and firewall rules**.

## Advanced Options
File-based key management:
```
--public /path/to/pub.key --private /path/to/priv.key
--remote-key /path/to/remote.pub
```
* You can modify AllowedIPs to use **specific 44Net ranges** rather than the full ```/8``` block:
```
NET_44_0="44.0.0.0/9"
NET_44_128="44.128.0.0/10"
```
Useful for ARDC ranges that have been sold off or reassigned.
## Maintenance
* Restart WireGuard:
```
sudo systemctl restart wg-quick@wg0
```
* Check routes:
```
ip route show
```
* Flush and reload iptables rules:
```
sudo iptables-restore < /etc/iptables/rules.v4
```
## Conclusion
This guide provides a **repeatable, generic setup** for accessing ARDC 44Net via WireGuard:
* Works for standalone servers or LAN gateways.
* Fully persistent configuration.
* Supports file-based or interactive key management.
* Restricts traffic to 44Net only, keeping the server’s internet separate.
* Optional NAT for LAN clients.
