#! /bin/sh -e

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

if [ -z "$DPDK_DIR" ]; then
	printf 'missing environment variable: $DPDK_DIR\n'
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

cd $DPDK_DIR

git checkout main
check_error "git checkout to main failed!"

ret=`git branch --list $patch_id`
if [ ! -z "$ret" ] ; then
	git branch -d $patch_id
	check_error "git branch -d $patch_id failed!"
fi

git checkout -b $patch_id
check_error "git checkout to $patch_id failed!"

git am $patch_email
check_error "git am $patch_email failed!"

rm -rf build

meson build
check_error "meson build failed!"

meson test -C build --suite DPDK:fast-tests
check_error "meson test failed!"

cd -
