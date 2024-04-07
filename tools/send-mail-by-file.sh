#! /bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) <mail_file>

	Send an email whose contents are specified by a file.
	END_OF_HELP
}

. $(dirname $(readlink -e $0))/load-ci-config.sh
sendmail=${DPDK_CI_MAILER:-/usr/sbin/sendmail}

file=$1
if [ -z "$file" ] ; then
	printf "missing argument\n\n" >&2
	print_usage >&2
	exit 1
fi

if [ ! -f "$file" ] ; then
	printf "$file is not an email file\n\n" >&2
	print_usage >&2
	exit 1
fi

smtp_user="qemudev@loongson.cn"
cat $file | $sendmail -f"$smtp_user" -t
