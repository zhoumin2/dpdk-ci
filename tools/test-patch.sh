#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

BRANCH_PREFIX=p
REUSE_PATCH=false

parse_email=$(dirname $(readlink -e $0))/../tools/parse-email.sh
send_patch_report=$(dirname $(readlink -e $0))/../tools/send-patch-report.sh
download_patch=$(dirname $(readlink -e $0))/../tools/download-patch.sh

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) [OPTIONS] <patch_id>

	Run dpdk ci tests for one patch specified by the patch_id
	END_OF_HELP
}

send_patch_test_report() {
	patch_email=$1
	status=$2
	desc=$3
	report=$4

	eval $($parse_email $patch_email)

	from="514762755@qq.com"
	echo "send test report for patch $pwid to $from"
	$send_patch_report -t "$subject" -f "$from" -m "$msgid" -p "$pwid" \
		-l "loongarch unit testing" -s "$status" -d "$desc" < $report
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
	mkdir $patches_dir
fi

patch_id=$1
patch_email=$patches_dir/$patch_id.patch

apply_log=$DPDK_HOME/build/apply-log.txt
meson_log=$DPDK_HOME/build/meson-logs/meson-log.txt
ninja_log=$DPDK_HOME/build/ninja-log.txt
test_log=$DPDK_HOME/build/meson-logs/testlog.txt
test_report=$DPDK_HOME/test-report.txt

if $REUSE_PATCH ; then
	if [ ! -f $patch_email ]; then
		$download_patch -g $patch_id > $patch_email
	fi
else
	$download_patch -g $patch_id > $patch_email
fi
echo "$($(dirname $(readlink -e $0))/filter-patch-email.sh < $patch_email)" > $patch_email

if [ ! -s $patch_email ]; then
	printf "$patch_email is empty\n"
	exit 1
fi

. $(dirname $(readlink -e $0))/gen_test_report.sh

cd $DPDK_HOME

if git status | grep -q "git am --abort" ; then
       git am --abort
fi

git checkout main
git pull --rebase
base_commit=`git log -1 --format=oneline |awk '{print $1}'`

if false ; then

new_branch=$BRANCH_PREFIX-$patch_id
ret=`git branch --list $new_branch`
if [ ! -z "$ret" ] ; then
	git branch -D $new_branch
fi
git checkout -b $new_branch

rm -rf $apply_log
git am $patch_email 2>&1 |tee $apply_log
if cat $apply_log | grep -q "git am --abort" ; then
	echo "apply patch failure"
	test_report_patch_apply_fail $base_commit $patch_email $apply_log $test_report
	send_patch_test_report $patch_email "WARNING" "apply patch failure" $test_report
	exit 0
fi

rm -rf build

meson build
if [ ! $? -eq 0 ]; then
	echo "meson build failure"
	test_report_patch_meson_build_fail $base_commit $patch_email $meson_log $test_report
	send_patch_test_report $patch_email "FAILURE" "meson build failure" $test_report
	exit 0
fi

ninja -C build |tee $ninja_log
if [ ! $? -eq 0 ]; then
	echo "ninja build failure"
	test_report_patch_ninja_build_fail $base_commit $patch_email $ninja_log $test_report
	send_patch_test_report $patch_email "FAILURE" "ninja build failure" $test_report
	exit 0
fi

fi

meson test -C build --suite DPDK:fast-tests --test-args="-l 0-7" -t 6
echo "test done!"
fail_num=`tail -n10 $test_log |sed -n 's/^Fail:[[:space:]]\+//p'`
if [ "$fail_num" != "0" ]; then
	echo "unit testing fail"
	test_report_patch_test_fail $base_commit $patch_email $test_report
	send_patch_test_report $patch_email "FAILURE" "Unit Testing FAIL" $test_report
	exit 0
fi

echo "unit testing pass"
test_report_patch_test_pass $base_commit $patch_email $test_report
send_patch_test_report $patch_email "SUCCESS" "Unit Testing PASS" $test_report

cd -
