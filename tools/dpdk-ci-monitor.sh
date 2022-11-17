#!/bin/sh -e

get_patch_check=$(dirname $(readlink -e $0))/../tools/get-patch-check.sh

project=DPDK
resource_type=series

URL=http://patches.dpdk.org/api
URL="${URL}/events/?category=${resource_type}-completed"

label_compilation="loongarch compilation"
label_unit_testing="loongarch unit testing"

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
	last_pwid=$(echo $pids | tr '\n' ' ' | awk '{print $NF}')

	echo "finding contexts for $last_pwid ..."

	failed=false
	contexts=$($get_patch_check $last_pwid) || failed=true
	echo "contexts for $last_pwid: $contexts"
	if $failed ; then
		echo "find contexts for $last_pwid failed"
		return 1
	fi

	context=$(echo "$label_compilation" | sed 's/ /-/g')
	if echo "$contexts" | grep -qi "$context" ; then
		echo "test report for $last_pwid from "$context" existed!"
	else
		echo "$label_compilation not found, notifying zhoumin ..."
		(
		writeheaders "$label_compilation not found for pwid $last_pwid" 'zhoumin@loongson.cn' 'zhoumin@bupt.cn'
		echo "http://dpdk.org/patch/$last_pwid"
		) | $sendmail -f"$smtp_user" -t
		return 0
	fi

	context=$(echo "$label_unit_testing" | sed 's/ /-/g')
	if echo "$contexts" | grep -qi "$context" ; then
		echo "test report for $last_pwid from "$context" existed!"
	else
		echo "$label_unit_testing not found, notifying zhoumin ..."
		(
		writeheaders "$label_unit_testing not found for pwid $last_pwid" 'zhoumin@loongson.cn' 'zhoumin@bupt.cn'
		echo "http://dpdk.org/patch/$last_pwid"
		) | $sendmail -f"$smtp_user" -t
		return 0
	fi

	return 0
}

if [ -z "$1" ] ; then
	pre=1
else
	pre=$1
fi

report_done_ids_file=/tmp/report_done_pw_${resource_type}_ids
if [ ! -f "$report_done_ids_file" ] ; then
	touch $report_done_ids_file
fi

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
