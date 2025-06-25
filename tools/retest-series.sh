#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2024 Loongson

BRANCH_PREFIX=s
REUSE_PATCH=false
RETEST_TIMES=-1
KEEP_BASE=false
REBASE=""
last_gpr_file="last_gpr.txt"

parse_email=$(dirname $(readlink -e $0))/../tools/parse-email.sh
send_series_report=$(dirname $(readlink -e $0))/../tools/send-series-report-la.sh
download_series=$(dirname $(readlink -e $0))/../tools/download-series.sh
get_patch_check=$(dirname $(readlink -e $0))/../tools/get-patch-check.sh
parse_testlog=$(dirname $(readlink -e $0))/../tools/parse_testlog.py
pw_maintainers_cli=$(dirname $(readlink -e $0))/../tools/pw_maintainers_cli.py
repo_branch_cfg=$(dirname $(readlink -e $0))/../config/repo_branch.cfg
repo_branch_cfg_v2=$(dirname $(readlink -e $0))/../config/repo_branch_v2.cfg
token_file=$(dirname $(readlink -e $0))/../.pw_token.dat

label_compilation="loongarch compilation"
label_unit_testing="loongarch unit testing"

status_warning="WARNING"
status_failure="FAILURE"
status_success="SUCCESS"

export LC="en_US.UTF-8"
export LANG="en_US.UTF-8"

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) [OPTIONS] <series_id>

	options:
		-t     retest times for <series_id>
		-b     rebase for <series_id>

	Run dpdk ci tests for one series specified by the series_id
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

	if echo "$contexts" | grep -qi "$context" ; then
	      echo "test report for $pwid from "$context" existed!"
	else
	      echo "not found context: "$context""
	fi
}

send_series_test_report() {
	series_id=$1
	patches_dir=$2
	label=$3
	status=$4
	desc=$5
	report=$6
	mail_file=$7

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	mail_path=$patches_dir/$mail_file

	target_pwid=$last_pwid
	if [ "$desc" = "$desc_apply_failure" ] ; then
		target_pwid=$first_pwid
	fi

	check_patch_check $target_pwid "$label"

	pwids=$first_pwid
	if [ $first_pwid != $last_pwid ] ; then
		pwids=$first_pwid-$last_pwid
	fi

	eval $($parse_email $patches_dir/$target_pwid.patch)
	if [ -z "$subject" -o -z "$from" -o -z "$msgid" \
		-o -z "$pwid" -o -z "$listid" ] ; then
		echo "parse email failed: $patches_dir/$target_pwid.patch"
		exit 1
	fi

	#from="zhoumin@loongson.cn"
	echo "send test report for series $series_id to $from"
	$send_series_report -t "$subject" -f "$from" -m "$msgid" -p "$target_pwid" \
		-r "$pwids" -o "$listid" -l "$label" \
		-s "$status" -d "$desc" -k "$mail_path" < $report
}

try_apply() {
	repo=$1
	need_send=$2

	failed=false
	ori_base=$(cat $repo_branch_cfg | jq "try ( .\"$repo\" )" |sed 's,",,g') || failed=true
	if $failed -o -z "$ori_base" ; then
		echo "get ori_base branch for repo $repo failed"
		exit 1
	fi

	failed=false
	base=$(cat $repo_branch_cfg_v2 | jq "try ( .\"$repo\" )" |sed 's,",,g') || failed=true
	if $failed -o -z "$base" ; then
		echo "get base branch for repo $repo failed"
		exit 1
	fi

	echo "Developer request rebase: $REBASE"
	if [ -n $REBASE ]; then
		base=$REBASE
	fi
	echo "Final base: $base"

	# Use the DPDK github mirrors as the remote repo
	# DPDK_HOME=/home/zhoumin/$repo
	DPDK_HOME=/home/zhoumin/gh_dpdk
	if [ ! -d "$DPDK_HOME" ] ; then
		echo "$DPDK_HOME is not directory"
		exit 1
	fi

	apply_log=$DPDK_HOME/apply-log.txt
	meson_log=$DPDK_HOME/build/meson-logs/meson-log.txt
	ninja_log=$DPDK_HOME/build/ninja-log.txt
	testlog_json=$DPDK_HOME/build/meson-logs/testlog.json
	testlog_txt=$DPDK_HOME/build/meson-logs/testlog.txt
	test_report=$DPDK_HOME/test-report.txt
	build_mail=build_mail.txt
	unit_test_mail=unit_test_mail.txt

	cd $DPDK_HOME

	if git status | grep -q "git am --abort" ; then
	       git am --abort
	fi

	if git status | grep -q "git rebase --abort" ; then
		git rebase --abort
	fi

	git checkout unused
	git branch -D $base
	git checkout origin/$base -b $base

	if ! $KEEP_BASE ; then
		need_update=true
		if [ -f "$last_gpr_file" ] ; then
			failed=false
			last_gpr=$(date +%s -d "$(cat $last_gpr_file | tr '\n' ' ')") || failed=true
			if ! $failed ; then
				now_ts=$(date +%s)
				diff=$((now_ts-last_gpr))
				if [ $diff -lt 3600 ] ; then
					echo "no need to update git base"
					need_update=false
				fi
			fi
		fi
		if $need_update ; then
			echo "need to update git base"
			timeout -s SIGKILL 60s git pull --rebase
			date_now=$(date --utc '+%FT%T')
			echo $date_now >$last_gpr_file
		fi
	fi
	base_commit=`git log -1 --format=oneline |awk '{print $1}'`

	new_branch=$BRANCH_PREFIX-$series_id
	ret=`git branch --list $new_branch`
	if [ ! -z "$ret" ]; then
		git branch -D $new_branch
	fi
	git checkout -b $new_branch

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
			echo "This patch cannot apply on $repo: $patch_email"
			if $need_send ; then
				failed=false
				test_report_series_apply_fail $repo $ori_base $base_commit $patches_dir $apply_log $test_report
				send_series_test_report $series_id $patches_dir "$label_compilation" $status_warning "$desc_apply_failure" $test_report $build_mail || failed=true
				if $failed ; then
				       echo "send series test report for $series_id failed!"
				fi
			fi
			applied=false
			break
		fi

		git am $patch_email
		applied=true
	done < $patches_dir/pwid_order.txt
}

while getopts b:hkrt: arg ; do
	case $arg in
		b ) REBASE=$OPTARG ;;
		k ) KEEP_BASE=true ;;
		r ) REUSE_PATCH=true ;;
		t ) RETEST_TIMES=$OPTARG ;;
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done

if [ -z "`echo $RETEST_TIMES| sed -n '/^[1-9][0-9]*$/p'`" ]; then
        printf "retest times is not valid: $RETEST_TIMES\n"
        exit 1
fi

RETEST_TIMES=$((RETEST_TIMES+0))
if [ $RETEST_TIMES -lt 1 ]; then
        printf "retest times is not valid: $RETEST_TIMES\n"
        exit 1
fi

desc_apply_failure="apply patch failure RETEST #"$RETEST_TIMES
desc_meson_build_failure="meson build failure RETEST #"$RETEST_TIMES
desc_ninja_build_failure="ninja build failure RETEST #"$RETEST_TIMES
desc_build_pass="Compilation OK RETEST #"$RETEST_TIMES
desc_unit_test_fail="Unit Testing FAIL RETEST #"$RETEST_TIMES
desc_unit_test_pass="Unit Testing PASS RETEST #"$RETEST_TIMES

shift $((OPTIND - 1))

if [ $# -lt 1 ]; then
	printf 'missing series_id argument\n'
	print_usage >&2
	exit 1
fi

series_id=$1
printf "To retest series: $series_id"
patches_dir=$(dirname $(readlink -e $0))/../series/$series_id

# This can also be "-g"
g_opt=""

if $REUSE_PATCH ; then
	if [ ! -d $patches_dir ] ; then
		failed=false
		$download_series $g_opt $series_id $patches_dir || failed=true
		if $failed ; then
			echo "download series failed"
			exit 1
		fi
	fi
else
	failed=false
	$download_series $g_opt $series_id $patches_dir || failed=true
	if $failed ; then
		echo "download series failed"
		exit 1
	fi
fi

export PW_SERVER="https://patches.dpdk.org/api/1.2/"
export PW_PROJECT=dpdk
export PW_TOKEN=$(cat $token_file)
export MAINTAINERS_FILE_PATH=/home/zhoumin/gh_dpdk/MAINTAINERS

default_repo=dpdk

failed=false
repo=$(timeout -s SIGKILL 120s python3.8 $pw_maintainers_cli --type series list-trees $series_id) || failed=true
if $failed ; then
	echo "list trees for series $series_id timeout, exit ..."
	exit 1
elif [ -z "$repo" ] ; then
	echo "list trees for series $series_id failed, default to '$default_repo'"
	repo=$default_repo
else
	echo "list trees for series $series_id: $repo"
fi

. $(dirname $(readlink -e $0))/gen-test-report.sh

applied=false

# Firstly, try to apply on prefer repo gotten from pw_maintainers_cli.py
prefer_repo=$repo
echo "try to apply on $repo ..."
try_apply $repo false

# Secondly, try to apply on default repo if failed on prefer repo
if ! $applied ; then
	if [ $repo != $default_repo ] ; then
		echo "apply patch on $repo failed, try to apply on $default_repo ..."
		repo=$default_repo
		try_apply $repo false
	fi
fi

# Thirdly, try to apply on prefer repo again and send email for failure
if ! $applied ; then
	repo=$prefer_repo
	echo "try to apply on $repo again and send email if failed ..."
	try_apply $repo true
fi

if ! $applied ; then
	echo "Cannot apply patch(es) for series $series_id, please check series directory and related repos"
	echo "Test will not be executed!"
	# exit successfully to skip this series
	exit 0
fi

rm -rf build

failed=false
meson build || failed=true
if $failed ; then
	echo "meson build failure"
	test_report_series_meson_build_fail $repo $ori_base $base_commit $patches_dir $meson_log $test_report
	send_series_test_report $series_id $patches_dir "$label_compilation" $status_failure "$desc_meson_build_failure" $test_report $build_mail
	exit 0
fi

failed=false
ninja -C build &> $ninja_log || failed=true
if $failed ; then
	echo "ninja build failure"
	test_report_series_ninja_build_fail $repo $ori_base $base_commit $patches_dir $ninja_log $test_report
	send_series_test_report $series_id $patches_dir "$label_compilation" $status_failure "$desc_ninja_build_failure" $test_report $build_mail
	exit 0
fi

echo "meson & ninja build pass"
test_report_series_build_pass $repo $ori_base $base_commit $patches_dir $test_report
send_series_test_report $series_id $patches_dir "$label_compilation" $status_success "$desc_build_pass" $test_report $build_mail

failed=false
meson test -C build --suite DPDK:fast-tests --test-args="-l 0-7" -t 8 || failed=true
echo "test done!"
if $failed ; then
	echo "unit testing fail"
	test_report_series_test_fail $repo $ori_base $base_commit $patches_dir $testlog_json $testlog_txt $test_report
	send_series_test_report $series_id $patches_dir "$label_unit_testing" $status_failure "$desc_unit_test_fail" $test_report $unit_test_mail
	exit 0
fi

echo "unit testing pass"
test_report_series_test_pass $repo $ori_base $base_commit $patches_dir $testlog_json $testlog_txt $test_report
send_series_test_report $series_id $patches_dir "$label_unit_testing" $status_success "$desc_unit_test_pass" $test_report $unit_test_mail

cd -
