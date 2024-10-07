#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

DEBUG=false
project=DPDK
resource_type=series
test_series=$(dirname $(readlink -e $0))/test-series.sh
series_id_file=$(dirname $(readlink -e $0))/../data/series_to_test.txt

print_usage () {
	cat <<- END_OF_HELP
	usage: $(basename $0) [OPTIONS] </path/to/last.txt>

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
}

while getopts hd arg ; do
	case $arg in
		d ) DEBUG=true ;;
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

SINCE_FILE=$1
if [ ! -f "$SINCE_FILE" ]; then
	printf "The file '$SINCE_FILE' doesn't exist.\n\n" >&2
	print_usage >&2
	exit 1
fi

setup

$(dirname $(readlink -e $0))/poll-pw $resource_type $project $SINCE_FILE $test_series
#$(dirname $(readlink -e $0))/poll-file $resource_type $series_id_file $test_series -k
python3.8 $(dirname $(readlink -e $0))/recheck.py
