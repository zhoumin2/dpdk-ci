#! /bin/sh -e

URL=http://patches.dpdk.org/api/series/
BRANCH_PREFIX=s
REUSE_PATCH=false

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) [OPTIONS] <series_id>

	Run dpdk ci tests for one series specified by the series_id
	END_OF_HELP
}

download_series() {
	if [ $# -lt 2 ] ; then
		printf 'missing argument(s) when download series\n'
	fi

	series_id=$1
	save_dir=$2

	if [ ! -d $save_dir ] ; then
		mkdir $save_dir
	fi

	echo "$URL/$series_id"
	#echo `$(wget "$URL/$series_id")`
	ids=$(wget -q -O - "$URL/$series_id" | jq "try ( .patches )" |jq "try ( .[] .id )")
	echo $ids

	if [ -z "$(echo $ids | tr -d '\n')" ]; then
		printf "cannot find patch(es) for series-id: $series_id\n"
		exit 1
	fi

	i=1
	for id in $ids ; do
		$(dirname $(readlink -e $0))/download-patch.sh -g $id > $save_dir/${i}_$id.patch
		i=$((i+1))
	done
}

while getopts h:r arg ; do
	case $arg in
		r ) REUSE_PATCH=true ;;
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done

shift $((OPTIND - 1))

if [ $# -lt 1 ]; then
	printf 'missing series_id argument\n'
	print_usage >&2
	exit 1
fi

if [ -z "$DPDK_HOME" ]; then
	printf 'missing environment variable: $DPDK_HOME\n'
	exit 1
fi

series_id=$1
patches_dir=$(dirname $(readlink -e $0))/../series_$series_id

if $REUSE_PATCH ; then
	if [ ! -d $patches_dir ] ; then
		download_series $series_id $patches_dir
	fi
else
	download_series $series_id $patches_dir
fi

cd $DPDK_HOME

git checkout main

new_branch=$BRANCH_PREFIX-$series_id
ret=`git branch --list $new_branch`
if [ ! -z "$ret" ]; then
	git branch -D $new_branch
fi
git checkout -b $new_branch

for patch in `ls $patches_dir |sort`
do
	git am $patches_dir/$patch
done

rm -rf build

meson build

meson test -C build --suite DPDK:fast-tests

cd -
