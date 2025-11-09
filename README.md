#  44Net WireGuard Setup
==============================

* Author: /gregoryfenton  
* GitHub: https://github.com/gregoryfenton  
* Wiki: https://44net.wiki  
* Portal: https://portal.44net.org  

## Overview
This script configures a local or remote 44Net WireGuard gateway. It supports:
* Local client routing to 44Net
* Remote gateway setup
* Interactive and non-interactive client management (add, replace, remove)
* Dry-run mode for testing changes
* Full sanity checks and logging

## Requirements
* bash shell
* WireGuard installed (wg, wg-quick)
* iptables and iproute2
* Root privileges

## Usage

* Basic usage (auto-detect mode):

```
sudo ./setup_44net.sh
```

* Force mode (local or remote):

```
sudo ./setup_44net.sh --mode local
sudo ./setup_44net.sh --mode remote
```

* Dry-run mode (no changes applied):

```
sudo ./setup_44net.sh --dry-run
```

## Key Parameters

* Load keys from files or provide the key strings:

```
--private /path/to/privatekey
--public  /path/to/publickey
--remote-key /path/to/remote_publickey
```

## Client Management

* Interactive:

```
sudo ./setup_44net.sh --mode remote
# Then follow prompts to add/replace/remove clients
```

* Non-interactive:

* Add a client:

```
sudo ./setup_44net.sh --mode remote \
    --client-action add \
    --client-pub /path/to/client.pub \
    --client-ip 44.1.2.6/32
```

* Replace a client:

```
sudo ./setup_44net.sh --mode remote \
    --client-action replace \
    --old-client-pub /path/to/oldclient.pub \
    --client-pub /path/to/newclient.pub \
    --client-ip 44.1.2.6/32
```

* Remove a client:

```
sudo ./setup_44net.sh --mode remote \
    --client-action remove \
    --client-pub /path/to/client.pub
```

## Additional Flags

* --dry-run : Show what would be changed without touching disk  
* --no-banner : Skip printing the banner  
* --mode [local|remote] : Force the script mode (otherwise auto-detected)  

## Logging

* All actions are logged to /var/log/44net-setup.log  
* Dry-run mode prints intended changes without modifying files

## Notes

* The script preserves existing iptables rules and appends 44Net-specific rules safely.
* Public keys can be provided as either encoded strings or file paths.
* IP addresses and key validity are fully sanity-checked before any changes are made.
* Client changes are applied on-the-fly using wg set without restarting the interface.
