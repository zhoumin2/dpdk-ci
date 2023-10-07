#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2016 6WIND S.A.

format_mailaddr=$(dirname $(readlink -e $0))/../tools/format_mail_address.py

print_usage () {
	cat <<- END_OF_HELP
	usage: $(basename $0) <email_file>

	Parse basic headers of the email
	and print them as shell variable assignments to evaluate.
	END_OF_HELP
}

while getopts h arg ; do
	case $arg in
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done
shift $(($OPTIND - 1))
if [ -z "$1" ] ; then
	printf 'file argument is missing\n\n' >&2
	print_usage >&2
	exit 1
fi

getheader () # <header_name> <email_file>
{
	sed "/^$1: */!d;s///;N;s,\n[[:space:]]\+, ,;s,\n.*,,;q" "$2" |
	sed 's,",\\",g'
}

subject=$(getheader Subject "$1")
from=$(getheader From "$1")
msgid=$(getheader Message-Id "$1")
[ -n "$msgid" ] || msgid=$(getheader Message-ID "$1")
[ -n "$msgid" ] || msgid=$(getheader Message-id "$1")
pwid=$(getheader X-Patchwork-Id "$1")
listid=$(getheader List-Id "$1")
reply=$(getheader In-Reply-To "$1")

from="`python3 $format_mailaddr "$from"`"
cat <<- END_OF_HEADERS
	subject="$subject"
	from="$from"
	msgid="$msgid"
	pwid="$pwid"
	listid="$listid"
	reply="$reply"
END_OF_HEADERS
