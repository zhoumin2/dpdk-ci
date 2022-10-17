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

send_series_test_report() {
	patches_dir=$1
	status=$2
	desc=$3
	report=$4

	first_pwid=`ls -1 $patches_dir |sed 's/\.patch//g' |sort -ug |head -1`
	last_pwid=`ls -1 $patches_dir |sed 's/\.patch//g' |sort -ug |tail -1`
	eval $($(dirname $(readlink -e $0))/parse-email.sh $patches_dir/$first_pwid.patch)

	$(dirname $(readlink -e $0))/send-patch-report.sh -t $subject -f $from -p $last_pwid -l "loongarch unit testing" -s $status -d $desc < $report
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

apply_log=$DPDK_HOME/build/apply-log.txt
meson_log=$DPDK_HOME/build/meson-logs/meson-log.txt
ninja_log=$DPDK_HOME/build/ninja-log.txt
test_log=$DPDK_HOME/build/meson-logs/testlog.txt
test_report=$DPDK_HOME/test-report.txt

if $REUSE_PATCH ; then
	if [ ! -d $patches_dir ] ; then
		download_series $series_id $patches_dir
	fi
else
	download_series $series_id $patches_dir
fi

. $(dirname $(readlink -e $0))/gen_test_report.sh

cd $DPDK_HOME

git checkout main
base_commit=`git log -1 --format=oneline |awk '{print $1}'`

new_branch=$BRANCH_PREFIX-$series_id
ret=`git branch --list $new_branch`
if [ ! -z "$ret" ]; then
	git branch -D $new_branch
fi
git checkout -b $new_branch

for patch in `ls $patches_dir |sort`
do
	git am $patches_dir/$patch > $apply_log
	if [ ! $? -eq 0 ]; then
		test_report_series_apply_fail $base_commit $patches_dir $apply_log $test_report
		send_series_test_report $patches_dir "WARNING" "apply patch failure" $test_report
	fi
done

rm -rf build

meson build
if [ ! $? -eq 0 ]; then
	test_report_series_meson_build_fail $base_commit $patches_dir $meson_log $test_report
	send_series_test_report $patches_dir "FAILURE" "meson build failure" $test_report
	exit 0
fi

ninja -C build
if [ ! $? -eq 0 ]; then
	test_report_series_ninja_build_fail $base_commit $patches_dir $ninja_log $test_report
	send_series_test_report $patches_dir "FAILURE" "ninja build failure" $test_report
	exit 0
echo

meson test -C build --suite DPDK:fast-tests
fail_num=`tail -n10 $test_log |sed -n 's/^Fail:[[:space:]]\+//p'`
if [ "$fail_num" != "0" ]; then
	test_report_series_test_fail $base_commit $patches_dir $test_report
	send_series_test_report $patches_dir "FAILURE" "Unit Testing FAIL" $test_report
	exit 0
fi

test_report_series_test_pass $base_commit $patches_dir $test_report
send_series_test_report $patches_dir "SUCCESS" "Unit Testing PASS" $test_report

cd -
