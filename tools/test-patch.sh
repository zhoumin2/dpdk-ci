#! /bin/sh -e

BRANCH_PREFIX=p

function print_usage() {
	cat <<- END_OF_HELP
	usage: $(basename $0) <patch_id>

	Test one patch.
	END_OF_HELP
}

function check_error() {
	if [ ! $? -eq 0 ]; then
		printf "error: $1"
		exit 1
	fi
}

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
	check_error "mkdir $patches_dir failed\n"
fi

patch_id=$1
patch_email=$patches_dir/$patch_id.patch

$(dirname $(readlink -e $0))/download-patch.sh $patch_id > $patch_email
echo "$($(dirname $(readlink -e $0))/filter-patch-email.sh < $patch_email)" > $patch_email

if [ ! -s $patch_email ]; then
	printf "$patch_email is empty\n"
	exit 1
fi

cd $DPDK_HOME

git checkout main
check_error "git checkout to main failed!"

new_branch=$BRANCH_PREFIX-$patch_id
ret=`git branch --list $new_branch`
if [ ! -z "$ret" ] ; then
	git branch -d $new_branch
fi
git checkout -b $new_branch

git am $patch_email
check_error "git am $patch_email failed!"

rm -rf build

meson build
check_error "meson build failed!"

meson test -C build --suite DPDK:fast-tests
check_error "meson test failed!"

cd -
