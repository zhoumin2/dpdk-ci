#!/bin/sh -e

prog="loongarch-dpdk-ci.sh"
DPDK=/home/zhoumin/dpdk
DPDK_CI=/home/zhoumin/dpdk-ci

ci_is_running() {
	num=$(ps -ef | grep $prog | grep -v grep | grep -v vim | wc -l)
	if [ "$num" != "0" ] ; then
		if [ "$num" != "1" ] ; then
			echo "Unexpected error: there are multiple instances for $prog"
			ps -ef | grep $prog | grep -v grep | grep -v vim
		fi
		return 0
	fi

	return 1
}

if ci_is_running ; then
	echo "$(basename $(readlink -e $0)) exits because $prog is running"
	exit 0
fi


failed=false
cd $DPDK_CI || failed=true
if $failed ; then
	echo "cd $DPDK_CI failed!"
	exit 1
fi

# Give two chances to restart quickly when start failed at the first time
for try in $(seq 3) ; do
	$DPDK_CI/tools/$prog $DPDK $DPDK_CI/last.txt || failed=true
	if ci_is_running ; then
		break
	fi
done
