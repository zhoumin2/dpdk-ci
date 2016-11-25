#! /bin/sh

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
	usage: $(basename $0) <report_url>

	Add or update a check in patchwork based on a test report.
	The argument specifies only the last URL parts of the test-report
	mailing list archives (month/id.html).
	END_OF_HELP
}

. $(dirname $(readlink -e $0))/load-ci-config.sh
pwclient=${DPDK_CI_PWCLIENT:-$(dirname $(readlink -m $0))/pwclient}

while getopts h arg ; do
	case $arg in
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done
if [ -z "$1" ] ; then
	printf 'missing argument\n\n' >&2
	print_usage >&2
	exit 1
fi

url="http://dpdk.org/ml/archives/test-report/$1"
mmarker='<!--beginarticle-->'
for try in $(seq 20) ; do
	[ -z "$report" -o $try -ge 19 ] || continue # 2 last tries if got something
	[ $try -le 1 ] || sleep 3 # no delay before first try
	report=$(curl -sf $url | grep -m1 -A9 "$mmarker") || continue
	echo "$report" | grep -q '^_.*_$' && break || continue
done
if [ -z "$report" ] ; then
	echo "cannot download report at $url" >&2
	exit 2
fi

pwid=$(echo "$report" | sed -rn 's,.*http://.*dpdk.org/.*patch/([0-9]+).*,\1,p')
label=$(echo "$report" | sed -n 's,.*Test-Label: *,,p')
status=$(echo "$report" | sed -n 's,.*Test-Status: *,,p')
desc=$(echo "$report" | sed -n 's,^_\(.*\)_$,\1,p')
case $status in
	'SUCCESS') pwstatus='success' ;;
	'WARNING') pwstatus='warning' ;;
	'FAILURE') pwstatus='fail' ;;
esac
printf 'id = %s\nlabel = %s\nstatus = %s/%s %s\nurl = %s\n' \
	"$pwid" "$label" "$status" "$pwstatus" "$desc" "$url"
[ -n "$pwid" -a -n "$label" -a -n "$status" -a -n "$desc" ] || exit 3

$pwclient check-create -c "$label" -s "$pwstatus" -d "$desc" -u "$url" $pwid
