#!/bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) [options]

	Run once dpdk ci monitor to check all series committed since last X
	days and to find out the series that didn't receive the test reports
	from Loongson.

	User can decide whether to resend the lost test reports or not.

	options:
	        -p pre   specify the checking period
	        -r       resend the lost test reports
	        -h       this help
	END_OF_HELP
}

get_patch_check=$(dirname $(readlink -e $0))/../tools/get-patch-check.sh
check_test_results=$(dirname $(readlink -e $0))/../tools/check_test_results.py

project=DPDK
resource_type=series

URL=http://patches.dpdk.org/api
URL="${URL}/events/?category=${resource_type}-completed"

label_compilation="loongarch compilation"
label_unit_testing="loongarch unit testing"

mail_send_interval=30

. $(dirname $(readlink -e $0))/load-ci-config.sh
sendmail=${DPDK_CI_MAILER:-/usr/sbin/sendmail}

writeheaders () # <subject> <ref> <to> [cc]
{
	echo "Content-Type: text/plain; charset=\"utf-8\""
	echo "Subject: "$1""
	#echo "In-Reply-To: $2"
	#echo "References: $2"
	echo "To: $2"
	[ -z "$3" ] || echo "Cc: $3"
	echo
}

smtp_user="qemudev@loongson.cn"

check_series_test_report() {
	series_id="$1"
	if [ -z "$series_id" ] ; then
		return 1
	fi

	url=http://patches.dpdk.org/api/series/$series_id
	echo "$(basename $0): request "$url" to get submitted time"

	failed=false
	resp=$(wget -q -O - "$url") || failed=true
	if $failed ; then
		echo "wget "$url" failed"
		echo "resp: "$resp""
		return 1
	fi

	failed=false
	sub_time=$(echo "$resp" | jq "try ( .date )") || failed=true
	if $failed ; then
		echo "jq handles for sub_time failed"
		echo "$resp"
		return 1
	fi
	sub_time=$(echo $sub_time |sed 's/"//g')
	echo "the sub_time for series $series_id: $sub_time"

	now_ts=$(date +%s)
	sub_ts=$(date +%s -d $sub_time)
	# change UTC time (UTC +0) to Beijing time (UTC +8)
	diff=$((now_ts-sub_ts-28800))
	# ignore the series submitted less than one hour
	if [ $diff -lt 3600 ] ; then
		echo "ignore series $series_id which submitted at $sub_time"
		return 1
	fi
	echo "$diff seconds passed since $series_id submitted"

	failed=false
	pids=$(echo "$resp" | jq "try ( .patches )" |jq "try ( .[] .id )") || failed=true
	if $failed ; then
		echo "jq handles for patch_ids failed"
		echo "$resp"
		return 1
	fi

	if [ -z "$(echo $pids | tr -d '\n')" ] ; then
		echo "cannot get pwid(s) for series $series_id"
		return 1
	fi

	echo "pwid(s) for series $series_id: $(echo $pids | tr '\n' ' ')"
	first_pwid=$(echo $pids | tr '\n' ' ' | awk '{print $1}')
	last_pwid=$(echo $pids | tr '\n' ' ' | awk '{print $NF}')
	echo "$series_id pwid(s) range: $first_pwid-$last_pwid"
	if [ $first_pwid != $last_pwid ] ; then
		echo "finding contexts for first pwid: $first_pwid ..."
		failed=false
		contexts=$($get_patch_check $first_pwid) || failed=true
		echo "contexts for first pwid $first_pwid: $contexts"
		if $failed ; then
			echo "find contexts for first pwid $first_pwid failed"
		else
			context=$(echo "$label_compilation" | sed 's/ /-/g')
			if echo "$contexts" | grep -qi "$context" ; then
				echo "test report for $first_pwid from "$context" existed!"
				return 0
			fi
		fi
	fi

	echo "finding contexts for last pwid: $last_pwid ..."
	failed=false
	contexts=$($get_patch_check $last_pwid) || failed=true
	echo "contexts for last pwid $last_pwid: $contexts"
	if $failed ; then
		echo "find contexts for last pwid $last_pwid failed"
		return 1
	fi

	write_series_url=false
	found=true
	patches_dir=$(dirname $(readlink -e $0))/../series/$series_id
	context=$(echo "$label_compilation" | sed 's/ /-/g')
	if echo "$contexts" | grep -qi "$context" ; then
		echo "test report for $last_pwid from "$context" existed!"
	else
		found=false
		echo "$label_compilation not found, notifying zhoumin ..."
		echo "http://patches.dpdk.org/project/dpdk/list/?series=$series_id&archive=both&state=*" >> $tmp_file
		write_series_url=true
		echo "$label_compilation not found for pwid $last_pwid: http://dpdk.org/patch/$last_pwid" >> $tmp_file

		mail_file=build_mail.txt
		mail_path=$patches_dir/$mail_file
		if $resend ; then
			if [ -f $mail_path ] ; then
				echo "try send build report for $series_id: $mail_path ..."
				cat $mail_path | $sendmail -f"$smtp_user" -t
				sleep $mail_send_interval
			fi
		fi
	fi

	context=$(echo "$label_unit_testing" | sed 's/ /-/g')
	if echo "$contexts" | grep -qi "$context" ; then
		echo "test report for $last_pwid from "$context" existed!"
	else
		found=false
		echo "$label_unit_testing not found, notifying zhoumin ..."
		if ! $write_series_url ; then
			echo "http://patches.dpdk.org/project/dpdk/list/?series=$series_id&archive=both&state=*" >> $tmp_file
		fi
		echo "$label_unit_testing not found for pwid $last_pwid: http://dpdk.org/patch/$last_pwid" >> $tmp_file

		mail_file=unit_test_mail.txt
		mail_path=$patches_dir/$mail_file
		if $resend ; then
			if [ -f $mail_path ] ; then
				echo "try send test report for $series_id: $mail_path ..."
				cat $mail_path | $sendmail -f"$smtp_user" -t
				sleep $mail_send_interval
			fi
		fi
	fi

	if ! $found ; then
		echo "" >> $tmp_file
		return 1
	fi

	return 0
}


pre=""
resend=false
while getopts hp:r arg ; do
	case $arg in
		p ) pre=$OPTARG ;;
		h ) print_usage ; exit 0 ;;
		r ) resend=true ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done

if [ -z "$pre" ] ; then
	echo "Missing -p argument!"
	print_usage
	exit 1
fi

if [ -z "`echo $pre | sed -n '/^[0-9][0-9]*$/p'`" ] ; then
	echo "The argument for -p should be numerical!"
	print_usage
	exit 1
fi

report_done_ids_file=/tmp/report_done_pw_${resource_type}_ids
if [ ! -f "$report_done_ids_file" ] ; then
	touch $report_done_ids_file
fi

tmp_file=`mktemp -t ci_monitor.XXXXXX`
page=1
hms=$(date +%T)
pre_day=$(date -d "$pre day ago" +%Y-%m-%dT$hms)
while true ; do
	echo "${URL}&page=${page}&since=${pre_day}"
	sids=$(curl -s "${URL}&page=${page}&since=${pre_day}" |
		jq "try ( .[] | select( .project.name == \"$project\" ) )" |
		jq "try ( .payload.${resource_type}.id )")
	echo "fetched series ids: $(echo $sids | tr '\n' ' ')"
	echo ""
	[ -z "$(echo $sids | tr -d '\n')" ] && break
	for id in $sids ; do
		if grep -q "^${id}$" $report_done_ids_file ; then
			continue
		fi
		failed=false
		check_series_test_report $id || failed=true
		echo ""
		if ! $failed ; then
			echo $id >>$report_done_ids_file
		fi
	done
	page=$(($page + 1))
done

if test -s $tmp_file ; then
	(
	writeheaders "Test reports not found!" 'zhoumin@loongson.cn'
	cat $tmp_file
	) | $sendmail -f"$smtp_user" -t
else
	echo "No missed test report found!"
	exit 0
fi

python3 $check_test_results $pre $tmp_file
if test -s $tmp_file ; then
	(
	writeheaders "Summaries for test results" 'zhoumin@loongson.cn'
	cat $tmp_file
	) | $sendmail -f"$smtp_user" -t
else
	echo "Get summaries failed for test results!"
	exit 0
fi

#rm $tmp_file
