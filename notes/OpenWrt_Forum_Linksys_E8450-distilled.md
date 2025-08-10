# Distilled Linksys E8450 notes

Via Belkin RT3200/Linksys E8450 WiFi AX discussion
https://forum.openwrt.org/t/belkin-rt3200-linksys-e8450-wifi-ax-discussion/94302

Dating from mid-2021 to mid-2025.

## Table of Contents

- [Troubleshooting, Tips, and Known Issues](#troubleshooting-tips-and-known-issues)
  - [Critical Issue: The "Reboot to Recovery" Loop](#critical-issue-the-reboot-to-recovery-loop)
  - [Critical Issue: I/O Errors on /dev/mtdblock2](#critical-issue-io-errors-on-devmtdblock2)
  - [Tips for Maximum Stability](#tips-for-maximum-stability)
- [Frequently Asked Questions (FAQs) - E8450 Edition](#frequently-asked-questions-faqs---e8450-edition)
- [OpenWrt 24.10.x Specific Issues and Solutions](#openwrt-2410x-specific-issues-and-solutions)
  - [Attended Sysupgrade Issues](#attended-sysupgrade-issues)
  - [WDS Configuration Changes](#wds-configuration-changes)
  - [Package Dependencies](#package-dependencies)
- [Memory Management & OOM Prevention](#memory-management--oom-prevention)
  - [Understanding Memory Pressure](#understanding-memory-pressure)
  - [Zram-Swap Configuration](#zram-swap-configuration)
  - [Memory Optimization Tips](#memory-optimization-tips)
- [WiFi 6 (802.11ax) Performance Optimization](#wifi-6-80211ax-performance-optimization)
  - [Country Code and Regulatory Settings](#country-code-and-regulatory-settings)
  - [802.11ax Specific Optimizations](#80211ax-specific-optimizations)
  - [Power Save and Battery Device Optimization](#power-save-and-battery-device-optimization)
  - [Channel Width Recommendations](#channel-width-recommendations)
- [Advanced Network Segmentation with VLANs](#advanced-network-segmentation-with-vlans)
  - [Guest Network with Proper Isolation](#guest-network-with-proper-isolation)
  - [IoT VLAN Segregation](#iot-vlan-segregation)
  - [Multiple SSIDs with Different Zones](#multiple-ssids-with-different-zones)
- [Release Selection for Maximum Stability](#release-selection-for-maximum-stability)
  - [Most Stable Releases (Community Consensus)](#most-stable-releases-community-consensus)
  - [Stability Best Practices](#stability-best-practices)
  - [Known Stable Configurations](#known-stable-configurations)
- [DNS and Ad-blocking Solutions](#dns-and-ad-blocking-solutions)
  - [Ad-blocking Comparison for E8450](#ad-blocking-comparison-for-e8450)
  - [DNS over HTTPS/TLS Configuration](#dns-over-httpstls-configuration)
  - [Preventing DNS Leaks & Bypasses](#preventing-dns-leaks--bypasses)
  - [DNS Performance Optimization](#dns-performance-optimization)
  - [AdGuard Home (If You Have RAM to Spare)](#adguard-home-if-you-have-ram-to-spare)
- [SQM/QoS Configuration for Optimal Performance](#sqmqos-configuration-for-optimal-performance)
  - [Basic SQM Setup for E8450](#basic-sqm-setup-for-e8450)
  - [cake vs fq_codel on E8450](#cake-vs-fq_codel-on-e8450)
  - [Gaming and Latency Optimization](#gaming-and-latency-optimization)
  - [Per-Device Bandwidth Limits](#per-device-bandwidth-limits)
  - [Bufferbloat Testing and Tuning](#bufferbloat-testing-and-tuning)
- [IPv6 Configuration for Native IPv6 ISPs with CGNAT](#ipv6-configuration-for-native-ipv6-isps-with-cgnat)
  - [Understanding CGNAT + IPv6 Native Setup](#understanding-cgnat--ipv6-native-setup)
  - [Basic IPv6 Configuration](#basic-ipv6-configuration)
  - [CGNAT Workarounds and Optimizations](#cgnat-workarounds-and-optimizations)
  - [DS-Lite Configuration](#ds-lite-configuration)
  - [IPv6 Firewall Best Practices](#ipv6-firewall-best-practices)
  - [IPv6 Performance Tuning](#ipv6-performance-tuning)
  - [Testing and Troubleshooting IPv6](#testing-and-troubleshooting-ipv6)
  - [464XLAT Support (For IPv6-Only Networks)](#464xlat-support-for-ipv6-only-networks)
- [Mesh Networking with E8450](#mesh-networking-with-e8450)
  - [Mesh Technologies Comparison](#mesh-technologies-comparison)
  - [WDS Mesh Setup (Recommended for Simplicity)](#wds-mesh-setup-recommended-for-simplicity)
  - [802.11s Mesh Configuration](#80211s-mesh-configuration)
  - [Performance Tips for Mesh Networks](#performance-tips-for-mesh-networks)
  - [Common Mesh Issues and Solutions](#common-mesh-issues-and-solutions)
  - [Mesh Stability Best Practices](#mesh-stability-best-practices)
  - [Alternative: Batman-adv for Large Networks](#alternative-batman-adv-for-large-networks)
- [Popular Add-on Services & Creative Uses](#popular-add-on-services--creative-uses)
  - [Network-wide VPN Client](#network-wide-vpn-client)
  - [Home Automation Hub](#home-automation-hub)
  - [Network Storage & Media Services](#network-storage--media-services)
  - [Advanced Network Monitoring](#advanced-network-monitoring)
  - [Dynamic DNS for CGNAT Bypass](#dynamic-dns-for-cgnat-bypass)
  - [Parental Controls & Access Management](#parental-controls--access-management)
  - [Wake-on-LAN Gateway](#wake-on-lan-gateway)
  - [USB LTE/5G Failover](#usb-lte5g-failover)
  - [Container Services (Advanced)](#container-services-advanced)
  - [Traffic Analysis & Security](#traffic-analysis--security)
  - [Time Services](#time-services)
  - [Development & Testing](#development--testing)


### **Troubleshooting, Tips, and Known Issues**

This section compiles the most common problems and solutions discussed in the forum.

#### **Critical Issue: The "Reboot to Recovery" Loop**

*   **Symptom:** Your router unexpectedly reboots and comes up in `initramfs` recovery mode. The 5GHz radio is missing, and your configuration is gone.
*   **Cause:** This is a **feature, not a bug**. The UBI bootloader is configured to check for kernel crash logs in `/sys/fs/pstore/` on boot. If logs are found, it boots into the recovery partition to prevent a boot loop and allow for debugging.
*   **Immediate Fix:** The crash logs are stored in RAM. A **cold boot** (unplugging the power for 30 seconds and plugging it back in) will clear the logs and the router will boot normally. Alternatively, if you can access the recovery system via SSH, you can run `rm /sys/fs/pstore/*` and then `reboot`.
*   **Advanced/Permanent Fix:** If you prefer stability over crash reporting, you can modify the bootloader's behavior to ignore the pstore. This is an advanced procedure. SSH into the router and run:
    ```bash
    fw_setenv bootcmd "run boot_ubi"
    ```
    This tells the bootloader to always boot the main UBI partition, bypassing the recovery check.

#### **Critical Issue: I/O Errors on `/dev/mtdblock2`**

*   **Symptom:** You see `blk_update_request: I/O error, dev mtdblock2` in `dmesg` or when trying to back up the factory partition.
*   **Cause:** The new SPI-NAND driver is more stringent about ECC (Error Correction Code) than the factory driver. The factory partition contains areas without proper ECC data. The new driver correctly identifies and reports these as read errors.
*   **Solution:** **Ignore them.** Daniel, the developer, has confirmed these errors are harmless and relate to unused parts of the partition. Your device is not faulty.

#### **Tips for Maximum Stability**

*   **Enable IRQBalance:** To improve performance under load (especially with Gigabit connections), install the `irqbalance` package and enable it.
*   **802.11r (Fast Roaming):** This can be unstable, particularly with Apple devices, causing `STA-OPMODE-N_SS-CHANGED` log spam and disconnects. If you experience this, try disabling "Disassociate on Low Acknowledgement" in the advanced wireless settings for the relevant interface. If problems persist, disable 802.11r.
*   **Hardware Flow Offloading:** While tempting for performance, it has been reported to cause instability and issues with IPv6. For maximum reliability, leave it **disabled**. Software Flow Offloading is a safer alternative if needed.
*   **Keep a Known-Good Firmware Version:** Before trying a new snapshot or major upgrade, make a note of your current stable version number. If you run into trouble, you can easily flash back to it.

### **Frequently Asked Questions (FAQs) - E8450 Edition**

*   **Q: Why can't I just flash a standard OpenWrt sysupgrade image from the stock Belkin/Linksys firmware?**
    *   A: Because of the new, more accurate NAND driver in recent OpenWrt versions. It will fail to read the factory calibration data correctly, leading to non-functional radios. You **must** use the `dangowrt` UBI installer first, which rewrites this data with correct ECC, making it readable by modern OpenWrt.

*   **Q: I think my device is bricked (blinking light, no ping). What do I do?**
    *   A: First, attempt TFTP recovery. The device will look for a server at `192.168.1.254`. You'll need to serve the `...-initramfs-recovery.itb` file. If that fails, you will need a USB-to-serial adapter to access the bootloader console and diagnose the issue.

*   **Q: Is 160MHz channel width completely unusable?**
    *   A: It's not *unusable*, but it is *unreliable* for many users, especially in mesh/WDS configurations. The hardware itself has limitations (2T2R on HE160), and it appears to be a source of driver instability. For a "set it and forget it" reliable network, 80MHz is the recommended setting.

### **OpenWrt 24.10.x Specific Issues and Solutions**

#### **Attended Sysupgrade Issues**

*   **Problem:** Attended sysupgrade fails on 24.10.0 with build errors
*   **Solution:** Use manual sysupgrade or upgrade to 24.10.2 where this is fixed. The issue was related to package dependency resolution in the build system.

#### **WDS Configuration Changes**

*   **Change:** Starting with 24.10.x, WDS configuration requires explicit mesh point setup
*   **Configuration:** For WDS backhaul between routers:
    ```
    config wifi-iface 'default_radio1'
        option device 'radio1'
        option mode 'ap'
        option wds '1'
        option network 'lan'
        option encryption 'sae-mixed'
        option key 'your-password'
    ```
*   **Note:** Ensure both APs use the same channel and encryption settings. SAE-mixed provides better compatibility than pure WPA3.

#### **Package Dependencies**

*   **owut Tool:** Now requires explicit installation of `ucert` package for firmware verification
*   **LuCI Attended Sysupgrade:** Requires `rpcd-mod-rpcsys` which may not be installed by default on minimal builds

### **Memory Management & OOM Prevention**

#### **Understanding Memory Pressure**

*   **Issue:** E8450 has 512MB RAM, which can be tight when running multiple services
*   **Common Memory Hogs:** 
    - AdGuard Home: 100-150MB
    - WireGuard/Tailscale: 50-70MB
    - LuCI with SSL: 30-40MB
    - SQM/QoS: 20-30MB per instance

#### **Zram-Swap Configuration**

*   **Installation and Setup:**
    ```bash
    opkg install zram-swap
    uci set system.@system[0].zram_size_mb='256'
    uci set system.@system[0].zram_comp_algo='lz4'
    uci commit system
    /etc/init.d/zram start
    /etc/init.d/zram enable
    ```
*   **Benefits:** Provides compressed swap in RAM, effectively giving 1.5-2x usable memory
*   **Trade-off:** Slight CPU overhead, but MediaTek MT7622 handles it well

#### **Memory Optimization Tips**

*   **Disable Unused Services:**
    ```bash
    # Common services to consider disabling if not needed
    /etc/init.d/odhcpd disable  # If not using IPv6
    /etc/init.d/vnstat disable  # If not monitoring bandwidth
    ```
*   **Use Lightweight Alternatives:**
    - Replace AdGuard Home with simple-adblock (saves ~100MB)
    - Use dropbear instead of openssh-server
    - Consider removing LuCI for CLI-only management (saves 30-40MB)
*   **Monitor Memory Usage:**
    ```bash
    # Check memory status
    free -m
    # See top memory consumers
    ps | awk '{print $5 " " $1 " " $9}' | sort -rn | head -10
    ```

### **WiFi 6 (802.11ax) Performance Optimization**

#### **Country Code and Regulatory Settings**

*   **Best Performance Countries:**
    - `US`: Good balance of channels and power limits (30dBm on 2.4GHz, 23dBm on 5GHz)
    - `BO` (Bolivia): Maximum allowed power on all bands (often 30dBm)
    - `PA` (Panama): Similar to BO with relaxed limits
*   **Configuration:**
    ```bash
    uci set wireless.radio0.country='US'
    uci set wireless.radio1.country='US'
    uci commit wireless
    wifi reload
    ```
*   **Warning:** Using incorrect country codes may violate local regulations

#### **802.11ax Specific Optimizations**

*   **Enable Key Features:**
    ```bash
    # For 5GHz radio (radio1)
    uci set wireless.radio1.he_mu_beamformer='1'
    uci set wireless.radio1.he_su_beamformer='1'
    uci set wireless.radio1.he_bss_color='128'  # Reduces interference
    uci set wireless.radio1.he_spr_sr_control='3'  # Spatial reuse
    ```
*   **OFDMA Settings:**
    - Enable for high-density environments with many clients
    - Disable for single/few client scenarios for lower latency
    ```bash
    # Enable OFDMA (good for many clients)
    uci set wireless.radio1.he_default_pe_duration='4'
    uci set wireless.radio1.ofdma_dl='1'
    uci set wireless.radio1.ofdma_ul='1'
    ```

#### **Power Save and Battery Device Optimization**

*   **Beacon and DTIM Settings:**
    ```bash
    # Balanced settings for mixed devices
    uci set wireless.default_radio0.beacon_int='100'  # Default
    uci set wireless.default_radio0.dtim_period='2'   # Good for most devices
    
    # For IoT/battery devices, increase DTIM
    uci set wireless.default_radio0.dtim_period='3'   # Better battery life
    ```
*   **Target Wake Time (TWT) for WiFi 6:**
    ```bash
    uci set wireless.radio1.he_twt_required='1'
    ```
    - Significantly improves battery life for WiFi 6 capable devices
    - May cause issues with older Intel AX200/AX201 drivers

#### **Channel Width Recommendations**

*   **2.4GHz Band:** Always use 20MHz (40MHz causes interference)
*   **5GHz Band:** 
    - 80MHz: Recommended for stability and compatibility
    - 160MHz: Only if you have WiFi 6E clients and clean spectrum
    - Avoid DFS channels (52-144) if stability is priority

### **Advanced Network Segmentation with VLANs**

#### **Guest Network with Proper Isolation**

*   **Basic Guest Network Setup:**
    ```bash
    # Create guest network interface
    uci set network.guest=interface
    uci set network.guest.proto='static'
    uci set network.guest.ipaddr='192.168.2.1'
    uci set network.guest.netmask='255.255.255.0'
    
    # Create guest DHCP
    uci set dhcp.guest=dhcp
    uci set dhcp.guest.interface='guest'
    uci set dhcp.guest.start='100'
    uci set dhcp.guest.limit='150'
    uci set dhcp.guest.leasetime='1h'
    
    # Guest WiFi
    uci set wireless.guest_radio0=wifi-iface
    uci set wireless.guest_radio0.device='radio0'
    uci set wireless.guest_radio0.network='guest'
    uci set wireless.guest_radio0.mode='ap'
    uci set wireless.guest_radio0.ssid='Guest-WiFi'
    uci set wireless.guest_radio0.encryption='psk2'
    uci set wireless.guest_radio0.key='guestpassword'
    uci set wireless.guest_radio0.isolate='1'  # Client isolation
    ```

*   **Firewall Zone for Guest Isolation:**
    ```bash
    # Guest zone with internet only
    uci add firewall zone
    uci set firewall.@zone[-1].name='guest'
    uci set firewall.@zone[-1].network='guest'
    uci set firewall.@zone[-1].input='REJECT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].forward='REJECT'
    
    # Allow guest to WAN only
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='guest'
    uci set firewall.@forwarding[-1].dest='wan'
    
    # Allow DHCP/DNS for guest
    uci add firewall rule
    uci set firewall.@rule[-1].name='Guest-DHCP-DNS'
    uci set firewall.@rule[-1].src='guest'
    uci set firewall.@rule[-1].dest_port='53 67 68'
    uci set firewall.@rule[-1].target='ACCEPT'
    ```

#### **IoT VLAN Segregation**

*   **VLAN Configuration for IoT Devices:**
    ```bash
    # Create VLAN 10 for IoT
    uci set network.iot=interface
    uci set network.iot.proto='static'
    uci set network.iot.device='br-lan.10'
    uci set network.iot.ipaddr='192.168.10.1'
    uci set network.iot.netmask='255.255.255.0'
    
    # Configure bridge VLAN filtering (DSA)
    uci set network.@device[0].ports='lan1 lan2 lan3 lan4'
    uci set network.@device[0].bridge_vlan='1'
    
    # Tag VLAN 10 on specific ports
    uci add network bridge-vlan
    uci set network.@bridge-vlan[-1].device='br-lan'
    uci set network.@bridge-vlan[-1].vlan='10'
    uci set network.@bridge-vlan[-1].ports='lan1:t lan2:t'  # Tagged on ports 1-2
    ```

*   **IoT Firewall Rules:**
    ```bash
    # IoT zone - no internet by default
    uci add firewall zone
    uci set firewall.@zone[-1].name='iot'
    uci set firewall.@zone[-1].network='iot'
    uci set firewall.@zone[-1].input='REJECT'
    uci set firewall.@zone[-1].output='REJECT'
    uci set firewall.@zone[-1].forward='REJECT'
    
    # Allow specific IoT devices internet (by MAC)
    uci add firewall rule
    uci set firewall.@rule[-1].name='IoT-Device-Internet'
    uci set firewall.@rule[-1].src='iot'
    uci set firewall.@rule[-1].src_mac='AA:BB:CC:DD:EE:FF'
    uci set firewall.@rule[-1].dest='wan'
    uci set firewall.@rule[-1].target='ACCEPT'
    ```

#### **Multiple SSIDs with Different Zones**

*   **Performance Impact:** Each additional SSID uses ~5-10MB RAM and some CPU
*   **Practical Limit:** 4 SSIDs per radio (8 total) before noticeable performance degradation
*   **Best Practice:** Use VLANs over wireless backhaul with WDS:
    ```bash
    # Enable VLAN tagging on WDS link
    uci set wireless.default_radio1.wds='1'
    uci set wireless.default_radio1.network='lan'
    
    # Bridge configuration for VLAN over WDS
    uci set network.@device[0].ports='lan1 lan2 lan3 lan4 wlan1'
    ```

### **Release Selection for Maximum Stability**

#### **Most Stable Releases (Community Consensus)**

*   **Golden Releases:**
    - **23.05.5**: Most stable overall, excellent for production use
    - **22.03.7**: Rock-solid but lacks newer features, good for "set and forget"
    - **24.10.2**: Current stable with good stability after .1 bug fixes
*   **Avoid:**
    - **.0 releases**: Always wait for .1 or .2 point releases
    - **Snapshots**: Only for testing, kernel modules break frequently
    - **RC (Release Candidates)**: May have unresolved issues

#### **Stability Best Practices**

*   **Update Strategy:**
    ```bash
    # Before any major update
    1. Wait 2-4 weeks after release for community feedback
    2. Check forum for E8450-specific issues
    3. Test on non-critical device first (secondary-ap before primary-ap)
    4. Keep previous firmware file for rollback
    ```

*   **Configuration for Stability:**
    - Disable hardware flow offloading (known to cause random reboots)
    - Use software flow offloading instead if needed
    - Avoid experimental features (WED, 802.11r with certain clients)
    - Stick to 80MHz channel width on 5GHz
    - Don't use DFS channels unless necessary

*   **Package Management:**
    ```bash
    # Only upgrade packages when necessary
    # Avoid blind "opkg upgrade" on all packages
    # Instead, upgrade selectively:
    opkg update
    opkg list-upgradable
    # Only upgrade specific packages with known fixes
    ```

#### **Known Stable Configurations**

*   **Conservative Setup (Maximum Uptime):**
    - OpenWrt 23.05.5
    - No flow offloading
    - 80MHz channels only
    - Basic packages only (no AdGuard, minimal services)
    - Uptime reports: 6+ months without issues

*   **Balanced Setup (Features + Stability):**
    - OpenWrt 24.10.2+
    - Software flow offloading enabled
    - Essential packages: SQM, WireGuard, DNS over HTTPS
    - Weekly auto-reboot via cron (prevents memory leaks)
    ```bash
    # Add weekly reboot for stability
    echo "0 4 * * 0 /sbin/reboot" >> /etc/crontabs/root
    /etc/init.d/cron restart
    ```

### **DNS and Ad-blocking Solutions**

#### **Ad-blocking Comparison for E8450**

*   **Memory Usage & Performance:**
    - **simple-adblock**: ~5-10MB RAM, minimal CPU, handles 100k+ domains easily
    - **adblock**: ~10-15MB RAM, more features than simple-adblock
    - **AdGuard Home**: 100-150MB RAM, heavy but feature-rich
    - **Pi-hole**: Not recommended (requires Docker, too heavy)

*   **Recommended: simple-adblock + https-dns-proxy**
    ```bash
    # Lightweight setup that works well
    opkg install simple-adblock luci-app-simple-adblock
    opkg install https-dns-proxy luci-app-https-dns-proxy
    
    # Configure simple-adblock
    uci set simple-adblock.config.enabled='1'
    uci set simple-adblock.config.dns='dnsmasq.servers'
    uci set simple-adblock.config.force_dns='1'  # Prevent DNS bypass
    uci commit simple-adblock
    /etc/init.d/simple-adblock start
    ```

#### **DNS over HTTPS/TLS Configuration**

*   **Using https-dns-proxy (Recommended):**
    ```bash
    # Install and configure
    opkg install https-dns-proxy
    
    # Configure for Cloudflare
    uci set https-dns-proxy.@https-dns-proxy[0].bootstrap_dns='1.1.1.1,8.8.8.8'
    uci set https-dns-proxy.@https-dns-proxy[0].resolver_url='https://cloudflare-dns.com/dns-query'
    uci set https-dns-proxy.@https-dns-proxy[0].listen_addr='127.0.0.1'
    uci set https-dns-proxy.@https-dns-proxy[0].listen_port='5053'
    
    # Point dnsmasq to use it
    uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5053'
    uci set dhcp.@dnsmasq[0].noresolv='1'  # Don't use ISP DNS
    uci commit
    /etc/init.d/dnsmasq restart
    /etc/init.d/https-dns-proxy restart
    ```

*   **Alternative: Stubby (DNS over TLS):**
    ```bash
    # More stable but slightly more RAM
    opkg install stubby
    uci set stubby.global.listen_address='127.0.0.1@5453'
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5453'
    ```

#### **Preventing DNS Leaks & Bypasses**

*   **Force All DNS Through Router:**
    ```bash
    # Redirect all DNS queries to router
    uci add firewall redirect
    uci set firewall.@redirect[-1].name='Intercept-DNS'
    uci set firewall.@redirect[-1].src='lan'
    uci set firewall.@redirect[-1].src_dport='53'
    uci set firewall.@redirect[-1].proto='tcp udp'
    uci set firewall.@redirect[-1].target='DNAT'
    uci set firewall.@redirect[-1].dest_port='53'
    
    # Block DoH bypass attempts (common DoH IPs)
    uci add firewall rule
    uci set firewall.@rule[-1].name='Block-DoH'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest='wan'
    uci set firewall.@rule[-1].dest_port='443'
    uci set firewall.@rule[-1].dest_ip='1.1.1.1 8.8.8.8 8.8.4.4'
    uci set firewall.@rule[-1].target='REJECT'
    ```

#### **DNS Performance Optimization**

*   **Dnsmasq Caching:**
    ```bash
    # Increase cache size for better performance
    uci set dhcp.@dnsmasq[0].cachesize='10000'  # Default is 150
    uci set dhcp.@dnsmasq[0].min_cache_ttl='3600'  # Cache for minimum 1 hour
    
    # Prefetch popular domains
    uci set dhcp.@dnsmasq[0].prefetch='1'
    
    # Use all servers and pick fastest
    uci set dhcp.@dnsmasq[0].all_servers='1'
    uci commit dhcp
    /etc/init.d/dnsmasq restart
    ```

*   **Parallel DNS Queries:**
    ```bash
    # Add multiple upstream servers for redundancy
    uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5053'  # DoH primary
    uci add_list dhcp.@dnsmasq[0].server='9.9.9.9'  # Quad9 backup
    uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'  # Cloudflare backup
    ```

#### **AdGuard Home (If You Have RAM to Spare)**

*   **Installation:**
    ```bash
    # Only if you have 200MB+ free RAM
    opkg install adguardhome
    
    # Disable dnsmasq DNS (keep DHCP)
    uci set dhcp.@dnsmasq[0].port='0'
    uci commit dhcp
    /etc/init.d/dnsmasq restart
    
    # Configure AdGuard to listen on port 53
    # Access web UI at http://router-ip:3000
    ```

*   **Memory Optimization for AdGuard:**
    - Set query log to 24 hours only
    - Limit statistics to 7 days
    - Use optimized blocklists (OISD Basic)
    - Disable unnecessary features (DHCP, filtering for specific clients)

### **SQM/QoS Configuration for Optimal Performance**

#### **Basic SQM Setup for E8450**

*   **Installation and Initial Config:**
    ```bash
    opkg install sqm-scripts luci-app-sqm
    
    # Basic setup for 100/20 Mbps connection
    uci set sqm.@queue[0]=queue
    uci set sqm.@queue[0].enabled='1'
    uci set sqm.@queue[0].interface='eth0'  # WAN interface
    uci set sqm.@queue[0].download='95000'  # 95% of download speed
    uci set sqm.@queue[0].upload='19000'    # 95% of upload speed
    uci commit sqm
    /etc/init.d/sqm start
    ```

*   **Bandwidth Settings Formula:**
    - Set to 85-95% of actual speeds for best bufferbloat control
    - For DOCSIS/Cable: Use 85% (more variable)
    - For Fiber: Use 90-95% (more stable)
    - For DSL: Use 85-90% (account for overhead)

#### **cake vs fq_codel on E8450**

*   **Performance Comparison:**
    - **cake**: Better fairness, more CPU (~15-20% at 500Mbps)
    - **fq_codel**: Lower CPU usage (~10-15% at 500Mbps)
    - **E8450 can handle**: ~600Mbps with cake, ~800Mbps with fq_codel

*   **Recommended cake Configuration:**
    ```bash
    # For most connections (best balance)
    uci set sqm.@queue[0].qdisc='cake'
    uci set sqm.@queue[0].script='piece_of_cake.qos'
    uci set sqm.@queue[0].qdisc_advanced='1'
    uci set sqm.@queue[0].squash_dscp='1'
    uci set sqm.@queue[0].squash_ingress='1'
    uci set sqm.@queue[0].ingress_ecn='ECN'
    uci set sqm.@queue[0].egress_ecn='ECN'
    uci set sqm.@queue[0].qdisc_really_really_advanced='1'
    uci set sqm.@queue[0].iqdisc_opts='nat dual-dsthost'
    uci set sqm.@queue[0].eqdisc_opts='nat dual-srchost'
    ```

*   **Connection-Specific Settings:**
    ```bash
    # For Cable/DOCSIS
    uci set sqm.@queue[0].iqdisc_opts='nat dual-dsthost docsis ack-filter'
    
    # For DSL/PPPoE  
    uci set sqm.@queue[0].overhead='44'
    uci set sqm.@queue[0].linklayer='atm'
    
    # For Fiber
    uci set sqm.@queue[0].overhead='44'
    uci set sqm.@queue[0].linklayer='ethernet'
    ```

#### **Gaming and Latency Optimization**

*   **DSCP Marking for Gaming:**
    ```bash
    # Mark gaming traffic as CS4 (high priority)
    
    # Console gaming (PlayStation/Xbox)
    uci add firewall rule
    uci set firewall.@rule[-1].name='Gaming-DSCP'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].src_ip='192.168.1.50'  # Gaming device IP
    uci set firewall.@rule[-1].dest='wan'
    uci set firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].set_dscp='CS4'
    uci set firewall.@rule[-1].target='DSCP'
    
    # PC gaming ports
    uci add firewall rule
    uci set firewall.@rule[-1].name='PC-Gaming-DSCP'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest='wan'
    uci set firewall.@rule[-1].dest_port='27015-27030 25565'  # Steam, Minecraft
    uci set firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].set_dscp='CS4'
    uci set firewall.@rule[-1].target='DSCP'
    ```

*   **cake Tin Configuration for Gaming:**
    ```bash
    # Use diffserv4 for gaming priority
    uci set sqm.@queue[0].qdisc_opts='diffserv4 nat dual-dsthost'
    uci set sqm.@queue[0].eqdisc_opts='diffserv4 nat dual-srchost'
    
    # Tin allocation (Voice, Video, Best Effort, Bulk)
    # Gaming traffic marked as CS4 goes to Voice tin (lowest latency)
    ```

#### **Per-Device Bandwidth Limits**

*   **Using nft-qos (Recommended):**
    ```bash
    opkg install nft-qos luci-app-nft-qos
    
    # Limit specific device
    uci set nft-qos.default=global
    uci set nft-qos.default.enable='1'
    
    # Add device limit
    uci add nft-qos limit
    uci set nft-qos.@limit[-1].enable='1'
    uci set nft-qos.@limit[-1].type='mac'
    uci set nft-qos.@limit[-1].mac='AA:BB:CC:DD:EE:FF'
    uci set nft-qos.@limit[-1].download='50'  # Mbps
    uci set nft-qos.@limit[-1].upload='10'     # Mbps
    uci commit nft-qos
    /etc/init.d/nft-qos restart
    ```

#### **Bufferbloat Testing and Tuning**

*   **Testing Tools:**
    - Waveform Bufferbloat Test: https://www.waveform.com/tools/bufferbloat
    - DSLReports Speed Test: http://www.dslreports.com/speedtest
    - Fast.com (with latency): https://fast.com (click "Show more info")

*   **Tuning Process:**
    ```bash
    # 1. Start with 85% of speeds
    # 2. Test bufferbloat
    # 3. If grade A+: Increase by 5%
    # 4. If grade B or worse: Decrease by 5%
    # 5. Repeat until optimal
    
    # Quick adjustment
    uci set sqm.@queue[0].download='90000'  # Adjust value
    uci commit sqm
    /etc/init.d/sqm restart
    ```

*   **CPU Usage Monitoring:**
    ```bash
    # Check SQM CPU impact
    top -d 1 | grep -E "si|sirq"
    
    # If CPU >80% during speed test, consider:
    # 1. Switch from cake to fq_codel
    # 2. Disable SQM on LAN-to-LAN traffic
    # 3. Use simpler cake options (no nat, no dual-host)
    ```

### **IPv6 Configuration for Native IPv6 ISPs with CGNAT**

#### **Understanding CGNAT + IPv6 Native Setup**

*   **Common ISP Configurations:**
    - IPv6 native with /56 or /48 prefix delegation
    - IPv4 via CGNAT (Carrier Grade NAT) - shared public IP
    - DS-Lite (Dual Stack Lite) - IPv4 over IPv6 tunnel
    - 464XLAT - IPv4 translation over IPv6

*   **E8450 Capabilities:**
    - Full IPv6 support with prefix delegation
    - Hardware NAT acceleration works with IPv6
    - Can handle multiple /64 subnets efficiently

#### **Basic IPv6 Configuration**

*   **WAN6 Interface Setup:**
    ```bash
    # DHCPv6 client configuration
    uci set network.wan6=interface
    uci set network.wan6.device='eth0'
    uci set network.wan6.proto='dhcpv6'
    uci set network.wan6.reqaddress='try'
    uci set network.wan6.reqprefix='auto'
    uci set network.wan6.peerdns='0'  # Use your own DNS
    
    # Request prefix delegation
    uci set network.wan6.ip6prefix='1'
    uci commit network
    ```

*   **LAN IPv6 Distribution:**
    ```bash
    # Configure LAN for IPv6
    uci set network.lan.ip6assign='64'  # Assign /64 from delegated prefix
    uci set network.lan.ip6hint='0'     # Use first /64 subnet
    
    # Enable router advertisements
    uci set dhcp.lan.ra='server'
    uci set dhcp.lan.ra_management='1'
    uci set dhcp.lan.ra_default='1'
    uci set dhcp.lan.dhcpv6='server'
    uci set dhcp.lan.ra_flags='managed-config other-config'
    
    # DNS for IPv6
    uci add_list dhcp.lan.dns='2606:4700:4700::1111'  # Cloudflare
    uci add_list dhcp.lan.dns='2001:4860:4860::8888'  # Google
    uci commit dhcp
    ```

#### **CGNAT Workarounds and Optimizations**

*   **Port Forwarding Alternatives:**
    ```bash
    # Since CGNAT blocks incoming connections, use:
    
    # 1. IPv6 for direct access (if ISP allows)
    # Allow SSH on IPv6
    uci add firewall rule
    uci set firewall.@rule[-1].name='Allow-SSH-IPv6'
    uci set firewall.@rule[-1].src='wan6'
    uci set firewall.@rule[-1].dest_port='22'
    uci set firewall.@rule[-1].proto='tcp'
    uci set firewall.@rule[-1].family='ipv6'
    uci set firewall.@rule[-1].target='ACCEPT'
    
    # 2. Tailscale/ZeroTier for remote access
    # Works through CGNAT without port forwarding
    opkg install tailscale
    tailscale up --advertise-routes=192.168.1.0/24
    ```

*   **MTU Optimization for IPv6:**
    ```bash
    # IPv6 requires larger MTU, especially with tunneling
    uci set network.wan6.mtu='1492'  # For PPPoE
    uci set network.wan6.mtu='1500'  # For DHCP
    
    # Enable MTU discovery
    uci set network.@globals[0].packet_steering='1'
    uci set network.@globals[0].tcp_mtu_probing='1'
    ```

#### **DS-Lite Configuration**

*   **For ISPs using DS-Lite (IPv4 over IPv6):**
    ```bash
    # Install DS-Lite support
    opkg install ds-lite
    
    # Configure DS-Lite tunnel
    uci set network.dslite=interface
    uci set network.dslite.proto='dslite'
    uci set network.dslite.peeraddr='aftr.isp.example.com'  # ISP's AFTR address
    uci set network.dslite.tunlink='wan6'
    
    # Update firewall
    uci add_list firewall.@zone[1].network='dslite'
    uci commit
    /etc/init.d/network restart
    ```

#### **IPv6 Firewall Best Practices**

*   **Secure Default Configuration:**
    ```bash
    # Default IPv6 firewall zone
    uci set firewall.@zone[1].name='wan6'
    uci set firewall.@zone[1].network='wan6'
    uci set firewall.@zone[1].input='REJECT'
    uci set firewall.@zone[1].output='ACCEPT'
    uci set firewall.@zone[1].forward='REJECT'
    uci set firewall.@zone[1].masq='0'  # No NAT for IPv6
    
    # Allow essential ICMPv6
    uci add firewall rule
    uci set firewall.@rule[-1].name='Allow-ICMPv6-Input'
    uci set firewall.@rule[-1].src='wan6'
    uci set firewall.@rule[-1].proto='icmp'
    uci set firewall.@rule[-1].icmp_type='echo-request echo-reply destination-unreachable packet-too-big time-exceeded parameter-problem'
    uci set firewall.@rule[-1].family='ipv6'
    uci set firewall.@rule[-1].target='ACCEPT'
    
    # Allow DHCPv6
    uci add firewall rule
    uci set firewall.@rule[-1].name='Allow-DHCPv6'
    uci set firewall.@rule[-1].src='wan6'
    uci set firewall.@rule[-1].dest_port='546'
    uci set firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].family='ipv6'
    uci set firewall.@rule[-1].target='ACCEPT'
    ```

#### **IPv6 Performance Tuning**

*   **Enable Hardware Offloading for IPv6:**
    ```bash
    # Software flow offloading works well with IPv6
    uci set firewall.@defaults[0].flow_offloading='1'
    uci set firewall.@defaults[0].flow_offloading_hw='0'  # Keep HW offload disabled
    
    # IPv6 specific optimizations
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.route.max_size=16384" >> /etc/sysctl.conf
    sysctl -p
    ```

#### **Testing and Troubleshooting IPv6**

*   **Verification Commands:**
    ```bash
    # Check IPv6 connectivity
    ping6 -c 4 google.com
    
    # Check prefix delegation
    ip -6 addr show
    ip -6 route show
    
    # Check router advertisements
    rdisc6 br-lan
    
    # Monitor DHCPv6
    logread -f | grep -i dhcpv6
    ```

*   **Common Issues and Fixes:**
    ```bash
    # Issue: No IPv6 on LAN clients
    # Fix: Ensure RA server is enabled
    uci set dhcp.lan.ra='server'
    uci set dhcp.lan.dhcpv6='server'
    /etc/init.d/odhcpd restart
    
    # Issue: Slow IPv6 (Happy Eyeballs issues)
    # Fix: Prefer IPv4 for dual-stack
    echo "precedence ::ffff:0:0/96 100" >> /etc/gai.conf
    
    # Issue: IPv6 DNS not working
    # Fix: Force IPv6 DNS servers
    uci set dhcp.lan.dns_service='0'  # Disable DNS service flag
    uci add_list dhcp.lan.dns='2606:4700:4700::1111'
    ```

#### **464XLAT Support (For IPv6-Only Networks)**

*   **Enabling 464XLAT for IPv4 compatibility:**
    ```bash
    # Install 464XLAT support
    opkg install 464xlat
    
    # Configure CLAT interface
    uci set network.clat=interface
    uci set network.clat.proto='464xlat'
    uci set network.clat.tunlink='wan6'
    uci set network.clat.ip6prefix='64:ff9b::/96'  # Well-known prefix
    
    # Add to firewall
    uci add_list firewall.@zone[0].network='clat'
    uci commit
    /etc/init.d/network restart
    ```

### **Mesh Networking with E8450**

#### **Mesh Technologies Comparison**

*   **Available Options on E8450:**
    - **WDS (Wireless Distribution System)**: Simple, stable, but proprietary
    - **802.11s**: Standard mesh protocol, more complex
    - **Batman-adv**: Layer 2 mesh, good for larger networks
    - **EasyMesh**: New standard, limited support in OpenWrt

*   **Community Consensus:**
    - **WDS**: Most reliable for 2-3 node setups
    - **802.11s**: Better for 4+ nodes but needs tuning
    - **Avoid mixing**: Pick one technology and stick with it

#### **WDS Mesh Setup (Recommended for Simplicity)**

*   **Main Router (primary-ap) Configuration:**
    ```bash
    # Configure 5GHz for WDS backhaul
    uci set wireless.radio1.channel='36'  # Fixed channel required
    uci set wireless.radio1.htmode='HE80'  # 80MHz for stability
    uci set wireless.radio1.country='US'
    
    # Create WDS AP interface
    uci set wireless.wds_ap=wifi-iface
    uci set wireless.wds_ap.device='radio1'
    uci set wireless.wds_ap.network='lan'
    uci set wireless.wds_ap.mode='ap'
    uci set wireless.wds_ap.ssid='WDS-Backhaul'
    uci set wireless.wds_ap.encryption='sae-mixed'  # WPA3/WPA2
    uci set wireless.wds_ap.key='strong-wds-password'
    uci set wireless.wds_ap.wds='1'
    uci set wireless.wds_ap.hidden='1'  # Hide SSID
    uci set wireless.wds_ap.isolate='0'
    uci commit wireless
    ```

*   **Secondary Router (secondary-ap) Configuration:**
    ```bash
    # Disable DHCP server
    uci set dhcp.lan.ignore='1'
    uci commit dhcp
    /etc/init.d/dnsmasq restart
    
    # Set static IP in same subnet
    uci set network.lan.ipaddr='192.168.1.2'
    uci set network.lan.gateway='192.168.1.1'
    uci set network.lan.dns='192.168.1.1'
    
    # Configure WDS client
    uci set wireless.radio1.channel='36'  # Same as main
    uci set wireless.wds_sta=wifi-iface
    uci set wireless.wds_sta.device='radio1'
    uci set wireless.wds_sta.network='lan'
    uci set wireless.wds_sta.mode='sta'
    uci set wireless.wds_sta.ssid='WDS-Backhaul'
    uci set wireless.wds_sta.encryption='sae-mixed'
    uci set wireless.wds_sta.key='strong-wds-password'
    uci set wireless.wds_sta.wds='1'
    uci commit
    wifi reload
    ```

#### **802.11s Mesh Configuration**

*   **For More Complex Deployments:**
    ```bash
    # Install mesh support
    opkg install wpad-mesh-mbedtls mesh11sd
    
    # Configure mesh point on each device
    uci set wireless.mesh=wifi-iface
    uci set wireless.mesh.device='radio1'
    uci set wireless.mesh.mode='mesh'
    uci set wireless.mesh.mesh_id='E8450-Mesh'
    uci set wireless.mesh.encryption='sae'
    uci set wireless.mesh.key='mesh-password'
    uci set wireless.mesh.network='lan'
    uci set wireless.mesh.mesh_fwding='1'
    uci set wireless.mesh.mesh_ttl='5'
    
    # Mesh parameters for stability
    uci set wireless.mesh.mesh_rssi_threshold='-65'
    uci set wireless.mesh.mesh_hwmp_rootmode='2'  # Proactive RANN
    uci set wireless.mesh.mesh_gate_announcements='1'
    ```

*   **802.11s Optimization:**
    ```bash
    # Reduce mesh overhead
    uci set wireless.mesh.mesh_hwmp_rann_interval='5000'
    uci set wireless.mesh.mesh_hwmp_root_interval='5000'
    uci set wireless.mesh.mesh_power_mode='active'  # No power save
    
    # For Apple device compatibility
    uci set wireless.mesh.disassoc_low_ack='0'
    uci set wireless.mesh.skip_inactivity_poll='1'
    ```

#### **Performance Tips for Mesh Networks**

*   **Channel Selection:**
    - Use non-DFS channels (36-48, 149-165) for stability
    - Fixed channel required (no auto)
    - Same channel on all mesh nodes
    - 80MHz recommended (160MHz unstable in mesh)

*   **Backhaul Optimization:**
    ```bash
    # Dedicated backhaul (if you have enough radios)
    # Use 5GHz for backhaul, 2.4GHz for clients
    
    # Increase beacon interval for backhaul
    uci set wireless.wds_ap.beacon_int='200'  # Default 100
    
    # Disable unnecessary features on backhaul
    uci set wireless.wds_ap.wmm='0'  # No QoS on backhaul
    uci set wireless.wds_ap.uapsd='0'  # No power save
    ```

*   **Roaming Configuration:**
    ```bash
    # Enable 802.11k/v for better roaming (NOT 802.11r)
    uci set wireless.default_radio0.ieee80211k='1'
    uci set wireless.default_radio0.ieee80211v='1'
    uci set wireless.default_radio0.bss_transition='1'
    
    # Avoid 802.11r in mesh - causes issues
    uci set wireless.default_radio0.ieee80211r='0'
    ```

#### **Common Mesh Issues and Solutions**

*   **Issue: Mesh Loop/Broadcast Storm**
    ```bash
    # Enable STP on bridge
    uci set network.@device[0].stp='1'
    uci set network.@device[0].forward_delay='2'
    
    # For 802.11s, disable forwarding on one node
    uci set wireless.mesh.mesh_fwding='0'  # On leaf nodes only
    ```

*   **Issue: Poor Mesh Performance**
    ```bash
    # Check mesh status
    iw dev mesh0 station dump
    iw dev mesh0 mpath dump
    
    # Monitor mesh quality
    watch -n 1 'iw dev mesh0 station dump | grep -E "signal|tx bitrate"'
    
    # Adjust RSSI threshold for better peer selection
    uci set wireless.mesh.mesh_rssi_threshold='-70'  # More aggressive
    ```

*   **Issue: Devices Connecting to Wrong Node**
    ```bash
    # Implement band steering
    uci set wireless.default_radio0.rssi_reject_assoc_rssi='-75'
    uci set wireless.default_radio0.rssi_reject_assoc_timeout='5000'
    
    # Or use Dawn for centralized steering
    opkg install dawn luci-app-dawn
    ```

#### **Mesh Stability Best Practices**

*   **Hardware Placement:**
    - Keep mesh nodes within -65dBm signal strength
    - Avoid obstacles between nodes
    - Elevate devices when possible
    - Test with: `iw dev wlan1 station get [MAC] | grep signal`

*   **Firmware Considerations:**
    - All nodes should run same OpenWrt version
    - Update all nodes together
    - Test mesh changes on non-critical nodes first

*   **Monitoring Script:**
    ```bash
    #!/bin/sh
    # Monitor mesh health
    while true; do
        echo "=== Mesh Status $(date) ==="
        iw dev mesh0 station dump | grep -E "Station|signal avg|tx bitrate"
        echo "=== Connected Clients ==="
        iw dev wlan0 station dump | wc -l
        iw dev wlan1 station dump | wc -l
        sleep 60
    done
    ```

#### **Alternative: Batman-adv for Large Networks**

*   **For 5+ Nodes:**
    ```bash
    # Install Batman-adv
    opkg install kmod-batman-adv batctl-full
    
    # Configure Batman interface
    uci set network.bat0=interface
    uci set network.bat0.proto='batadv'
    uci set network.bat0.routing_algo='BATMAN_IV'
    uci set network.bat0.mesh='bat0'
    
    # Add mesh interface to Batman
    uci set network.bat0_hardif=interface
    uci set network.bat0_hardif.proto='batadv_hardif'
    uci set network.bat0_hardif.master='bat0'
    uci set network.bat0_hardif.device='mesh0'
    ```

*   **Batman-adv provides:**
    - Better loop avoidance
    - Multi-path routing
    - Automatic topology management
    - Works well with 802.11s underneath

### **Popular Add-on Services & Creative Uses**

#### **Network-wide VPN Client**

*   **Use Case:** Route all home traffic through VPN for privacy or geo-unblocking
*   **Popular Implementations:**
    - WireGuard client for entire network (low CPU usage)
    - OpenVPN for services that require it
    - Policy-based routing to exclude certain devices (smart TVs, gaming consoles)
*   **Community Notes:** WireGuard handles ~200Mbps on E8450, OpenVPN ~50Mbps

#### **Home Automation Hub**

*   **Use Case:** Central control point for smart home devices
*   **Common Setups:**
    - Mosquitto MQTT broker for IoT communication
    - Zigbee2MQTT with CC2531/CC2652 USB dongles
    - Node-RED for automation flows (requires USB storage)
*   **Benefits:** Reduces cloud dependence, improves IoT response times

#### **Network Storage & Media Services**

*   **Use Case:** Turn router into light NAS/media server
*   **Implementations:**
    - Samba for Windows file sharing via USB drive
    - MiniDLNA for streaming to smart TVs
    - p910nd for network print server
*   **Limitations:** USB 3.0 speeds (~100MB/s), limited to light usage

#### **Advanced Network Monitoring**

*   **Use Case:** Detailed insights into network performance and usage
*   **Popular Tools:**
    - **Netdata**: Real-time performance metrics with web UI
    - **vnstat**: Long-term bandwidth statistics per interface
    - **nlbwmon**: Per-device bandwidth tracking
    - **collectd + InfluxDB**: Time-series metrics for Grafana dashboards
*   **Memory Impact:** Netdata uses 30-50MB RAM, others are lighter

#### **Dynamic DNS for CGNAT Bypass**

*   **Use Case:** Maintain accessible hostname despite changing IPs or CGNAT
*   **Services Used:**
    - Cloudflare (with API token for security)
    - DuckDNS (simple, free)
    - No-IP, DynDNS (traditional providers)
*   **Trick:** Combined with IPv6, allows direct access even behind CGNAT

#### **Parental Controls & Access Management**

*   **Use Case:** Time-based internet access for kids' devices
*   **Features:**
    - Schedule-based WiFi/internet access per MAC address
    - Different rules for weekdays/weekends
    - Bandwidth limits for specific devices
    - Content filtering beyond DNS blocking
*   **Implementation:** Using built-in firewall rules with cron, or luci-app-access-control

#### **Wake-on-LAN Gateway**

*   **Use Case:** Remotely wake computers on home network
*   **Setup Types:**
    - WoL via LuCI interface
    - Automated wake via scripts
    - Integration with home automation
*   **Pro Tip:** Combine with VPN/Tailscale for secure remote wake

#### **USB LTE/5G Failover**

*   **Use Case:** Automatic backup internet when main connection fails
*   **Popular Dongles:**
    - Huawei E3372, E8372 (LTE)
    - Quectel modules via USB adapter
*   **Features:**
    - Automatic failover with mwan3
    - Load balancing between connections
    - SMS notifications on failover events

#### **Container Services (Advanced)**

*   **Use Case:** Run lightweight services in Docker
*   **Requirements:** USB storage for overlay filesystem
*   **Common Containers:**
    - Pi-hole (though AdGuard Home is preferred natively)
    - Homebridge for HomeKit
    - Bitwarden_rs for password management
*   **Warning:** High memory usage, only for advanced users

#### **Traffic Analysis & Security**

*   **Use Case:** Deep packet inspection and security monitoring
*   **Tools:**
    - **Snort** (lightweight IDS/IPS)
    - **BandwidthD** (visual bandwidth usage)
    - **ntopng** (network traffic analysis)
    - **Fail2ban** (SSH brute force protection)
*   **Reality Check:** CPU intensive, may impact routing performance

#### **Time Services**

*   **Use Case:** Accurate network time for all devices
*   **Implementations:**
    - NTP server for local network
    - GPS time via USB GPS dongle
    - Stratum 1 time server setup
*   **Benefit:** Reduces WAN traffic, improves local time accuracy

#### **Development & Testing**

*   **Use Case:** Network testing and development
*   **Tools:**
    - **iperf3 server** for bandwidth testing
    - **tcpdump** for packet capture
    - **nmap** for network scanning
    - **Python/Perl** for custom scripts
*   **Note:** E8450 has enough CPU for light development tasks
