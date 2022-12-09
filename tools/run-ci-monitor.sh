#!/bin/sh -e

prog="dpdk-ci-monitor.sh"
DPDK_CI=/home/zhoumin/dpdk-ci

monitor_is_running() {
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

if monitor_is_running ; then
	echo "$(basename $(readlink -e $0)) exits because $prog is running"
	exit 0
fi


failed=false
cd $DPDK_CI || failed=true
if $failed ; then
	echo "cd $DPDK_CI failed!"
	exit 1
fi

# Give one more chance to restart quickly when start failed at the first time
for try in $(seq 2) ; do
	failed=false
	$DPDK_CI/tools/$prog -p 5 || failed=true
	if ! $failed ; then
		break
	fi
	if monitor_is_running ; then
		break
	fi
done
