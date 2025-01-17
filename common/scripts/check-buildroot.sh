#!/bin/bash -e

RK_SCRIPTS_DIR="${RK_SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"
RK_SDK_DIR="${RK_SDK_DIR:-$RK_SCRIPTS_DIR/../../../..}"
BUILDROOT_DIR="$RK_SDK_DIR/buildroot"

# Check for host linux version
LINUX_VER_MAJOR=$(uname -r | cut -d'.' -f1)
LINUX_VER_MINOR=$(uname -r | cut -d'.' -f2)
if [ "$LINUX_VER_MAJOR" -lt 4 ] ||
	[ "$LINUX_VER_MAJOR" -eq 4 -a "$LINUX_VER_MINOR" -lt 15 ]; then
	echo -e "\e[35m"
	echo "Your host linux version is too old: $(uname -r)"
	echo "Please upgrade it to at least 4.15!"
	echo -e "\e[0m"
	exit 1
fi

# Buildroot brmake needs unbuffer
if ! which unbuffer >/dev/null 2>&1; then
	echo -e "\e[35m"
	echo "Your unbuffer is missing"
	echo "Please install it:"
	echo "sudo apt-get install expect expect-dev"
	echo -e "\e[0m"
	exit 1
fi

# Buildroot brmake needs unbuffer
if ! which unbuffer >/dev/null 2>&1; then
	echo -e "\e[35m"
	echo "Your unbuffer is missing"
	echo "Please install it:"
	echo "sudo apt-get install expect expect-dev"
	echo -e "\e[0m"
	exit 1
fi

# The new buildroot Makefile needs make (>= 4.0)
if ! "$BUILDROOT_DIR/support/dependencies/check-host-make.sh" 4.0 make \
	> /dev/null; then
	echo -e "\e[35m"
	echo "Your make is too old: $(make -v | head -n 1)"
	echo "Please update it:"
	echo "git clone https://github.com/mirror/make.git --depth 1 -b 4.2"
	echo "cd make"
	echo "git am $BUILDROOT_DIR/package/make/*.patch"
	echo "autoreconf -f -i"
	echo "./configure"
	echo "sudo make install -j8"
	echo -e "\e[0m"
	exit 1
fi

# The buildroot's e2fsprogs doesn't support new features like
# metadata_csum_seed and orphan_file
if grep -wq metadata_csum_seed /etc/mke2fs.conf; then
	echo -e "\e[35m"
	echo "Your mke2fs is too new: $(mke2fs -V 2>&1 | head -n 1)"
	echo "Please downgrade it:"
	"$RK_SCRIPTS_DIR/install-e2fsprogs.sh"
	echo -e "\e[0m"
	exit 1
fi

"$RK_SCRIPTS_DIR/check-header.sh" libc6 dirent.h libc6-dev
