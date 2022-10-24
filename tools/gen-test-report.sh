#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

getheader() # <header_name> <email_file>
{
	sed "/^$1: */!d;s///;N;s,\n[[:space:]]\+, ,;s,\n.*,,;q" "$2" |
	sed 's,",\\",g'
}

write_patch_info() {
	submitter=$(getheader X-Patchwork-Submitter "$1")
	date=$(getheader Date "$1")

	echo "Submitter: $submitter"
	echo "Date: $date"
}

write_base_info() {
	echo "DPDK git baseline: Repo:dpdk"
	echo "  Branch: main"
	echo "  CommitID: $1"
}

write_env_result_fail() {
	cat <<- END_OF_HELP
	Test environment and result as below:

	+---------------------+----------------+
	|     Environment     | dpdk_unit_test |
	+=====================+================+
	| Loongnix-Server 8.3 | FAIL           |
	+---------------------+----------------+

	Loongnix-Server 8.3
	    Kernel: 4.19.190+
	    Compiler: gcc 8.3


	END_OF_HELP
}

write_env_result_pass() {
	cat <<- END_OF_HELP
	Test environment and result as below:

	+---------------------+----------------+
	|     Environment     | dpdk_unit_test |
	+=====================+================+
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

test_report_patch_apply_fail() {
	base_commit=$1
	email=$2
	log=$3
	report=$4
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_info $email
	write_base_info $base_commit
	echo ""
	echo "Apply patch $pwid failed:"
	echo ""
	write_apply_error_log $log
	) | cat - > $report
}

test_report_patch_meson_build_fail() {
	base_commit=$1
	email=$2
	log=$3
	report=$4
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_info $email
	write_base_info $base_commit
	echo ""
	echo "$pwid --> meson build failed"
	echo ""
	write_env_result_fail
	write_meson_build_error_log $log
	) | cat - > $report
}

test_report_patch_ninja_build_fail() {
	base_commit=$1
	email=$2
	log=$3
	report=$4
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_meteinfo $email
	write_base_info $base_commit
	echo ""
	echo "$pwid --> ninja build failed"
	echo ""
	write_env_result_fail
	write_ninja_build_error_log $log
	) | cat - > $report
}

test_report_patch_test_fail() {
	base_commit=$1
	email=$2
	report=$3
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_info $email
	write_base_info $base_commit
	echo ""
	echo "$pwid --> testing fail"
	echo ""
	write_env_result_fail
	) | cat - > $report
}

test_report_patch_test_pass() {
	base_commit=$1
	email=$2
	report=$3
	pwid=$(getheader X-Patchwork-Id $email)

	(
	write_patch_info $email
	write_base_info $base_commit
	echo ""
	echo "$pwid --> testing pass"
	echo ""
	write_env_result_pass
	) | cat - > $report
}

test_report_series_apply_fail() {
	base_commit=$1
	patches_dir=$2
	log=$3
	report=$4

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $base_commit
	echo ""
	echo "Apply patch set $patchset failed:"
	echo ""
	write_apply_error_log $log
	) | cat - > $report
}

test_report_series_meson_build_fail() {
	base_commit=$1
	patches_dir=$2
	log=$3
	report=$4

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $base_commit
	echo ""
	echo "$patchset --> meson build failed"
	echo ""
	write_env_result_fail
	write_meson_build_error_log $log
	) | cat - > $report
}

test_report_series_ninja_build_fail() {
	base_commit=$1
	patches_dir=$2
	log=$3
	report=$4

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $base_commit
	echo ""
	echo "$patchset --> ninja build failed"
	echo ""
	write_env_result_fail
	write_ninja_build_error_log $log
	) | cat - > $report
}

test_report_series_test_fail() {
	base_commit=$1
	patches_dir=$2
	report=$3

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $base_commit
	echo ""
	echo "$patchset --> testing fail"
	echo ""
	write_env_result_fail
	) | cat - > $report
}

test_report_series_test_pass() {
	base_commit=$1
	patches_dir=$2
	report=$3

	first_pwid=`head -1 $patches_dir/pwid_order.txt`
	last_pwid=`tail -1 $patches_dir/pwid_order.txt`
	if [ "$first_pwid" != "$last_pwid" ]; then
		patchset="$first_pwid-$last_pwid"
	else
		patchset="$first_pwid"
	fi

	(
	write_patch_info $patches_dir/$first_pwid.patch
	write_base_info $base_commit
	echo ""
	echo "$patchset --> testing pass"
	echo ""
	write_env_result_pass
	) | cat - > $report
}
