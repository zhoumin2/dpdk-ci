#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2016 6WIND S.A.

print_usage () {
	cat <<- END_OF_HELP
	usage: $(basename $0) [options] < report

	Send test report in a properly formatted email for patchwork integration.
	The report is submitted to this script via stdin.

	options:
	        -t title    subject of the patch email
	        -f from     sender of the patch email
	        -m msgid    id of the patch email
	        -p pwid     id of the patch in patchwork (retrieved from msgid otherwise)
	        -o listid   origin of the patch
	        -l label    title of the test (slug formatted)
	        -s status   one of these test results: SUCCESS, WARNING, FAILURE
	        -d desc     few words to better describe the status
	        -h          this help
	END_OF_HELP
}

. $(dirname $(readlink -e $0))/load-ci-config.sh
sendmail=${DPDK_CI_MAILER:-/usr/sbin/sendmail}
pwclient=${DPDK_CI_PWCLIENT:-$(dirname $(readlink -m $0))/pwclient}

unset title
unset from
unset msgid
unset pwid
unset listid
unset label
unset status
unset desc
while getopts d:f:hl:m:o:p:s:t: arg ; do
	case $arg in
		t ) title=$OPTARG ;;
		f ) from=$OPTARG ;;
		m ) msgid=$OPTARG ;;
		p ) pwid=$OPTARG ;;
		o ) listid=$OPTARG ;;
		l ) label=$(echo $OPTARG | sed 's,[[:space:]]\+,-,g') ;;
		s ) status=$OPTARG ;;
		d ) desc=$OPTARG ;;
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done
shift $(($OPTIND - 1))
if [ -t 0 ] ; then
	printf 'nothing to read on stdin\n\n' >&2
	print_usage >&2
	exit 1
fi
report=$(cat)

writeheaders () # <subject> <ref> <to> [cc]
{
	echo "Subject: $1"
	echo "In-Reply-To: $2"
	echo "References: $2"
	echo "To: $3"
	[ -z "$4" ] || echo "Cc: $4"
	echo
}

writeheadlines () # <label> <status> <description> [pwid]
{
	echo "Test-Label: $1"
	echo "Test-Status: $2"
	[ -z "$4" ] || echo "http://dpdk.org/patch/$4"
	echo
	echo "_${3}_"
	echo
}

if echo "$listid" | grep -q 'dev.dpdk.org' ; then
	# get patchwork id
	if [ -z "$pwid" -a -n "$msgid" ] ; then
		for try in $(seq 20) ; do
			pwid=$($pwclient list -f '%{id}' -m "$msgid")
			[ -n "$pwid" ] && break || sleep 7
		done
	fi
	[ -n "$pwid" ] || pwid='?'
	# send public report
	subject=$(echo $title | sed 's,\[dpdk-dev\] ,,')
	[ "$status" = 'SUCCESS' ] && cc='' || cc="$from"
	(
	writeheaders "|$status| pw$pwid $subject" "$msgid" 'test-report@dpdk.org' "$cc"
	writeheadlines "$label" "$status" "$desc" "$pwid"
	echo "$report"
	) | $sendmail -t
else
	# send private report
	(
		writeheaders "Re: $title" "$msgid" "$from"
		writeheadlines "$label" "$status" "$desc"
		echo "$report"
	) | $sendmail -t
fi
