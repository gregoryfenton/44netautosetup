#  44Net WireGuard Cheatsheet
#  ========================

# Modes
-  local    - Run on local client machine
-  remote   - Run on remote gateway

# Options
-  --private FILE|KEY     - Specify local private key
-  --public FILE|KEY      - Specify local public key
-  --remote-key FILE|KEY  - Specify remote public key
-  --mode local|remote    - Force mode
-  --dry-run              - Print actions without making changes
-  --install-required     - Auto-install missing packages
-  --no-banner            - Suppress banner output

# Client Management (remote)
-  Add client:       1
-  Replace client:   2
-  Remove client:    3
-  Quit:             Q
