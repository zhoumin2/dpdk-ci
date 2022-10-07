#!/bin/bash

set -e

TOOLS_DIR=./tools
DPDK_DIR=../dpdk

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) <patchwork_id>
	Test a patch.
	END_OF_HELP
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
git checkout -b $patch_id
git am ../tools/$email_file
ninja build
meson test -C build --suite DPDK:fast-tests
