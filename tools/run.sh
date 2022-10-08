#! /bin/sh -e

TOOLS_DIR=tools
DPDK_DIR=../dpdk
LAST_FILE=last.txt
TEST=true
PROXY=""

function init_last() {
	echo `date "+%Y-%m-%dT00:00:00"` > $LAST_FILE
}

function setup() {
	if $TEST; then
		init_last
		#PROXY=proxychains
	fi

	cd $DPDK_DIR
	git checkout main
	$PROXY git pull --rebase
	cd -
}

setup

$TOOLS_DIR/poll-pw patch DPDK $LAST_FILE $TOOLS_DIR/test-patch.sh
