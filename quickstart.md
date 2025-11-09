## 44Net WireGuard Setup Script

![44Net](https://raw.githubusercontent.com/gregoryfenton/44net/main/logo.png)  

*Author: /gregoryfenton  
*GitHub: https://github.com/gregoryfenton  
*Wiki: https://44net.wiki  
*Portal: https://portal.44net.org  

---

### Overview

This script configures a **WireGuard VPN tunnel** for 44Net connectivity on either a **local client machine** or a **remote gateway server**. It ensures proper routing, firewall rules, and sanity checks to allow LAN clients to access 44Net addresses through a remote gateway.

* Key Features:

- Automatic local/remote mode detection (based on hostname)  
- Full IP and configuration sanity checks before making changes  
- Reusable private keys; generates public key if missing  
- Safe iptables editing — preserves existing rules  
- Adds routes for 44Net ranges (44.0.0.0/9 and 44.128.0.0/10)  
- Remote client management (add/remove/replace) without restarting WireGuard  
- Optional dry-run mode to preview changes  
- Ping checks to verify connectivity  

---

### Requirements

- **Operating System:** Linux (Debian/Ubuntu recommended)  
- **Packages:** wireguard, iptables-persistent, iproute2, resolvconf  
- **Permissions:** Root access required for installation, routing, and iptables updates  

---

### Installation

1. Clone the repository:  

```bash
git clone https://github.com/gregoryfenton/44netautosetup.git
cd 44net
```

2. Make the script executable:  

```bash
chmod +x setup_44net.sh
```

3. (Optional) Install dependencies:

```bash
sudo apt update
sudo apt install -y wireguard iptables-persistent iproute2 resolvconf
```

---

### Usage

#### Basic Usage

```bash
sudo ./setup_44net.sh
```

The script will:

1. Detect if it is running on the local client or remote gateway (based on hostname).  
2. Perform sanity checks on IPs, LAN subnet, and WireGuard keys.  
3. Generate missing keys as needed.  
4. Update /etc/wireguard/wg0.conf.  
5. Add routes for 44Net ranges.  
6. Update iptables rules safely.  
7. Enable IP forwarding.  
8. Run ping tests to verify connectivity.  
9. Log all actions to /var/log/wg-manager.log.  

---

#### Command-Line Options

| Option | Description  
|--------|-------------  
| --private <key\|file> | Private key string or path to a private key file  
| --public <key\|file> | Public key string or path to a public key file  
| --remote-key <key\|file> | Public key of the remote peer (gateway or client)  
| --dry-run | Print all changes the script would make without touching files  
| --mode <local\|remote> | Override automatic host detection  
| --no-banner | Skip displaying the banner at the start of the script  

---

#### Examples

##### Local Client

```bash
sudo ./setup_44net.sh --private /home/user/wg-private.key --remote-key /home/user/wg-remote.pub
```

- Sets up the client tunnel to the remote 44Net gateway  
- Adds necessary routes and iptables rules  
- Performs connectivity checks to remote gateway and 44Net main node  

##### Remote Gateway

```bash
sudo ./setup_44net.sh --mode remote --private /etc/wireguard/privatekey --remote-key CLIENT_PUBLIC_KEY
```

- Configures the remote gateway interface  
- Adds NAT and forwarding rules for LAN clients  
- Supports dynamic client management via wg set live updates  

##### Dry-Run Mode

```bash
sudo ./setup_44net.sh --dry-run
```

- Outputs all configuration changes to console  
- No files or iptables rules are modified  

---

### Logging

All operations are logged with timestamps to:

`
/var/log/setup_44net.log
`

Use standard log rotation to manage file size.

---

### Adding/Removing Clients (Remote Gateway Only)

- The remote gateway supports adding, replacing, or removing clients **without restarting WireGuard**, using wg set live updates.  
- This ensures minimal downtime and maintains connectivity for existing peers.

---

### Safety Notes

- The script **never exposes or requires client private keys**.  
- Sanity checks validate all IPs, subnets, and key formats before writing any configuration.  
- Existing firewall rules are preserved; only the 44Net-specific rules are added or updated.  
- Ping checks confirm that the tunnel and 44Net connectivity are functional after setup.  

---

### License

MIT License — see LICENSE in the repository.

---

### Support & Links

- GitHub: https://github.com/gregoryfenton  
- 44Net Wiki: https://44net.wiki  
- 44Net Portal: https://portal.44net.org  
