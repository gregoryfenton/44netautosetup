## 44Net WireGuard Setup Script - Quick Start

### Requirements
* Linux server with root/sudo access
* WireGuard installed
* iptables, iproute2, grep, awk, sed, ping installed

### 1. Clone Repository
```
git clone https://github.com/yourusername/44net-setup.git
cd 44net-setup
```

### 2. Configure INI
* Edit 44net-setup.ini to match your network:
  * LAN_SUBNET -> your LAN
  * WG_LOCAL_IP / WG_REMOTE_IP -> WireGuard tunnel addresses
  * NET_44_0 / NET_44_128 -> 44Net ranges
  * LOG_FILE -> logging path
* Keys: PRIVATE_KEY_FILE, PUBLIC_KEY_FILE, REMOTE_PUBLIC_KEY_FILE

### 3. Run the Script
```
sudo ./44net-setup.sh
```
* Adds missing MASQUERADE rules and routes
* Detects duplicates and logs alerts
* Creates log file at $LOG_FILE

### 4. First-Time Recommendations
* Use dry-run mode first:
```
sudo DRY_RUN=1 ./44net-setup.sh
```
* Ensure WG interface is down before first run
* To clean previous setup:
```
sudo ./44net-setup.sh clean
```

### 5. Troubleshooting
* Verify WireGuard interface: wg show
* Check iptables: sudo iptables -t nat -S
* Check routes: ip route show
* See TROUBLESHOOTING.md for flowchart
