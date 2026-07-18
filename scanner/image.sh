#!/bin/sh

link_file() {
    src="$1"
    mkdir -p "${DATAFS_PATH}/$(dirname "$src")"
    if [ -f "${ROOTFS_PATH}${src}" ]; then
        mv "${ROOTFS_PATH}${src}" "${ROOTFS_PATH}${src}.alpine-builder"
        cp -a "${ROOTFS_PATH}${src}.alpine-builder" "${DATAFS_PATH}${src}"
    fi
    ln -sf "/data${src}" "${ROOTFS_PATH}${src}"
}

chroot_exec apk add \
    drill \
    nftables \
    sane \
    sane-saned \
    sane-utils \
    sane-backend-genesys \
    sane-backend-pixma

# disable audio, bluetooth and wifi
{
    echo "dtparam=audio=off"
    echo "dtoverlay=disable-bt"
    echo "dtoverlay=disable-wifi"
} >>"${BOOTFS_PATH}/config.txt"

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

# make ntpd and syslog configurable
link_file "/etc/conf.d/ntpd"
link_file "/etc/conf.d/syslog"

# configure firewall
cat <<EOF >"${ROOTFS_PATH}/etc/nftables.nft"
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    set scanserv_hosts {
        type ipv4_addr
    }
    chain INPUT {
        type filter hook input priority 0; policy accept
        ct state vmap { established : accept, related : accept }
        ip protocol icmp accept
        iifname lo accept
        ip saddr 172.20.27.0/24 tcp dport 22 accept
        tcp dport 6566 ip saddr @scanserv_hosts accept
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
link_file /etc/sane.d/saned.conf
cat <<"EOF" > "${ROOTFS_PATH}/etc/init.d/saned-config"
#!/sbin/openrc-run

name="Dynamic config for SANE server"
description="Resolves scanservjs hosts via DNS SRV to build the saned whitelist"

depend() {
    need net
    before saned
}

start() {
    ebegin "Querying infrastructure DNS for scanservjs hosts"

    : > /etc/sane.d/saned.conf
    drill -Q SRV "_scanserv._tcp.$(hostname -d)" | while read -r _ _ _ name ; do
        name="${name%.}"
        echo "$name" >> /etc/sane.d/saned.conf
        drill -Q "$name" | while read -r ip ; do
            nft add element inet filter scanserv_hosts { "$ip" }
        done
    done

    if [ ! -s /etc/sane.d/saned.conf ]; then
        ip route show | awk '$1 != "default" { print $1 }' | while read -r subnet ; do
            echo "$subnet" >> /etc/sane.d/saned.conf
            nft add element inet filter scanserv_hosts { "$subnet" }
        done
    fi
    eend $?
}
EOF
chmod 0755 "${ROOTFS_PATH}/etc/init.d/saned-config"
chroot_exec rc-update add saned-config default
chroot_exec rc-update add saned default
