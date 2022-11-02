#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

URL=http://patches.dpdk.org/api/series
download_patch=$(dirname $(readlink -e $0))/download-patch.sh
filter_patch_email=$(dirname $(readlink -e $0))/filter-patch-email.sh
parse_encoded_file=$(dirname $(readlink -e $0))/parse_encoded_file.py

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

num=$(wc -l $save_dir/pwid_order.txt | awk '{print $1}')
echo "The number of patch(es) is: $num"
for id in $ids ; do
	email=$save_dir/$id.patch
	if [ ! -f $email ] ; then
		$download_patch $g_opt $id > $email
	fi

	downloaded=false
	for try in $(seq 20) ; do
		lines=$(echo "$($filter_patch_email < $email)" | wc -l)
		echo "$email lines: $lines"
		if [ $((lines)) -lt 8 ] ; then
			echo "download $email"
			$download_patch $g_opt $id > $email
		else
			downloaded=true
			break
		fi
		sleep 1
	done

	if ! $downloaded ; then
		if [ $((num)) -gt 1 ] ; then
			exit 1
		fi
	fi

	lines=$(echo "$($filter_patch_email < $email)" | wc -l)
	if [ $((lines)) -lt 8 ] ; then
		echo "filter patch email failed: $email"
		#exit 1
	fi
	python3 $parse_encoded_file $email $email
done

echo "download series done!"
