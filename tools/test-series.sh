#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

BRANCH_PREFIX=s
REUSE_PATCH=false

parse_email=$(dirname $(readlink -e $0))/../tools/parse-email.sh
send_patch_report=$(dirname $(readlink -e $0))/../tools/send-patch-report.sh

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

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	eval $($parse_email $patches_dir/$first_pwid.patch)

	$send_patch_report -t $subject -f $from -p $last_pwid -l "loongarch unit testing" -s $status -d $desc < $report
}

while getopts hr arg ; do
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
		$(dirname $(readlink -e $0))/download-series.sh -g $series_id $patches_dir
	fi
else
	$(dirname $(readlink -e $0))/download-series.sh -g $series_id $patches_dir
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

applied=false

while read line
do
	id=`echo $line|sed 's/^[[:space:]]*//g;s/[[:space:]]*$//g'`
	if [ -z "$id" ] ; then
		continue
	fi

	git am $patches_dir/$id.patch |tee $apply_log
	if [ ! $? -eq 0 ]; then
		echo "apply patch failure"
		test_report_series_apply_fail $base_commit $patches_dir $apply_log $test_report
		send_series_test_report $patches_dir "WARNING" "apply patch failure" $test_report
		exit 0
	fi
	applied=true
done < $patches_dir/pwid_order.txt

if ! applied ; then
	echo "Cannot apply any patch for series $series_id, please check series directory"
	echo "Test not be executed!"
	exit 1
fi

rm -rf build

meson build
if [ ! $? -eq 0 ]; then
	echo "meson build failure"
	test_report_series_meson_build_fail $base_commit $patches_dir $meson_log $test_report
	send_series_test_report $patches_dir "FAILURE" "meson build failure" $test_report
	exit 0
fi

ninja -C build |tee $ninja_log
if [ ! $? -eq 0 ]; then
	echo "ninja build failure"
	test_report_series_ninja_build_fail $base_commit $patches_dir $ninja_log $test_report
	send_series_test_report $patches_dir "FAILURE" "ninja build failure" $test_report
	exit 0
fi

meson test -C build --suite DPDK:fast-tests --test-args="-l 0-7" -t 3
fail_num=`tail -n10 $test_log |sed -n 's/^Fail:[[:space:]]\+//p'`
if [ "$fail_num" != "0" ]; then
	echo "unit testing fail"
	test_report_series_test_fail $base_commit $patches_dir $test_report
	send_series_test_report $patches_dir "FAILURE" "Unit Testing FAIL" $test_report
	exit 0
fi

echo "unit testing pass"
test_report_series_test_pass $base_commit $patches_dir $test_report
send_series_test_report $patches_dir "SUCCESS" "Unit Testing PASS" $test_report

cd -
