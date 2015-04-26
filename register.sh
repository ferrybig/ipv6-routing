#!/bin/bash
MYDIR="$(dirname "$(readlink -f "$0")")"

. "$MYDIR/config.sh" || exit 1;

IFACE=""
IFADDR=""
SESSION=""



PREFIX=0
TARGETS=""
REMOTE=""
SESSION=""
VERSION=0
HELP=0
INCORRECT=0
while [[ $# > 0 ]]
do
        key="$1"

        case $key in
                -p|--prefix)
                        PREFIX=1
                        shift
                ;;
                -s|--session)
                        SESSION="$2"
                        shift 2
                ;;
                -r|--remote)
                        REMOTE="$2"
                        shift 2
                ;;
                -V|--version)
                        VERSION=1
                        shift
                ;;
                -h)
                        HELP=1
                        shift
                ;;
                -*)
                        INCORRECT=1
                        shift
                ;;
                *)
                        [ -z "$TARGETS" ] && TARGETS="$1" || TARGETS="$TARGETS $1"
                        shift
                ;;

        esac
done

if [ "$INCORRECT" -eq 1 ]
then
        echo "Incorrect usage" &1>2
        exit 1
fi

if [ "$VERSION" -eq 1 ]
then
        echo "Version 1.0.0"
        exit 0
fi

if [ "$HELP" -eq 1 ]
then
        echo "No help for this program"
        exit 0
fi
                    




(

        flock -e 200

        for IFACE in $TARGETS
        do
                if [ -f "$IPV6_NETWORK_IFACE$IFACE.range" ]
                then
                        echo "Interface $IFACE is already configured! unregister first or clear file $IPV6_NETWORK_IFACE$IFACE.range"
                        exit 1;
                fi

                if [ "$IPV6_USE_SESSION" -eq "1" -a \( ! -z "$SESSION" \) -a -s "${IPV6_USER_SESSION}$SESSION" ]
                then
                        IPV6_SESSION="$(cat "${IPV6_USER_SESSION}$SESSION")"
                        if [ ! -f "$IPV6_SESSION" ]
                        then
                                echo "User session not found, did the prefix change?"
                                IPV6_SESSION=""
                        fi
                else
                        IPV6_SESSION=""
                fi
                IPV6_EXISTING="$(echo $IPV6_SESSION && find $IPV6_NETWORK_PREFIXES -type f -name '*:*' | sort -R)"
        #        echo "Valid ipv6 address files:"
        #        echo "$IPV6_EXISTING"

                found=""
                for range in $IPV6_EXISTING
                do
                        if [ -z "$range" ]
                        then
                                continue;
                        fi
                        if [ ! -s "$range" ]
                        then
                                found="$range"
                                break;
                        else
                                echo "Skipping range $range as it isn't empty"
                        fi

                done


                if [ -z "$found" ]
                then
                        echo "No free prefix found! Is there a problem with "
                        exit 1
                fi

                if [ "$IPV6_USE_SESSION" -eq "1" ]
                then
                        echo "$found" > "${IPV6_USER_SESSION}$SESSION"
                fi
                range="$found";
                addr="$(basename $range)"
                if [ -z "$IFACE" ]
                then
                        echo "Test mode, found range: $addr in file $range"
                        exit 0;
                fi
                echo "Configuring interface $IFACE"
                echo "$IFACE" > "$range"
                echo "$range" > "$IPV6_NETWORK_IFACE$IFACE.range"
                #echo "$range" > "$IPV6_NETWORK_IFACE$IFACE.last"

                /sbin/ip -6 addr add "$addr:1/64" dev "$IFACE"

                CONFIG="$IPV6_NETWORK_IFACE$IFACE"


                RA="$CONFIG.radvd.conf"
                RAP="$CONFIG.radvd.pid"
                echo "interface $IFACE {"                                  > "$RA"
                echo "    AdvSendAdvert on;"                               >> "$RA"
                echo "    MinRtrAdvInterval 5;"                            >> "$RA"
                echo "    MaxRtrAdvInterval 90;"                           >> "$RA"
                echo "    AdvRetransTimer 5000; "                          >> "$RA"
                echo "    AdvReachableTime 1800; "                         >> "$RA"
                echo "    AdvDefaultLifetime 1800;"                        >> "$RA"
                echo "    AdvSourceLLAddress on;"                          >> "$RA"
                echo "    AdvOtherConfigFlag on;"                          >> "$RA"
                echo "    AdvManagedFlag on;"                              >> "$RA"
        #        echo "    UnicastOnly on;"                                 >> "$RA"
                echo "    prefix $addr:/64 {};"                            >> "$RA"
                echo "    route ::/0 {RemoveRoute on;};"                   >> "$RA"
                echo "    RDNSS $IFADDR {}; "                              >> "$RA"
                echo "    DNSSL ferrybig.local {};"                        >> "$RA"
                echo " };"                                                 >> "$RA"

                /usr/sbin/radvd -C "$RA" -p "$RAP" 200>/dev/null


                DHCP="$CONFIG.dhcp6s.conf"
                DHCP_PID="$CONFIG.dhcp6s.pid"
                echo "option domain-name-servers $IFADDR;"                > "$DHCP"
                echo 'option domain-name "ferrybig.local";'               >> "$DHCP"
                echo "interface $IFACE {"                                 >> "$DHCP"
                echo "    allow rapid-commit;"                            >> "$DHCP"
                echo "};"                                                 >> "$DHCP"

                /usr/sbin/dhcp6s -c "$DHCP" -P "$DHCP_PID" "$IFACE" 200>/dev/null




                echo "Connection setup, using range: $addr:1/64, session: $SESSION"
        done

        






) 200>$IPV6_NETWORK_DIRECTORY.lockfile

