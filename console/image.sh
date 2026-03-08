#!/bin/sh

link_file() {
    src="$1"
    mv "${ROOTFS_PATH}${src}" "${ROOTFS_PATH}${src}.alpine-builder"
    ln -sf "/data${src}" "${ROOTFS_PATH}${src}"
    mkdir -p "${DATAFS_PATH}/$(dirname "$src")"
    cp -a "${ROOTFS_PATH}${src}.alpine-builder" "${DATAFS_PATH}${src}"
}

chroot_exec apk add \
    openssh-sftp-server \
    linux-firmware-edgeport \
    nftables

# disable audio, bluetooth and wifi
{
    echo "dtparam=audio=off"
    echo "dtoverlay=disable-bt"
    echo "dtoverlay=disable-wifi"
} >>"${BOOTFS_PATH}/config.txt"

# enable loading edgeport modules on startup
echo "io_edgeport" >>"${ROOTFS_PATH}/etc/modules"

chroot_exec adduser -h /var/empty -g "Console User" -s /bin/sh -G dialout -D -H console

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

# make ntpd and syslog configurable
link_file "/etc/conf.d/ntpd"
link_file "/etc/conf.d/syslog"

# configure dhcp client
echo "    udhcpc_opts -O hostname -O ntpsrv -O 7" >>"${ROOTFS_PATH}/etc/network/interfaces.alpine-builder"
cp -a "${ROOTFS_PATH}/etc/network/interfaces.alpine-builder" "${DATAFS_PATH}/etc/network/interfaces"
mkdir "${ROOTFS_PATH}/etc/udhcpc/post-bound"
cat <<"EOF" >"${ROOTFS_PATH}/etc/udhcpc/post-bound/config.sh"
#!/bin/sh

set -eu

decode_iplist() {
    _hex="$1"
    _list=""
    while [ -n "$_hex" ]; do
	_chunk="$(echo "$_hex" | cut -c 1-8)"
	_ip1="$(printf "%d" "0x$(echo "$_chunk" | cut -c 1-2)")"
        _ip2="$(printf "%d" "0x$(echo "$_chunk" | cut -c 3-4)")"
        _ip3="$(printf "%d" "0x$(echo "$_chunk" | cut -c 5-6)")"
        _ip4="$(printf "%d" "0x$(echo "$_chunk" | cut -c 7-8)")"

        _list="${_list} ${_ip1}.${_ip2}.${_ip3}.${_ip4}"
	_hex="$(echo "$_hex" | cut -c 9-)"
    done
    echo "$_list"
}

skip_opts() {
    _skip="$1"
    shift

    _newopts=""
    while [ -n "${1:-}" ]; do
        if [ "$1" = "$_skip" ]; then
            shift
            shift
            continue
        fi
        _newopts="${_newopts} ${1}"
        shift
    done
    echo "$_newopts"
}

if [ -n "${hostname:-}" ]; then
    echo "$hostname" > /etc/hostname
    hostname "$hostname"
fi

if [ -n "${ntpsrv:-}" ]; then
    [ -f /etc/conf.d/ntpd ] && . /etc/conf.d/ntpd
    NTPD_OPTS="$(skip_opts "-p" ${NTPD_OPTS:-})"
    for ip in $ntpsrv ; do
        NTPD_OPTS="${NTPD_OPTS} -p ${ip}"
    done
    sed -i -e "s/NTPD_OPTS=.*/NTPD_OPTS=\"${NTPD_OPTS#?}\"/" /data/etc/conf.d/ntpd
fi

if [ -n "${opt7:-}" ]; then
    logsrv="$(decode_iplist "$opt7")"
    [ -f /etc/conf.d/syslog ] && . /etc/conf.d/syslog
    SYSLOGD_OPTS="$(skip_opts "-R" ${SYSLOGD_OPTS:-})"
    for ip in $(decode_iplist "$opt7") ; do
        SYSLOGD_OPTS="${SYSLOGD_OPTS} -R ${ip}"
    done
    sed -i -e "s/SYSLOGD_OPTS=.*/SYSLOGD_OPTS=\"${SYSLOGD_OPTS#?}\"/" /data/etc/conf.d/syslog
fi
EOF
chmod 0755 "${ROOTFS_PATH}/etc/udhcpc/post-bound/config.sh"

# create console script
cat <<"EOF" >"${ROOTFS_PATH}/usr/local/bin/console"
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
