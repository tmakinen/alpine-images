#!/bin/sh

chroot_exec apk add \
    openssh-sftp-server \
    linux-firmware-edgeport \
    nftables

# enable loading edgeport modules on startup
echo "io_edgeport" >> "${ROOTFS_PATH}/etc/modules"

chroot_exec adduser -h /var/empty -g "Console User" -s /bin/sh -G dialout -D -H console

# configure firewall
cat <<EOF > "${ROOTFS_PATH}/etc/nftables.nft"
#!/usr/sbin/nft -f

flush ruleset

table ip filter {
    chain INPUT {
        type filter hook input priority 0; policy accept
        ct state vmap { established : accept, related : accept }
        ip protocol icmp accept
        iifname lo accept
        ip saddr 172.20.25.1/32 tcp dport 22 accept
        ip saddr 172.20.25.2/32 tcp dport 22 accept
        ip saddr 172.20.25.3/32 tcp dport 22 accept
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

# configure ntpd
echo 'NTPD_OPTS="-N -p time.oob.foo.sh"' > "${ROOTFS_PATH}/etc/conf.d/ntpd"

# configure syslog
echo 'SYSLOGD_OPTS="-R loghost.oob.foo.sh -L -K -t"' > "${ROOTFS_PATH}/etc/conf.d/syslog"

# create console script
cat <<"EOF" > "${ROOTFS_PATH}/usr/local/bin/console"
#!/bin/sh

set -eu
umask 077

if [ $# -ne 1 ]; then
    echo "Usage: $(basename "$0") <port>" 1>&2
    exit 1
fi
port="/dev/ttyUSB${1}"
if [ ! -c "$port" ]; then
    echo "ERROR: Invalid port ${1}, no device ${port} found" 1>&2
    exit 1
fi

echo "Connecting to ${port}..."
echo "Escape character is ^X (Ctrl + X)"
busybox microcom -s 115200 "$port"
EOF
chmod 0755 "${ROOTFS_PATH}/usr/local/bin/console"
