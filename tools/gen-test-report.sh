#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

getheader() # <header_name> <email_file>
{
	sed "/^$1: */!d;s///;N;s,\n[[:space:]]\+, ,;s,\n.*,,;q" "$2" |
	sed 's,",\\",g'
}

get_submitter() {
	prefix="X-Patchwork-Submitter"
	sed "/^${prefix}: */!d;s///;N;s,\n[[:space:]]\+, ,;s,\n.*,,;q" "$1" |
	sed 's,",,g'
}

write_patch_info() {
	submitter=$(get_submitter "$1")
	date=$(getheader Date "$1")

	echo "Submitter: $submitter"
	echo "Date: $date"
}

write_base_info() {
	repo=$1
	branch=$2
	commit=$3

	echo "DPDK git baseline: Repo:$repo"
	echo "  Branch: $branch"
	echo "  CommitID: $commit"
}

write_env_result_compilation_fail() {
	cat <<- END_OF_HELP
	Test environment and result as below:

	+---------------------+----------------+
	|     Environment     | compilation    |
	+---------------------+----------------+
	| Loongnix-Server 8.3 | FAIL           |
	+---------------------+----------------+

	Loongnix-Server 8.3
	    Kernel: 4.19.190+
	    Compiler: gcc 8.3


	END_OF_HELP
}

write_env_result_compilation_pass() {
	cat <<- END_OF_HELP
	Test environment and result as below:

	+---------------------+----------------+
	|     Environment     | compilation    |
	+---------------------+----------------+
	| Loongnix-Server 8.3 | PASS           |
	+---------------------+----------------+

	Loongnix-Server 8.3
	    Kernel: 4.19.190+
	    Compiler: gcc 8.3


	END_OF_HELP
}

write_env_result_unit_test_fail() {
	cat <<- END_OF_HELP
	Test environment and result as below:

	+---------------------+----------------+
	|     Environment     | dpdk_unit_test |
	+---------------------+----------------+
	| Loongnix-Server 8.3 | FAIL           |
	+---------------------+----------------+

	Loongnix-Server 8.3
	    Kernel: 4.19.190+
	    Compiler: gcc 8.3


	END_OF_HELP
}

write_env_result_unit_test_pass() {
	cat <<- END_OF_HELP
	Test environment and result as below:

	+---------------------+----------------+
	|     Environment     | dpdk_unit_test |
	+---------------------+----------------+
	| Loongnix-Server 8.3 | PASS           |
	+---------------------+----------------+

	Loongnix-Server 8.3
	    Kernel: 4.19.190+
	    Compiler: gcc 8.3


	END_OF_HELP
}

write_apply_error_log() {
	log=$1

	cat $log
}

write_meson_build_error_log() {
	log=$1

	echo "Meson build logs:"
	echo "-------------------------------BEGIN LOGS----------------------------"

	start_print=false
	while read line ; do
		if $start_print ; then
			echo $line
			continue
		fi

		if echo $line | grep -q "\--- stderr ---" ; then
			start_print=true
			echo $line
			continue
		fi
	done < $log

	echo "-------------------------------END LOGS------------------------------"

}

write_ninja_build_error_log() {
	log=$1

	echo "Ninja build logs:"
	echo "-------------------------------BEGIN LOGS----------------------------"

	start_print=false
	while read line ; do
		if $start_print ; then
			echo $line
			continue
		fi

		if echo $line | grep -q "FAILED:" ; then
			start_print=true
			echo $line
			continue
		fi
	done < $log

	echo "-------------------------------END LOGS------------------------------"
}

write_test_result_fail() {
	testlog_json=$1
	testlog_txt=$2

	echo "Test result details:"
	$parse_testlog --summary $1 $2

	echo ""
	echo "Test logs for failed test cases:"
	$parse_testlog --faillogs $1 $2
}

write_test_result_pass() {
	testlog_json=$1
	testlog_txt=$2

	echo "Test result details:"
	$parse_testlog --summary $1 $2
}

test_report_patch_apply_fail() {
	repo=$1
	branch=$2
	base_commit=$3
	email=$4
	log=$5
	report=$6
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_info $email
	write_base_info $repo $branch $base_commit
	echo ""
	echo "Apply patch $pwid failed:"
	echo ""
	write_apply_error_log $log
	) | cat - > $report
}

test_report_patch_meson_build_fail() {
	repo=$1
	branch=$2
	base_commit=$3
	email=$4
	log=$5
	report=$6
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_info $email
	write_base_info $repo $branch $base_commit
	echo ""
	echo "$pwid --> meson build failed"
	echo ""
	write_env_result_compilation_fail
	write_meson_build_error_log $log
	) | cat - > $report
}

test_report_patch_ninja_build_fail() {
	repo=$1
	branch=$2
	base_commit=$3
	email=$4
	log=$5
	report=$6
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_info $email
	write_base_info $repo $branch $base_commit
	echo ""
	echo "$pwid --> ninja build failed"
	echo ""
	write_env_result_compilation_fail
	write_ninja_build_error_log $log
	) | cat - > $report
}

test_report_patch_build_pass() {
	repo=$1
	branch=$2
	base_commit=$3
	email=$4
	report=$5
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_info $email
	write_base_info $repo $branch $base_commit
	echo ""
	echo "$pwid --> meson & ninja build successfully"
	echo ""
	write_env_result_compilation_pass
	) | cat - > $report
}

test_report_patch_test_fail() {
	repo=$1
	branch=$2
	base_commit=$3
	email=$4
	report=$5
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_info $email
	write_base_info $repo $branch $base_commit
	echo ""
	echo "$pwid --> testing fail"
	echo ""
	write_env_result_unit_test_fail
	write_test_result_fail $testlog_json $testlog_txt
	) | cat - > $report
}

test_report_patch_test_pass() {
	repo=$1
	branch=$2
	base_commit=$3
	email=$4
	report=$5
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_info $email
	write_base_info $repo $branch $base_commit
	echo ""
	echo "$pwid --> testing pass"
	echo ""
	write_env_result_unit_test_pass
	write_test_result_pass $testlog_json $testlog_txt
	) | cat - > $report
}

test_report_series_apply_fail() {
	repo=$1
	branch=$2
	base_commit=$3
	patches_dir=$4
	log=$5
	report=$6

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $repo $branch $base_commit
	echo ""
	echo "Apply patch set $patchset failed:"
	echo ""
	write_apply_error_log $log
	) | cat - > $report
}

test_report_series_meson_build_fail() {
	repo=$1
	branch=$2
	base_commit=$3
	patches_dir=$4
	log=$5
	report=$6

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $repo $branch $base_commit
	echo ""
	echo "$patchset --> meson build failed"
	echo ""
	write_env_result_compilation_fail
	write_meson_build_error_log $log
	) | cat - > $report
}

test_report_series_ninja_build_fail() {
	repo=$1
	branch=$2
	base_commit=$3
	patches_dir=$4
	log=$5
	report=$6

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $repo $branch $base_commit
	echo ""
	echo "$patchset --> ninja build failed"
	echo ""
	write_env_result_compilation_fail
	write_ninja_build_error_log $log
	) | cat - > $report
}

test_report_series_build_pass() {
	repo=$1
	branch=$2
	base_commit=$3
	patches_dir=$4
	report=$5

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $repo $branch $base_commit
	echo ""
	echo "$patchset --> meson & ninja build successfully"
	echo ""
	write_env_result_compilation_pass
	) | cat - > $report
}

test_report_series_test_fail() {
	repo=$1
	branch=$2
	base_commit=$3
	patches_dir=$4
	testlog_json=$5
	testlog_txt=$6
	report=$7

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $repo $branch $base_commit
	echo ""
	echo "$patchset --> testing fail"
	echo ""
	write_env_result_unit_test_fail
	write_test_result_fail $testlog_json $testlog_txt
	) | cat - > $report
}

test_report_series_test_pass() {
	repo=$1
	branch=$2
	base_commit=$3
	patches_dir=$4
	testlog_json=$5
	testlog_txt=$6
	report=$7

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $repo $branch $base_commit
	echo ""
	echo "$patchset --> testing pass"
	echo ""
	write_env_result_unit_test_pass
	write_test_result_pass $testlog_json $testlog_txt
	) | cat - > $report
}
