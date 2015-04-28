#!/bin/bash
MYDIR="$(dirname "$(readlink -f "$0")")"

. "$MYDIR/config.sh" || exit 1;
if [ $# -eq 0 ]
then
        echo "No arguments supplied, going to test mode"
        IFACE=""
        IFADDR=""
else
        IFACE="$1"
        IFADDR="$(/bin/ip -6 addr show dev "$IFACE" | grep -F 'scope link' | head -1 | grep -oE '(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))')"
        if [ $? -ne 0 ]
        then
                echo "No link-local address found on device $IFACE" >&2
        fi
        if [ ! -z "$REGISTER_DEBUG" ]
        then
                echo "Going forced debug mode" >&2
                IFACE=""
        fi
fi

(
        flock -e 200





        if [ -f "$IPV6_NETWORK_IFACE$IFACE.range" ]
        then
                echo "Connection for $IFACE was found"
                addrfile="$(cat "$IPV6_NETWORK_IFACE$IFACE.range")"
                addr="$(basename $addrfile)"
                find "$IPV6_NETWORK_IFACE" -type f -name "$IFACE.*" -name "*.pid" -print0 | while IFS= read -r -d $'\0' line; do
                        echo "Found pid file: $line"
                        pid="$(cat $line)"
                        if [ ! -z "$pid" ]; then
                                kill -15 "$pid"
                        else
                                echo "Removing old file: $line"
                                echo rm "$line"
                        fi
                done
                if [ -f "$IPV6_NETWORK_IFACE$IFACE.prefix" ]
                then
                        prefixfile="$(cat "$IPV6_NETWORK_IFACE$IFACE.prefix")"
                        > $prefixfile
                        echo "Removing range $(basename "$prefixfile"):/64 from $IFACE"
                fi
                echo "Removing range $addr:/64 from $IFACE"
                /sbin/ip -6 addr del "$addr:1/64" dev "$IFACE"
                > $addrfile
                rm $IPV6_NETWORK_IFACE$IFACE.range
        else
                echo "Connection $IFACE not found"
        fi




) 200>$IPV6_NETWORK_DIRECTORY.lockfile

