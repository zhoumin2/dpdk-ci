#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

URL=http://patches.dpdk.org/api/series

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) [-g] <series_id> <save_dir>

	Download all patch(es) for a series_id from patchwork through pwclient
	XML-RPC (default) or curl HTTP GET (option -g).
	END_OF_HELP
}

g_opt=""

while getopts gh arg ; do
	case $arg in
		g ) g_opt="-g" ;;
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done
shift $(($OPTIND - 1))

series_id=$1
save_dir=$2

if [ -z "$series_id" -o -z "$save_dir" ] ; then
	printf 'missing argument(s) when download series\n'
	print_usage >&2
	exit 1
fi

if [ ! -d $save_dir ] ; then
	mkdir -p $save_dir
fi

url="$URL/$series_id"
echo "$(basename $0): request "$url""

failed=false
resp=$(wget -q -O - "$url") || failed=true
if $failed ; then
	echo "wget "$url" failed"
	echo "$resp"
	exit 1
fi

failed=false
ids=$(echo "$resp" | jq "try ( .patches )" |jq "try ( .[] .id )") || failed=true
if $failed ; then
	echo "jq handles failed"
	echo "$resp"
	exit 1
fi

if [ -z "$(echo $ids | tr -d '\n')" ] ; then
	echo "cannot get pwid(s) for series $series_id"
	exit 1
fi

echo "pwid(s) for series $series_id: $(echo $ids | tr '\n' ' ')"
echo "$ids" > $save_dir/pwid_order.txt

for id in $ids ; do
	$(dirname $(readlink -e $0))/download-patch.sh $g_opt $id > $save_dir/$id.patch
done

echo "download series done!"
