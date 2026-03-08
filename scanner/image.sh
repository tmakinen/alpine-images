#!/bin/sh

chroot_exec apk add \
    nftables \
    sane \
    sane-saned \
    sane-backends

# disable audio, bluetooth and wifi
{
    echo "dtparam=audio=off"
    echo "dtoverlay=disable-bt"
    echo "dtoverlay=disable-wifi"
} >>"${BOOTFS_PATH}/config.txt"

# configure firewall
cat <<EOF >"${ROOTFS_PATH}/etc/nftables.nft"
#!/usr/sbin/nft -f

flush ruleset

table ip filter {
    chain INPUT {
        type filter hook input priority 0; policy accept
        ct state vmap { established : accept, related : accept }
        ip protocol icmp accept
        iifname lo accept
        ip saddr 172.20.24.1/32 tcp dport 22 accept
        ip saddr 172.20.24.2/32 tcp dport 22 accept
        ip saddr 172.20.24.3/32 tcp dport 22 accept
        ip saddr 172.20.24.1/32 tcp dport 6566 accept
        ip saddr 172.20.24.2/32 tcp dport 6566 accept
        ip saddr 172.20.24.3/32 tcp dport 6566 accept
        reject with icmp type host-prohibited
    }
    chain FORWARD {
        type filter hook forward priority 0; policy drop
        reject with icmp type host-prohibited
    }
}

table ip6 filter {
    chain INPUT {
        type filter hook input priority 0; policy accept
        ct state vmap { established : accept, related : accept }
        ip6 nexthdr icmpv6 accept
        iifname lo accept
        reject with icmpv6 type admin-prohibited
    }
    chain FORWARD {
        type filter hook forward priority 0; policy drop
        reject with icmpv6 type admin-prohibited
    }
}
EOF
chroot_exec rc-update add nftables default

# configure saned
chroot_exec rc-update add saned default

# configure ntpd
echo 'NTPD_OPTS="-N -p time.print.foo.sh"' >"${ROOTFS_PATH}/etc/conf.d/ntpd"

# configure syslog
echo 'SYSLOGD_OPTS="-R loghost.print.foo.sh -L -K -t"' >"${ROOTFS_PATH}/etc/conf.d/syslog"
