## 44Net WireGuard Setup Script - User Guide

### Overview
Sets up NAT and routing for 44Net via WireGuard:
* MASQUERADE rules
* Routes for 44Net ranges
* Duplicate detection
* Logging and dry-run support

### Configuration
Uses 44net-setup.ini for variable overrides.
* Network: LAN, WG addresses, 44Net ranges
* Paths: WG config, IPTables rules, log file
* Keys: local/private and remote keys
* Options: COLOR, DRY_RUN

#### Important Notes
* Script reads variable names; sections are cosmetic
* Dry-run mode is safe to test before applying
* Idempotent: safe to run multiple times

### Script Functions

| Function | Description |
|---|---|
| timestamp | Returns current time for logs
| colour_echo | Logs messages with severity colors
| run_or_echo | Executes commands or prints them if dry-run
| read_key_or_file | Reads a key from file or value
| check_required_cmds | Ensures necessary binaries exist
| duplicate_rule_check | Detects multiple identical iptables rules
| clean | Removes WG config, routes, and NAT rules

### Running
```
sudo ./44net-setup.sh
```
Dry-run first:
```
sudo DRY_RUN=1 ./44net-setup.sh
```

### Cleaning
```
sudo ./44net-setup.sh clean
```

### Logging
* Default: /var/log/44net-setup.log
* Alerts for duplicate rules or critical issues
