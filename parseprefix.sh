#!/bin/bash
MYDIR="$(dirname "$(readlink -f "$0")")"

. "$MYDIR/config.sh" || exit 1;
#IPV6_NETWORK_DIRECTORY=/etc/ppp/ipv6-prefixes/
(
        flock -e 200

        #IPV6_ALLOW_PREFIX_DEGLATION=1;
	#IPV6_NETWORK_SIZE=64

        IPV6="$(ip addr show tap0 | grep inet6 | head -n1 | grep -Eo '([a-f0-9]{1,4}\:){1,8}(\:[a-f0-9]{1,4}){1,8}\/1?[0-9]{1,2}')"

	IPV6_NETWORKS="$(sipcalc -6 $IPV6 --v6split $IPV6_NETWORK_SIZE | grep Network | grep -E '([0-9a-f]{1,4}:){4}' -o | sed -r 's/:0{1,3}/:/g')"


	IPV6_EXISTING="$(find $IPV6_NETWORK_PREFIXES -type f -name '*:*')"

	echo "Networks: " >&2
	#printf "%s\n" $IPV6_NETWORKS >&2
	
	for range in $IPV6_NETWORKS
	do
		if [ -f $IPV6_NETWORK_PREFIXES$range ];
		then
			echo "Updating exisiting range: $range"
		else
			echo "Adding new range: $range"
		fi
		
		touch "$IPV6_NETWORK_PREFIXES$range"
		IPV6_EXISTING="$(printf "%s\n" $IPV6_EXISTING | grep -v $range -F)"
	done
	for range in $IPV6_EXISTING
	do

		echo "Removing range: $range"
		rm "$range"
	done

	





) 200>$IPV6_NETWORK_DIRECTORY.lockfile

