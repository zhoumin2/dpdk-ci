#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2016 6WIND S.A.

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
	url="http://patches.dpdk.org/patch/$pwid/mbox/"
	curl -sf $url
else
	$pwclient view $pwid
fi |
sed '/^Subject:/{s/\(\[[^],]*\)/\1] [PATCH/;s/,/ /g}'
