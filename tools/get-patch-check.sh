#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) [OPTIONS] <pwid>

	Get a patch's combined checks by its ID.
	END_OF_HELP
}

verbose=false

while getopts hv arg ; do
	case $arg in
		h ) print_usage ; exit 0 ;;
		v ) verbose=true ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done
shift $(($OPTIND - 1))

pwid=$1
if [ -z "$pwid" ] ; then
	printf 'missing argument for pwid\n'
	print_usage >&2
	exit 1
fi

URL=http://patches.dpdk.org/api/patches/$pwid/checks/
if $verbose ; then
	echo "request: $URL"
fi

failed=false
for try in $(seq 3) ; do
	failed=false
	resp=$(wget -q -O - "$URL") || failed=true
	if $verbose ; then
		echo $resp
	fi
	if $failed ; then
		echo "wget $URL failed"
		#echo "response: $resp"
		sleep 1
		continue
	fi

	failed=false
	contexts=$(echo "$resp" | jq "try ( .[] | .context )") || failed=true
	if $failed ; then
		echo "jq handles failed, requested url: $URL"
		#echo "response: $resp"
		sleep 1
		continue
	fi
	break
done
if $failed ; then
	exit 1
fi

if $verbose ; then
	echo -n "context(s) for patch $pwid: "
fi
echo $contexts
