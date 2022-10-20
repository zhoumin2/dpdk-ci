#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

URL=http://patches.dpdk.org/api
verbose=false

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) [OPTIONS] </path/to/last>

	Fetch all patch id(s) since the first date from the specified file.

	options:
	        -v	go into verbose mode
	        -h	this help
	END_OF_HELP
}

if ! command -v jq >/dev/null 2>&1 ; then
	printf "The command jq is unavailable, please install it.\n\n" >&2
	exit 1
fi

while getopts hv arg ; do
	case $arg in
		v ) verbose=true ;;
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done

shift $(($OPTIND - 1))

if [ $# -lt 1 ] ; then
	printf 'missing argument(s)\n\n' >&2
	print_usage >&2
	exit 1
fi

since_file=$1

if [ ! -f "$since_file" ] ; then
	printf "The file '$since_file' doesn't exist.\n\n" >&2
	exit 1
fi

if ! date -d "$(cat $since_file | tr '\n' ' ')" >/dev/null 2>&1 ; then
	printf "The file '$since_file' doesn't contain a valid date format.\n\n" >&2
	exit 1
fi

URL="${URL}/events/?category=patch-completed"

since=$(date -d "$(cat $since_file | tr '\n' ' ')" '+%FT%T')
if $verbose ; then
	echo $since
fi

page=1
date_now=$(date --utc '+%FT%T')
while true ; do
	url="${URL}&page=${page}&since=${since}"
	if $verbose ; then
		echo $url
	fi

	resp=`curl -s $url`
	if [ ! $? -eq 0 ] ; then
		if $verbose ; then
			echo "curl -s "$url" failed"
			echo "$resp"
		fi
		exit 1
	fi

	ids=$(echo "$resp" | jq "try ( .[] | select( .project.name == \"DPDK\" ) )" |
		jq "try ( .payload.patch.id )")
	if [ ! $? -eq 0 ] ; then
		if $verbose ; then
			echo "jq handles failed"
			echo "$resp"
		fi
		exit 1
	fi

	if [ -z "$(echo $ids | tr -d '\n')" ] ; then
		if $verbose ; then
			echo "fetch done!"
		fi
		break
	fi

	echo "$(echo $ids | tr '\n' ' ')"
	page=$(($page + 1))
done
printf $date_now >$since_file
