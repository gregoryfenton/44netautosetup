## 44Net WireGuard Setup - Troubleshooting Flowchart  
  
Start  
 |  
 v  
[Run 44net-setup.sh?]---No--->[Run with sudo]  
 | Yes  
 v  
[Required commands installed?]---No--->[Install missing: wg, iptables, ip, grep, awk, sed, ping]  
 | Yes  
 v  
[WireGuard interface up?]---No--->[Check wg0 config or run 'wg-quick up wg0']  
 | Yes  
 v  
[Duplicate MASQUERADE rules?]---Yes--->[Logged alert, continue]  
 | No  
 v  
[Add missing MASQUERADE rules]  
 |  
 v  
[Routes for NET_44_0 / NET_44_128 / WG_REMOTE_IP exist?]---Yes--->[Logged duplicate, continue]  
 | No  
 v  
[Add missing routes]  
 |  
 v  
[Test LAN connectivity to 44Net]---Fail--->[Check LAN_SUBNET, routing, WG config, firewall]  
 | Pass  
 v  
All systems operational  
