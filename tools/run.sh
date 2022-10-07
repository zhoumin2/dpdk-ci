#!/bin/bash

set -e

TOOLS_DIR=./tools
DPDK_DIR=../dpdk

$TOOLS_DIR/poll-pw patch DPDK last.txt $TOOLS_DIR/test-patch.sh
