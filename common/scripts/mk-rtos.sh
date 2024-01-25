#!/bin/bash -e

RK_RTOS_BSP_DIR=$RK_SDK_DIR/rtos/bsp/rockchip
ITS_FILE="$RK_CHIP_DIR/$RK_RTOS_FIT_ITS"

RK_SCRIPTS_DIR="${RK_SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"

usage_hook()
{
	echo -e "rtos                             \tbuild and pack RTOS"
}

rtos_get_value()
{
	echo "$1" | grep -owP "$2\s*=\s*<([^>]+)>" | awk -F'<|>' '{print $2}'
}

rtos_get_string()
{
	echo "$1" | grep -owP "$2\s*=\s*\"([^>]+)\"" | awk -F'"' '{print $2}'
}

rtos_get_node()
{
	echo "$1" | \
	awk -v node="$2" \
		'$0 ~ node " {" {
		in_block = 1;
		block = $0;
		next;
		}
		in_block {
			block = block "\n" $0;
			if (/}/) {
				count_open = gsub(/{/, "&", block);
				count_close = gsub(/}/, "&", block);
				if (count_open == count_close) {
					in_block = 0;
					print block;
					block = "";
				}
			}
		}'
}

build_hal()
{
	check_config RK_RTOS_HAL_TARGET || return 0

	message "=========================================="
	message "  Building CPU$1: HAL-->$RK_RTOS_HAL_TARGET"
	message "=========================================="

	cd "$RK_RTOS_BSP_DIR/common/hal/project/$RK_RTOS_HAL_TARGET/GCC"

	make clean > /dev/null
	rm -rf hal$1.elf hal$1.bin
	make -j$(nproc) > ${RK_SDK_DIR}/hal.log 2>&1
	cp TestDemo.elf hal$1.elf
	mv TestDemo.bin hal$1.bin
	ln -rsf hal$1.bin $RK_OUTDIR/cpu$1.bin

	finish_build build_hal $@
}

build_rtthread()
{
	check_config RK_RTOS_RTT_TARGET || return 0

	message "=========================================="
	message "  Building CPU$1: RT-Thread-->$RK_RTOS_RTT_TARGET"
	message "                  Config-->$2"
	message "=========================================="

	cd "$RK_RTOS_BSP_DIR/$RK_RTOS_RTT_TARGET"

	export RTT_ROOT=$RK_RTOS_BSP_DIR/../../
	export RTT_PRMEM_BASE=$FIRMWARE_CPU_BASE
	export RTT_PRMEM_SIZE=$DRAM_SIZE
	export RTT_SRAM_BASE=$SRAM_BASE
	export RTT_SRAM_SIZE=$SRAM_SIZE
	export RTT_SHMEM_BASE=$SHMEM_BASE
	export RTT_SHMEM_SIZE=$SHMEM_SIZE

	ROOT_PART_OFFSET=$(rk_partition_start rootfs)
	if [ -n $ROOT_PART_OFFSET ];then
		export ROOT_PART_OFFSET=$ROOT_PART_OFFSET
	fi

	ROOT_PART_SIZE=$(rk_partition_size rootfs)
	if [ -n $ROOT_PART_SIZE ];then
		export ROOT_PART_SIZE=$ROOT_PART_SIZE
	fi

	if [ -f "$2" ] ;then
		scons --useconfig="$2"
	else
		warning "Warning: Config $2 not exit!\n"
		warning "Default config(.config) will be used!\n"
	fi

	scons -c > /dev/null
	rm -rf gcc_arm.ld Image/rtt$1.elf Image/rtt$1.bin
	scons -j$(nproc) > ${RK_SDK_DIR}/rtt.log 2>&1
	cp rtthread.elf Image/rtt$1.elf
	mv rtthread.bin Image/rtt$1.bin
	ln -rsf Image/rtt$1.bin $RK_OUTDIR/cpu$1.bin

	if [ -n "$RK_RTOS_RTT_ROOTFS_DATA" ] && [ -n "$ROOT_PART_SIZE" ] ;then

		RTT_TOOLS_PATH=$RK_RTOS_BSP_DIR/$RK_RTOS_RTT_TARGET/../tools
		RTT_ROOTFS_USERDAT=$RK_RTOS_BSP_DIR/$RK_RTOS_RTT_TARGET/$RK_RTOS_RTT_ROOTFS_DATA
		RTT_ROOTFS_SECTOR_SIZE=$(($(printf "%d" $ROOT_PART_SIZE) / 8)) # covert to 4096B

		dd of=root.img bs=4K seek=$RTT_ROOTFS_SECTOR_SIZE count=0 2>&1 || fatal "Failed to dd image!"
		mkfs.fat -S 4096 root.img
		MTOOLS_SKIP_CHECK=1 $RTT_TOOLS_PATH/mcopy -bspmn -D s -i root.img $RTT_ROOTFS_USERDAT/* ::/

		mv root.img Image/
		ln -rsf Image/root.img $RK_FIRMWARE_DIR/rootfs.img
	fi

	finish_build build_rtthread $@
}

clean_hook()
{
	[ "$RK_RTOS" ] || return 0

	cd "$RK_RTOS_BSP_DIR/$RK_RTOS_RTT_TARGET"
	scons -c >/dev/null || true

	cd "$RK_RTOS_BSP_DIR/common/hal/project/$RK_RTOS_HAL_TARGET/GCC"
	make clean >/dev/null || true

	rm -rf "$RK_FIRMWARE_DIR/amp.img"
}

build_images()
{
	for item in $1
	do
		ITS_IMAGE=$(rtos_get_node "$(cat $ITS_FILE)" $item)
		export FIRMWARE_CPU_BASE=$(rtos_get_value "$ITS_IMAGE" load)
		export DRAM_SIZE=$(rtos_get_value "$ITS_IMAGE" size)
		export SRAM_BASE=$(rtos_get_value "$ITS_IMAGE" srambase)
		export SRAM_SIZE=$(rtos_get_value "$ITS_IMAGE" sramsize)
		export CUR_CPU=$(rtos_get_value "$ITS_IMAGE" cpu)
		if (( $CUR_CPU > 0xff )); then
			CUR_CPU=$((CUR_CPU >> 8))
		fi
		CUR_CPU=$(($CUR_CPU))
		export AMP_PRIMARY_CORE=$(rtos_get_value "$ITS_IMAGE" primary)

		echo Image info: $item
		for p in FIRMWARE_CPU_BASE DRAM_SIZE SRAM_BASE SRAM_SIZE SHMEM_BASE \
			 SHMEM_SIZE LINUX_RPMSG_BASE LINUX_RPMSG_SIZE CUR_CPU
		do
			echo $(env | grep -w $p && true)
		done

		SYS=$(rtos_get_string "$ITS_IMAGE" sys)

		case $SYS in
			hal)
				build_hal $CUR_CPU
				;;
			rtt)
				build_rtthread $CUR_CPU "$(rtos_get_string "$ITS_IMAGE" rtt_config)"
				;;
			*)
				break;;
		esac
	done
}

BUILD_CMDS="rtos"
build_hook()
{
	local i

	check_config RK_RTOS || false

	message "=========================================="
	message "          Start building RTOS"
	message "=========================================="

	"$RK_SCRIPTS_DIR/check-rtos.sh"

	export CROSS_COMPILE=$(get_toolchain RTOS "$RK_RTOS_ARCH" "" none)
	[ "$CROSS_COMPILE" ] || exit 1

	if [ -f "$RK_CHIP_DIR/$RK_RTOS_CFG" ]; then
		set -a
		source $RK_CHIP_DIR/$RK_RTOS_CFG
		set +a
	fi

	CORE_NUMBERS=$(grep -wcE "amp[0-9]* {" $ITS_FILE)
	echo "CORE_NUMBERS=$CORE_NUMBERS"

	EXT_MEMORY=$(rtos_get_node "$(cat $ITS_FILE)" share_memory)
	if [ "$EXT_MEMORY" ]; then
		SHMEM_BASE=$(rtos_get_value "$EXT_MEMORY" "shm_base")
		if [ "$SHMEM_BASE" ]; then
			export SHMEM_BASE
			export SHMEM_SIZE=$(rtos_get_value "$EXT_MEMORY" "shm_size")
		fi

		LINUX_RPMSG_BASE=$(rtos_get_value "$EXT_MEMORY" "rpmsg_base")
		if [ "$LINUX_RPMSG_BASE" ]; then
			export LINUX_RPMSG_BASE=$LINUX_RPMSG_BASE
			export LINUX_RPMSG_SIZE=$(rtos_get_value "$EXT_MEMORY" "rpmsg_size")
		fi
	fi

	ITS_IMAGES=$(grep -wE "amp[0-9]* {" $ITS_FILE | grep -o amp[0-9]*)
	build_images "$ITS_IMAGES"

	cd "$RK_OUTDIR"
	ln -rsf $ITS_FILE amp.its
	sed -i '/share_memory {/,/}/d' amp.its
	sed -i '/compile {/,/}/d' amp.its

	$RK_RTOS_BSP_DIR/tools/mkimage -f amp.its -E -p 0xe00 $RK_FIRMWARE_DIR/amp.img

	finish_build rtos $@
}

source "${RK_BUILD_HELPER:-$(dirname "$(realpath "$0")")/../build-hooks/build-helper}"

build_hook $@
