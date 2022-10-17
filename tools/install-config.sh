#!/bin/sh -e

# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2022 Loongson

CI_CONFIG_DIR=/etc/dpdk
PWCLIENTRC_DIR=~/

if [ ! -d $CI_CONFIG_DIR ] ; then
	mkdir $CI_CONFIG_DIR
	if [ ! $? -eq 0 ] ; then
		printf "mkdir $CI_CONFIG_DIR failed\n" >&2
		exit 1
	fi
fi

install $(dirname $(readlink -e $0))/../config/ci.config $CI_CONFIG_DIR/ci.config
install $(dirname $(readlink -e $0))/../config/pwclientrc $PWCLIENTRC_DIR/.pwclientrc
