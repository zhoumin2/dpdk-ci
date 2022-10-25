#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

BRANCH_PREFIX=s
REUSE_PATCH=false

parse_email=$(dirname $(readlink -e $0))/../tools/parse-email.sh
send_series_report=$(dirname $(readlink -e $0))/../tools/send-series-report-la.sh
download_series=$(dirname $(readlink -e $0))/../tools/download-series.sh
get_patch_check=$(dirname $(readlink -e $0))/../tools/get-patch-check.sh
parse_testlog=$(dirname $(readlink -e $0))/../tools/parse_testlog.py

export LC="en_US.UTF-8"
export LANG="en_US.UTF-8"

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) [OPTIONS] <series_id>

	Run dpdk ci tests for one series specified by the series_id
	END_OF_HELP
}

check_patch_check() {
	pwid=$1
	label="loongarch"

	failed=false
	contexts=$($get_patch_check $pwid) || failed=true
	echo "contexts for $pwid: $contexts"
	if $failed ; then
		return;
	fi

	if [ ! -z "$(echo "$contexts" | grep -qi $label)" ] ; then
	      echo "test report for $pwid from $label existed!"
	      echo "test not execute."
	      exit 0
	fi
}

send_series_test_report() {
	series_id=$1
	patches_dir=$2
	status=$3
	desc=$4
	report=$5

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`

	check_patch_check $last_pwid

	pwids=$first_pwid
	if [ $first_pwid != $last_pwid ] ; then
		pwids=$first_pwid-$last_pwid
	fi

	eval $($parse_email $patches_dir/$last_pwid.patch)
	if [ -z "$subject" -o -z "$from" -o -z "$msgid" \
		-o -z "$pwid" -o -z "$listid" ] ; then
		echo "parse email failed: $patches_dir/$last_pwid.patch"
		exit 1
	fi

	from="zhoumin@loongson.cn"
	echo "send test report for series $series_id to $from"
	$send_series_report -t "$subject" -f "$from" -m "$msgid" -p "$last_pwid" \
		-r "$pwids" -o "$listid" -l "loongarch unit testing" \
		-s "$status" -d "$desc" < $report
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
patches_dir=$(dirname $(readlink -e $0))/../series/$series_id

apply_log=$DPDK_HOME/apply-log.txt
meson_log=$DPDK_HOME/build/meson-logs/meson-log.txt
ninja_log=$DPDK_HOME/build/ninja-log.txt
testlog_json=$DPDK_HOME/build/meson-logs/testlog.json
testlog_txt=$DPDK_HOME/build/meson-logs/testlog.txt
test_report=$DPDK_HOME/test-report.txt

if $REUSE_PATCH ; then
	if [ ! -d $patches_dir ] ; then
		failed=false
		$download_series -g $series_id $patches_dir || failed=true
		if $failed ; then
			echo "download series failed"
			exit 1
		fi
	fi
else
	failed=false
	$download_series -g $series_id $patches_dir || failed=true
	if $failed ; then
		echo "download series failed"
		exit 1
	fi
fi

last_pwid=`tail -1 $patches_dir/pwid_order.txt`
check_patch_check $last_pwid

. $(dirname $(readlink -e $0))/gen-test-report.sh

cd $DPDK_HOME

if git status | grep -q "git am --abort" ; then
       git am --abort
fi

git checkout main
git pull --rebase
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
	patch_email=$patches_dir/$id.patch

	rm -rf $apply_log

	failed=false
	git apply --check $patch_email || failed=true
	if $failed ; then
		git apply -v $patch_email 2>&1 | tee $apply_log
		echo "apply patch failure"
		test_report_series_apply_fail $base_commit $patches_dir $apply_log $test_report
		send_series_test_report $series_id $patches_dir "WARNING" "apply patch failure" $test_report
		exit 0
	fi

	git am $patch_email
	applied=true
done < $patches_dir/pwid_order.txt

if ! $applied ; then
	echo "Cannot apply any patch for series $series_id, please check series directory"
	echo "Test not be executed!"
	exit 1
fi

rm -rf build

failed=false
meson build || failed=true
if $failed ; then
	echo "meson build failure"
	test_report_series_meson_build_fail $base_commit $patches_dir $meson_log $test_report
	send_series_test_report $series_id $patches_dir "FAILURE" "meson build failure" $test_report
	exit 0
fi

failed=false
ninja -C build &> $ninja_log || failed=true
if $failed ; then
	echo "ninja build failure"
	test_report_series_ninja_build_fail $base_commit $patches_dir $ninja_log $test_report
	send_series_test_report $series_id $patches_dir "FAILURE" "ninja build failure" $test_report
	exit 0
fi

failed=false
meson test -C build --suite DPDK:fast-tests --test-args="-l 0-7" -t 8 || failed=true
echo "test done!"
if $failed ; then
	echo "unit testing fail"
	test_report_series_test_fail $base_commit $patches_dir $testlog_json $testlog_txt $test_report
	send_series_test_report $series_id $patches_dir "FAILURE" "Unit Testing FAIL" $test_report
	exit 0
fi

echo "unit testing pass"
test_report_series_test_pass $base_commit $patches_dir $testlog_json $testlog_txt $test_report
send_series_test_report $series_id $patches_dir "SUCCESS" "Unit Testing PASS" $test_report

cd -
