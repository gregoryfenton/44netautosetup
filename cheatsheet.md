#  44Net WireGuard Setup - Command Line Options Cheat Sheet

## Flags
* --private <file|key>       Load private key from a file or key string
* --public <file|key>        Load public key from a file or key string
* --remote-key <file|key>    Remote peer's public key (file or key string)
* --dry-run                   Show planned changes without modifying disk
* --no-banner                 Skip printing the banner
* --mode <local|remote>       Force mode; otherwise auto-detected
* --client-action <add|replace|remove>  Manage a client (remote mode)
* --client-pub <file|key>    Client public key for add/replace/remove
* --client-ip <ip/cidr>      Allowed IP for client (required for add/replace)
* --old-client-pub <file|key>  Old client public key (for replace)

## Usage Examples

* Basic usage (auto-detect mode):
```
sudo ./setup_44net.sh
```

* Force mode:
```
sudo ./setup_44net.sh --mode local
sudo ./setup_44net.sh --mode remote
```

* Dry-run mode:
```
sudo ./setup_44net.sh --dry-run
```

* Adding a client (non-interactive):
```
sudo ./setup_44net.sh --mode remote \
    --client-action add \
    --client-pub /path/to/client.pub \
    --client-ip 44.1.2.6/32
```

* Replacing a client:
```
sudo ./setup_44net.sh --mode remote \
    --client-action replace \
    --old-client-pub /path/to/oldclient.pub \
    --client-pub /path/to/newclient.pub \
    --client-ip 44.1.2.6/32
```

* Removing a client:
```
sudo ./setup_44net.sh --mode remote \
    --client-action remove \
    --client-pub /path/to/client.pub
```

## Notes
* Interactive prompts are available if client keys or IPs are not supplied
* Public keys can be supplied as either a file path or the encoded key string
* Dry-run mode will display all changes to files, iptables, and wg set commands
* Logging is written to /var/log/44net-setup.log
* Client changes are applied live using wg set, without restarting wg0
