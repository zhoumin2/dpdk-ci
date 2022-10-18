#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

DEBUG=false
project=DPDK
resource_type=series

print_usage () {
	cat <<- END_OF_HELP
	usage: $(basename $0) [OPTIONS] </path/to/dpdk-repo> </path/to/last.txt>

	Run dpdk ci tests for patches commited since the time in last.txt
	END_OF_HELP
}


init_last () {
	URL=http://patches.dpdk.org/api
	URL="${URL}/events/?category=${resource_type}-completed"

	echo `date "+%Y-%m-%dT00:00:00"` > $SINCE_FILE

	since=$(date -d "$(cat $SINCE_FILE | tr '\n' ' ')" '+%FT%T')
	printf "Test since: $since\n"
	ids=$(curl -s "${URL}&page=${page}&since=${since}" |
		jq "try ( .[] | select( .project.name == \"$project\" ) )" |
		jq "try ( .payload.${resource_type}.id )")

	while [ -z "$(echo $ids | tr -d '\n')" ]
	do
		since=$(date -d "yesterday $(date -d $since '+%F')" '+%FT%T')
		printf "Test since: $since\n"
		ids=$(curl -s "${URL}&page=1&since=${since}" |
			jq "try ( .[] | select( .project.name == \"$project\" ) )" |
			jq "try ( .payload.${resource_type}.id )")
	done

	num=0
	for id in $ids;
	do
		num=$((num+1))
	done

	printf "There are $num patch(es) since $since\n"
	echo $since > $SINCE_FILE
}

setup () {
	if $DEBUG; then
		init_last
	fi

	cd $DPDK_HOME
	git checkout main
	cd -
}


while getopts hd arg ; do
	case $arg in
		d ) DEBUG=true ;;
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done

shift $(($OPTIND - 1))

if [ $# -lt 2 ] ; then
	printf 'missing argument(s)\n\n' >&2
	print_usage >&2
	exit 1
fi

DPDK_HOME=$1
SINCE_FILE=$2

if [ ! -d "$DPDK_HOME" ]; then
	printf "The directory '$DPDK_HOME' doesn't exist.\n\n" >&2
	print_usage >&2
	exit 1
fi

if [ ! -f "$SINCE_FILE" ]; then
	printf "The file '$SINCE_FILE' doesn't exist.\n\n" >&2
	print_usage >&2
	exit 1
fi

setup

export DPDK_HOME=$DPDK_HOME
$(dirname $(readlink -e $0))/poll-pw $resource_type $project $SINCE_FILE $(dirname $(readlink -e $0))/test-series.sh
