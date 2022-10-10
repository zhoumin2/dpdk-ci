#! /bin/sh -e

BRANCH_PREFIX=p
REUSE_PATCH=false

print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) [OPTIONS] <patch_id>

	Run dpdk ci tests for one patch specified by the patch_id
	END_OF_HELP
}

while getopts h:r arg ; do
	case $arg in
		r ) REUSE_PATCH=true ;;
		h ) print_usage ; exit 0 ;;
		? ) print_usage >&2 ; exit 1 ;;
	esac
done

shift $((OPTIND - 1))

if [ $# -lt 1 ]; then
	printf 'missing patch_id argument\n'
	print_usage >&2
	exit 1
fi

if [ -z "$DPDK_HOME" ]; then
	printf 'missing environment variable: $DPDK_HOME\n'
	exit 1
fi

patches_dir=$(dirname $(readlink -e $0))/../patches
if [ ! -d $patches_dir ]; then
	mkdir $patches_dir
fi

patch_id=$1
patch_email=$patches_dir/$patch_id.patch

if $REUSE_PATCH ; then
	if [ ! -f $patch_email ]; then
		$(dirname $(readlink -e $0))/download-patch.sh $patch_id > $patch_email
	fi
else
	$(dirname $(readlink -e $0))/download-patch.sh $patch_id > $patch_email
fi
echo "$($(dirname $(readlink -e $0))/filter-patch-email.sh < $patch_email)" > $patch_email

if [ ! -s $patch_email ]; then
	printf "$patch_email is empty\n"
	exit 1
fi

cd $DPDK_HOME

git checkout main

new_branch=$BRANCH_PREFIX-$patch_id
ret=`git branch --list $new_branch`
if [ ! -z "$ret" ] ; then
	git branch -D $new_branch
fi
git checkout -b $new_branch

git am $patch_email

rm -rf build

meson build

meson test -C build --suite DPDK:fast-tests

cd -
