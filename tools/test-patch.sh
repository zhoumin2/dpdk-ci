#!/bin/bash

set -e

TOOLS_DIR=tools
DPDK_DIR=../dpdk

function print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) <patchwork_id>
	Test a patch.
	END_OF_HELP
}

function check_error() {
	if [ ! $? -eq 0 ]; then
		printf "error: $1"
		exit -1
	fi
}

if [ $# -lt 1 ]; then
	printf 'missing patch_id argument\n'
	print_usage >&2
	exit -1
fi

patch_id=$1
email_file=$patch_id.patch

$TOOLS_DIR/download-patch.sh $patch_id > $email_file
$TOOLS_DIR/filter-patch-email.sh $email_file > $email_file

if [ ! -s $email_file ]; then
	printf "$email_file is empty"
	exit -1
fi

cd $DPDK_DIR

git checkout main
check_error "git checkout to main failed!"

git checkout -b $patch_id
check_error "git checkout to $patch_id failed!"

git am ../$TOOLS_DIR/$email_file
check_error "git am ../$TOOLS_DIR/$email_file failed!"

ninja build
check_error "ninja build failed!"

meson test -C build --suite DPDK:fast-tests
check_error "meson test failed!"

cd -
