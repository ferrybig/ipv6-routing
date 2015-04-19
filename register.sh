#!/bin/bash
MYDIR="$(dirname "$(readlink -f "$0")")"

. "$MYDIR/config.sh" || exit 1;



if [ $# -eq 0 ]
then
	echo "No arguments supplied, going to test mode"
	IFACE=""
	IFADDR=""
	SESSION=""
else
	IFACE="$1"
	IFADDR="$(/bin/ip -6 addr show dev "$IFACE" | grep -F 'scope link' | head -1 | grep -oE '(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))')"
	if [ $? -ne 0 ]
	then
		echo "No link-local address found on device $IFACE" >&2
		exit 1;
	fi
	if [ ! -z "$REGISTER_DEBUG" ]
	then
		echo "Going forced debug mode" >&2
		IFACE=""
	fi
	if [ $# -eq 1 ]
	then
		SESSION=""
	else
		SESSION="$2"
		# use bashism to validate the string, maybe search for a posix way & allow the user to edit it
		if  [[ ! "$SESSION" =~ ^[A-Za-z0-9_]{1,32}$ ]];
		then
			SESSION=""
		fi
	fi
fi


(

	flock -e 200

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
#	echo "Valid ipv6 address files:"
#	echo "$IPV6_EXISTING"

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
	echo "interface $IFACE {" 				> "$RA"
	echo "    AdvSendAdvert on;" 				>> "$RA"
	echo "    MinRtrAdvInterval 5;" 			>> "$RA"
	echo "    MaxRtrAdvInterval 90;" 			>> "$RA"
	echo "    AdvRetransTimer 5000; " 			>> "$RA"
	echo "    AdvReachableTime 180; " 			>> "$RA"
	echo "    AdvDefaultLifetime 180;"			>> "$RA"
	echo "    AdvSourceLLAddress on;"			>> "$RA"
	echo "    AdvOtherConfigFlag on;"			>> "$RA"
	echo "    AdvManagedFlag on;"				>> "$RA"
	echo "    prefix $addr:/64 {DeprecatePrefix on;};" 	>> "$RA"
	echo "    route ::/0 {RemoveRoute on;};"            	>> "$RA"
	echo "    RDNSS $IFADDR {}; "                      	>> "$RA"
	echo "    DNSSL ferrybig.local {};"  			>> "$RA"
	echo " };" 						>> "$RA"
	
	/usr/sbin/radvd -C "$RA" -p "$RAP" 200>/dev/null
	
	
	DHCP="$CONFIG.dhcp6s.conf"
	DHCP_PID="$CONFIG.dhcp6s.pid"
	echo "option domain-name-servers $IFADDR;"		> "$DHCP"
	echo 'option domain-name "ferrybig.local";'		>> "$DHCP"
	echo "interface $IFACE {"				>> "$DHCP"
	echo "    allow rapid-commit;"				>> "$DHCP"
	echo "};"						>> "$DHCP"

	/usr/sbin/dhcp6s -c "$DHCP" -P "$DHCP_PID" "$IFACE" 200>/dev/null




	echo "Connection setup, using range: $addr"
	
	
	
	
	






) 200>$IPV6_NETWORK_DIRECTORY.lockfile

