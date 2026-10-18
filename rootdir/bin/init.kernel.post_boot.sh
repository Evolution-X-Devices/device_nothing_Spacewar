#=============================================================================
# Copyright (c) 2020-2021 Qualcomm Technologies, Inc.
# All Rights Reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#
# Copyright (c) 2009-2012, 2014-2019, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#=============================================================================

function configure_zram_parameters() {
	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}

	low_ram=`getprop ro.config.low_ram`

	# Zram disk - 75% for Go and < 2GB devices .
	# For >2GB Non-Go devices, size = 50% of RAM size. Limit the size to 4GB.
	# And enable lz4 zram compression for Go targets.

	let RamSizeGB="( $MemTotal / 1048576 ) + 1"
	diskSizeUnit=M
	if [ $RamSizeGB -le 2 ]; then
		let zRamSizeMB="( $RamSizeGB * 1024 ) * 3 / 4"
	else
		let zRamSizeMB="( $RamSizeGB * 1024 ) / 2"
	fi

	# use MB avoid 32 bit overflow
	if [ $zRamSizeMB -gt 4096 ]; then
		let zRamSizeMB=4096
	fi

	if [ "$low_ram" == "true" ]; then
		echo lz4 > /sys/block/zram0/comp_algorithm
	fi

	if [ -f /sys/block/zram0/disksize ]; then
		if [ -f /sys/block/zram0/use_dedup ]; then
			echo 1 > /sys/block/zram0/use_dedup
		fi
		echo "$zRamSizeMB""$diskSizeUnit" > /sys/block/zram0/disksize

		# ZRAM may use more memory than it saves if SLAB_STORE_USER
		# debug option is enabled.
		if [ -e /sys/kernel/slab/zs_handle ]; then
			echo 0 > /sys/kernel/slab/zs_handle/store_user
		fi
		if [ -e /sys/kernel/slab/zspage ]; then
			echo 0 > /sys/kernel/slab/zspage/store_user
		fi

		mkswap /dev/block/zram0
		swapon /dev/block/zram0 -p 32758
	fi
}

function configure_memory_parameters() {
	# Set Memory parameters.
	#
	# Set per_process_reclaim tuning parameters
	# All targets will use vmpressure range 50-70,
	# All targets will use 512 pages swap size.
	#
	# Set Low memory killer minfree parameters
	# 32 bit Non-Go, all memory configurations will use 15K series
	# 32 bit Go, all memory configurations will use uLMK + Memcg
	# 64 bit will use Google default LMK series.
	#
	# Set ALMK parameters (usually above the highest minfree values)
	# vmpressure_file_min threshold is always set slightly higher
	# than LMK minfree's last bin value for all targets. It is calculated as
	# vmpressure_file_min = (last bin - second last bin ) + last bin
	#
	# Set allocstall_threshold to 0 for all targets.
	#

	ProductName=`getprop ro.product.name`

	configure_zram_parameters
	echo 80 > /proc/sys/vm/swappiness

        # Disable wsf  beacause we are using efk.
        # wsf Range : 1..1000. So set to bare minimum value 1.
        echo 1 > /proc/sys/vm/watermark_scale_factor

	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}
	if [ $MemTotal -le 8388608 ]; then
		echo 0 > /proc/sys/vm/watermark_boost_factor
	fi
}

rev=`cat /sys/devices/soc0/revision`
ddr_type=`od -An -tx /proc/device-tree/memory/ddr_device_type`
ddr_type4="07"
ddr_type5="08"

# cpuset parameters
echo 0-3 > /dev/cpuset/background/cpus
echo 0-3 > /dev/cpuset/system-background/cpus

# configure governor settings for silver cluster
echo "schedutil" > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
echo 0 > /sys/devices/system/cpu/cpufreq/policy0/schedutil/down_rate_limit_us
echo 0 > /sys/devices/system/cpu/cpufreq/policy0/schedutil/up_rate_limit_us
echo 691200 > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq

# configure governor settings for gold cluster
echo "schedutil" > /sys/devices/system/cpu/cpufreq/policy4/scaling_governor
echo 0 > /sys/devices/system/cpu/cpufreq/policy4/schedutil/down_rate_limit_us
echo 0 > /sys/devices/system/cpu/cpufreq/policy4/schedutil/up_rate_limit_us
echo 691200 > /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq

# configure governor settings for gold+ cluster
echo "schedutil" > /sys/devices/system/cpu/cpufreq/policy7/scaling_governor
echo 0 > /sys/devices/system/cpu/cpufreq/policy7/schedutil/down_rate_limit_us
echo 0 > /sys/devices/system/cpu/cpufreq/policy7/schedutil/up_rate_limit_us
echo 806400 > /sys/devices/system/cpu/cpufreq/policy7/scaling_min_freq

# configure RIMPS for L3 DCVS
for c0_rimps_l3 in /sys/devices/system/cpu/memlat/c0_memlat/cpu0-cpu-l3-lat
do
	cat $c0_rimps_l3/available_frequencies | cut -d " " -f 1 > $c0_rimps_l3/min_freq
	echo 400 > $c0_rimps_l3/ratio_ceil
	echo 3 > $c0_rimps_l3/sample_ms
done

for c4_rimps_l3 in /sys/devices/system/cpu/memlat/c4_memlat/cpu4-cpu-l3-lat
do
	cat $c4_rimps_l3/available_frequencies | cut -d " " -f 1 > $c4_rimps_l3/min_freq
	echo 4000 > $c4_rimps_l3/ratio_ceil
	echo 3 > $c4_rimps_l3/sample_ms
	echo 60 > $c4_rimps_l3/l2wb_pct
	echo 25000 > $c4_rimps_l3/l2wb_filter
done

for c7_rimps_l3 in /sys/devices/system/cpu/memlat/c7_memlat/cpu7-cpu-l3-lat
do
	cat $c7_rimps_l3/available_frequencies | cut -d " " -f 1 > $c7_rimps_l3/min_freq
	echo 20000 > $c7_rimps_l3/ratio_ceil
	echo 3 > $c7_rimps_l3/sample_ms
	echo 60 > $c7_rimps_l3/l2wb_pct
	echo 25000 > $c7_rimps_l3/l2wb_filter
done


# configure bus-dcvs
for device in /sys/devices/platform/soc
do
	for cpubw in $device/*cpu-cpu-llcc-bw/devfreq/*cpu-cpu-llcc-bw
	do
		cat $cpubw/available_frequencies | cut -d " " -f 1 > $cpubw/min_freq
		echo "2288 4577 7110 9155 12298 14236 15258" > $cpubw/bw_hwmon/mbps_zones
		echo 4 > $cpubw/bw_hwmon/sample_ms
		echo 68 > $cpubw/bw_hwmon/io_percent
		echo 20 > $cpubw/bw_hwmon/hist_memory
		echo 0 > $cpubw/bw_hwmon/hyst_length
		echo 80 > $cpubw/bw_hwmon/down_thres
		echo 0 > $cpubw/bw_hwmon/guard_band_mbps
		echo 250 > $cpubw/bw_hwmon/up_scale
		echo 1600 > $cpubw/bw_hwmon/idle_mbps
		echo 40 > $cpubw/polling_interval
	done

	for llccbw in $device/*cpu-llcc-ddr-bw/devfreq/*cpu-llcc-ddr-bw
	do
		cat $llccbw/available_frequencies | cut -d " " -f 1 > $llccbw/min_freq
		if [ ${ddr_type:4:2} == $ddr_type4 ]; then
			echo "1144 1720 2086 2929 3879 5931 6515 8136" > $llccbw/bw_hwmon/mbps_zones
		elif [ ${ddr_type:4:2} == $ddr_type5 ]; then
			echo "1144 1720 2086 2929 3879 5931 6515 7980 12191" > $llccbw/bw_hwmon/mbps_zones
		fi
		echo 4 > $llccbw/bw_hwmon/sample_ms
		echo 68 > $llccbw/bw_hwmon/io_percent
		echo 20 > $llccbw/bw_hwmon/hist_memory
		echo 0 > $llccbw/bw_hwmon/hyst_length
		echo 80 > $llccbw/bw_hwmon/down_thres
		echo 0 > $llccbw/bw_hwmon/guard_band_mbps
		echo 250 > $llccbw/bw_hwmon/up_scale
		echo 1600 > $llccbw/bw_hwmon/idle_mbps
		echo 48 > $llccbw/polling_interval
	done

	for l3bw in $device/*snoop-l3-bw/devfreq/*snoop-l3-bw
	do
		cat $l3bw/available_frequencies | cut -d " " -f 1 > $l3bw/min_freq
		echo 4 > $l3bw/bw_hwmon/sample_ms
		echo 10 > $l3bw/bw_hwmon/io_percent
		echo 20 > $l3bw/bw_hwmon/hist_memory
		echo 10 > $l3bw/bw_hwmon/hyst_length
		echo 0 > $l3bw/bw_hwmon/down_thres
		echo 0 > $l3bw/bw_hwmon/guard_band_mbps
		echo 0 > $l3bw/bw_hwmon/up_scale
		echo 1600 > $l3bw/bw_hwmon/idle_mbps
		echo 9155 > $l3bw/max_freq
		echo 40 > $l3bw/polling_interval
	done

	# configure mem_latency settings for LLCC and DDR scaling and qoslat
	for memlat in $device/*lat/devfreq/*lat
	do
		cat $memlat/available_frequencies | cut -d " " -f 1 > $memlat/min_freq
		echo 8 > $memlat/polling_interval
		echo 400 > $memlat/mem_latency/ratio_ceil
	done

	# configure compute settings for silver latfloor
	for latfloor in $device/*cpu0-cpu*latfloor/devfreq/*cpu0-cpu*latfloor
	do
		cat $latfloor/available_frequencies | cut -d " " -f 1 > $latfloor/min_freq
		echo 8 > $latfloor/polling_interval
	done

	# configure compute settings for gold latfloor
	for latfloor in $device/*cpu4-cpu*latfloor/devfreq/*cpu4-cpu*latfloor
	do
		cat $latfloor/available_frequencies | cut -d " " -f 1 > $latfloor/min_freq
		echo 8 > $latfloor/polling_interval
	done

        # configure mem_latency settings for prime latfloor
	for latfloor in $device/*cpu7-cpu*latfloor/devfreq/*cpu7-cpu*latfloor
	do
		cat $latfloor/available_frequencies | cut -d " " -f 1 > $latfloor/min_freq
		echo 8 > $latfloor/polling_interval
		echo 25000 > $latfloor/mem_latency/ratio_ceil
	done

	# qoslat ratio ceil
	for qoslat in $device/*qoslat/devfreq/*qoslat
	do
	    echo 50 > $qoslat/mem_latency/ratio_ceil
	done
done

# set s2idle as default suspend mode
echo s2idle > /sys/power/mem_sleep

configure_memory_parameters

setprop vendor.post_boot.parsed 1