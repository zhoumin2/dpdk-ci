#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

BRANCH_PREFIX=p
REUSE_PATCH=false

parse_email=$(dirname $(readlink -e $0))/../tools/parse-email.sh
send_patch_report=$(dirname $(readlink -e $0))/../tools/send-patch-report-la.sh
download_patch=$(dirname $(readlink -e $0))/../tools/download-patch.sh
filter_patch_email=$(dirname $(readlink -e $0))/filter-patch-email.sh
get_patch_check=$(dirname $(readlink -e $0))/../tools/get-patch-check.sh
parse_testlog=$(dirname $(readlink -e $0))/../tools/parse_testlog.py

label_compilation="LoongArch compilation"
label_unit_testing="LoongArch unit testing"

status_warning="WARNING"
status_failure="FAILURE"
status_success="SUCCESS"

desc_apply_failure="apply patch failure"
desc_meson_build_failure="meson build failure"
desc_ninja_build_failure="ninja build failure"
desc_build_pass="Compilation OK"
desc_unit_test_fail="Unit Testing FAIL"
desc_unit_test_pass="Unit Testing PASS"

export LC="en_US.UTF-8"
export LANG="en_US.UTF-8"

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) [OPTIONS] <patch_id>

	Run dpdk ci tests for one patch specified by the patch_id
	END_OF_HELP
}

check_patch_check() {
	pwid=$1
	context=$(echo "$2" | sed 's/ /-/g')

	echo "finding context: "$context" for $pwid ..."

	failed=false
	contexts=$($get_patch_check $pwid) || failed=true
	echo "contexts for $pwid: $contexts"
	if $failed ; then
		echo "find context "$context" failed"
		return;
	fi

	if [ ! -z "$(echo "$contexts" | grep -qi "$context")" ] ; then
	      echo "test report for $pwid from "$context" existed!"
	      echo "test not execute."
	      exit 0
	else
	      echo "not found context: "$context""
	fi
}

send_patch_test_report() {
	patch_email=$1
	label=$2
	status=$3
	desc=$4
	report=$5

	eval $($parse_email $patch_email)

	check_patch_check $pwid "$label"

	from="zhoumin@loongson.cn"
	echo "send test report for patch $pwid to $from"
	$send_patch_report -t "$subject" -f "$from" -m "$msgid" -p "$pwid" \
		-o "$listid" -l "$label" -s "$status" \
		-d "$desc" < $report
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
	printf 'missing patch_id argument\n'
	print_usage >&2
	exit 1
fi

if [ -z "$DPDK_HOME" ]; then
	printf 'missing environment variable: $DPDK_HOME\n'
	exit 1
fi

patches_dir=$(dirname $(readlink -e $0))/../patches
if [ ! -d $patches_dir ]; then
	mkdir -p $patches_dir
fi

patch_id=$1
patch_email=$patches_dir/$patch_id.patch

apply_log=$DPDK_HOME/apply-log.txt
meson_log=$DPDK_HOME/build/meson-logs/meson-log.txt
ninja_log=$DPDK_HOME/build/ninja-log.txt
testlog_json=$DPDK_HOME/build/meson-logs/testlog.json
testlog_txt=$DPDK_HOME/build/meson-logs/testlog.txt
test_report=$DPDK_HOME/test-report.txt

if $REUSE_PATCH ; then
	if [ ! -f $patch_email ] ; then
		$download_patch -g $patch_id > $patch_email
	fi
else
	$download_patch -g $patch_id > $patch_email
fi

lines=$(echo "$($filter_patch_email < $patch_email)" | wc -l)
if [ $((lines)) -lt 8 ]; then
	echo "filter patch email failed: $patch_email"
	exit 1
fi

#check_patch_check $patch_id

. $(dirname $(readlink -e $0))/gen-test-report.sh

cd $DPDK_HOME

if git status | grep -q "git am --abort" ; then
       git am --abort
fi

git checkout main
git pull --rebase
base_commit=`git log -1 --format=oneline |awk '{print $1}'`

new_branch=$BRANCH_PREFIX-$patch_id
ret=`git branch --list $new_branch`
if [ ! -z "$ret" ] ; then
	git branch -D $new_branch
fi
git checkout -b $new_branch

rm -rf $apply_log

failed=false
git apply --check $patch_email || failed=true
if $failed ; then
	git apply -v $patch_email 2>&1 | tee $apply_log
	echo "apply patch failure"
	test_report_patch_apply_fail $base_commit $patch_email $apply_log $test_report
	send_patch_test_report $patch_email "$label_compilation" $status_warning "$desc_apply_failure" $test_report
	exit 0
fi

git am $patch_email

rm -rf build

failed=false
meson build || failed=true
if $failed ; then
	echo "meson build failure"
	test_report_patch_meson_build_fail $base_commit $patch_email $meson_log $test_report
	send_patch_test_report $patch_email "$label_compilation" $status_failure "$desc_meson_build_failure" $test_report
	exit 0
fi

failed=false
ninja -C build |tee $ninja_log || failed=true
if $failed ; then
	echo "ninja build failure"
	test_report_patch_ninja_build_fail $base_commit $patch_email $ninja_log $test_report
	send_patch_test_report $patch_email "$label_compilation" $status_failure "$desc_ninja_build_failure" $test_report
	exit 0
fi

echo "meson & ninja build pass"
test_report_patch_build_pass $base_commit $patch_email $test_report
send_patch_test_report $patch_email "$label_compilation" $status_success "$desc_build_pass" $test_report

failed=false
meson test -C build --suite DPDK:fast-tests --test-args="-l 0-7" -t 8 || failed=true
echo "test done!"
if $failed ; then
	echo "unit testing fail"
	test_report_patch_test_fail $base_commit $patch_email $testlog_json $testlog_txt $test_report
	send_patch_test_report $patch_email "$label_unit_testing" $status_failure "$desc_unit_test_fail" $test_report
	exit 0
fi

echo "unit testing pass"
test_report_patch_test_pass $base_commit $patch_email $testlog_json $testlog_txt $test_report
send_patch_test_report $patch_email "$label_unit_testing" $status_success "$desc_unit_test_pass" $test_report

cd -
