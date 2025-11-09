#  Quickstart Guide
#  =================

-  1. Copy the script to your machine
```bash
    cp setup_44net.sh /usr/local/bin/
```

-  2. Make executable
```bash
    chmod +x setup_44net.sh
```

-  3. Run prerequisites check (dry-run)
```bash
    ./setup_44net.sh --dry-run --install-required
```

-  4. Run setup
```bash
    ./setup_44net.sh --mode local
```
-  or
```bash
    ./setup_44net.sh --mode remote
```

-  5. Check
      
```bash
    /var/log/44net-setup.log
```
for detailed operation logs
