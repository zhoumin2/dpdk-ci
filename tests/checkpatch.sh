#! /bin/sh -e

# BSD LICENSE
#
# Copyright 2016 6WIND S.A.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in
#     the documentation and/or other materials provided with the
#     distribution.
#   * Neither the name of 6WIND S.A. nor the names of its
#     contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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
report=$($dpdkdir/scripts/checkpatches.sh -q $email) || failed=true
report=$(echo "$report" | sed '1,/^###/d')

label='checkpatch'
$failed && status='WARNING' || status='SUCCESS'
$failed && desc='coding style issues' || desc='coding style OK'

echo "$report" | $toolsdir/send-patch-report.sh \
	-t "$subject" -f "$from" -m "$msgid" -p "$pwid" -o "$listid" \
	-l "$label" -s "$status" -d "$desc"
