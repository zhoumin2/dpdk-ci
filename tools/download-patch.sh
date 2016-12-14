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
	usage: $(basename $0) [-g] <patchwork_id>

	Download a patch from patchwork through pwclient XML-RPC (default)
	or curl HTTP GET (option -g).
	END_OF_HELP
}

. $(dirname $(readlink -e $0))/load-ci-config.sh
pwclient=${DPDK_CI_PWCLIENT:-$(dirname $(readlink -m $0))/pwclient}

http_get=false
while getopts gh arg ; do
	case $arg in
		g ) http_get=true ;;
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done
shift $(($OPTIND - 1))
pwid=$1
if [ -z "$pwid" ] ; then
	printf 'missing argument\n\n' >&2
	print_usage >&2
	exit 1
fi

if $http_get ; then
	url="http://dpdk.org/dev/patchwork/patch/$pwid/mbox/"
	curl -sf $url
else
	$pwclient view $pwid
fi |
sed '/^Subject:/{s/\(\[[^],]*\)/\1] [PATCH/;s/,/ /g}'
