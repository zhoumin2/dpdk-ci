#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

URL=http://patches.dpdk.org/api/series/

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
	mkdir $save_dir
fi

echo "request: $URL/$series_id"
#echo `$(wget "$URL/$series_id")`
ids=$(wget -q -O - "$URL/$series_id" | jq "try ( .patches )" |jq "try ( .[] .id )")
echo "pwid(s) for series $series_id: $ids"
echo "$ids" > $save_dir/pwid_order.txt

if [ -z "$(echo $ids | tr -d '\n')" ]; then
	printf "cannot find patch(es) for series-id: $series_id\n"
	exit 1
fi

for id in $ids ; do
	$(dirname $(readlink -e $0))/download-patch.sh $g_opt $id > $save_dir/$id.patch
done

echo "download series done!"
