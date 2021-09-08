#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2016 6WIND S.A.

print_usage () {
	cat <<- END_OF_HELP
	usage: $(basename $0) dpdk_dir < email

	Check email-formatted patch from stdin.
	This test runs checkpatch.pl of Linux via a script in dpdk_dir.
	END_OF_HELP
}

while getopts h arg ; do
	case $arg in
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done
shift $(($OPTIND - 1))
toolsdir=$(dirname $(readlink -m $0))/../tools
dpdkdir=$1
if [ -z "$dpdkdir" ] ; then
	printf 'missing argument\n\n' >&2
	print_usage >&2
	exit 1
fi

email=/tmp/$(basename $0 sh)$$
$toolsdir/filter-patch-email.sh >$email
trap "rm -f $email" INT EXIT

eval $($toolsdir/parse-email.sh $email)
# normal exit if no valid patch in the email
[ -n "$subject" -a -n "$from" ] || exit 0

failed=false

# check In-Reply-To for version > 1
if echo $subject | grep -qi 'v[2-9].*\]' && [ -z "$reply" ] ; then
	failed=true
	replyto_msg='Must be a reply to the first patch (--in-reply-to).\n\n'
fi

report=$(cd $dpdkdir && devtools/checkpatches.sh -q $email) || failed=true
report=$(echo "$report" | sed '1,/^###/d')

label='checkpatch'
$failed && status='WARNING' || status='SUCCESS'
$failed && desc='coding style issues' || desc='coding style OK'

echo "$replyto_msg$report" | $toolsdir/send-patch-report.sh \
	-t "$subject" -f "$from" -m "$msgid" -p "$pwid" -o "$listid" \
	-l "$label" -s "$status" -d "$desc"
