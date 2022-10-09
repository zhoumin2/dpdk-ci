#! /bin/sh -e

URL=http://patches.dpdk.org/api/series/

function print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) <series_id>

	Test one patch.
	END_OF_HELP
}

if [ $# -lt 1 ]; then
	printf 'missing series_id argument\n'
	print_usage >&2
	exit 1
fi

if [ -z "$DPDK_DIR" ]; then
	printf 'missing environment variable: $DPDK_DIR\n'
	exit 1
fi

series_id=$1
patches_dir=$(dirname $(readlink -e $0))/../series_$series_id
if [ ! -d $patches_dir ]; then
	mkdir $patches_dir
fi

echo "$URL/$series_id"
#echo `$(wget "$URL/$series_id")`
ids=$(wget -q -O - "$URL/$series_id" | jq "try ( .patches )" |jq "try ( .[] .id )")
echo $ids

if [ -z "$(echo $ids | tr -d '\n')" ]; then
	printf "cannot find patch(es) for series-id: $series_id\n"
	exit 1
fi

for id in $ids ; do
	$(dirname $(readlink -e $0))/download-patch.sh $id > $patches_dir/$id.patch
done
