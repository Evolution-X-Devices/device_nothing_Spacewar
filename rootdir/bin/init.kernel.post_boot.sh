#!/system/bin/sh

# ── RAM ─────────────────────────────────────────────────

configure_zram() {
    ZRAM_SIZE_MB=2048

    if [ -f /sys/block/zram0/comp_algorithm ]; then
        echo lz4  > /sys/block/zram0/comp_algorithm 2>/dev/null || \
        echo lzo  > /sys/block/zram0/comp_algorithm 2>/dev/null
    fi

    if [ -f /sys/block/zram0/disksize ]; then
        swapoff /dev/block/zram0 2>/dev/null
        echo "${ZRAM_SIZE_MB}M" > /sys/block/zram0/disksize

        [ -f /sys/block/zram0/use_dedup ] && \
        echo 1 > /sys/block/zram0/use_dedup

        [ -e /sys/kernel/slab/zs_handle ] && \
        echo 0 > /sys/kernel/slab/zs_handle/store_user
        [ -e /sys/kernel/slab/zspage ] && \
        echo 0 > /sys/kernel/slab/zspage/store_user

        mkswap  /dev/block/zram0
        swapon  /dev/block/zram0 -p 32758
    fi
}

configure_read_ahead() {
    RA=128

    [ -f /sys/block/mmcblk0/bdi/read_ahead_kb ] && \
    echo $RA > /sys/block/mmcblk0/bdi/read_ahead_kb

    [ -f /sys/block/mmcblk0rpmb/bdi/read_ahead_kb ] && \
    echo $RA > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb

    for dm in $(ls /sys/block/*/queue/read_ahead_kb 2>/dev/null | grep -e dm -e mmc); do
        echo $RA > "$dm"
    done
}

configure_vm() {
    echo 40  > /proc/sys/vm/swappiness
    echo 20  > /proc/sys/vm/watermark_scale_factor
    echo 2   > /proc/sys/vm/kswapd_threads
    echo 15  > /proc/sys/vm/dirty_ratio
    echo 5   > /proc/sys/vm/dirty_background_ratio
    configure_zram
}

# ── CPU ─────────────────────────────────────────────────────

configure_scheduler() {
    [ -e /proc/sys/kernel/sched_upmigrate ]   && echo "25 45" > /proc/sys/kernel/sched_upmigrate
    [ -e /proc/sys/kernel/sched_downmigrate ] && echo "20 40" > /proc/sys/kernel/sched_downmigrate
    [ -e /proc/sys/kernel/sched_group_upmigrate ]   && echo 55 > /proc/sys/kernel/sched_group_upmigrate
    [ -e /proc/sys/kernel/sched_group_downmigrate ] && echo 35 > /proc/sys/kernel/sched_group_downmigrate
    [ -e /proc/sys/kernel/sched_walt_rotate_big_tasks ] && echo 1 > /proc/sys/kernel/sched_walt_rotate_big_tasks

    echo 1 > /proc/sys/kernel/sched_boost

    [ -e /proc/sys/kernel/sched_min_task_util_for_boost ]           && echo 20       > /proc/sys/kernel/sched_min_task_util_for_boost
    [ -e /proc/sys/kernel/sched_min_task_util_for_colocation ]      && echo 15       > /proc/sys/kernel/sched_min_task_util_for_colocation
    [ -e /proc/sys/kernel/sched_task_unfilter_period ]              && echo 10000000 > /proc/sys/kernel/sched_task_unfilter_period
    [ -e /proc/sys/kernel/sched_conservative_pl ]                   && echo 1        > /proc/sys/kernel/sched_conservative_pl
    [ -e /proc/sys/kernel/sched_coloc_busy_hysteresis_enable_cpus ] && echo 255      > /proc/sys/kernel/sched_coloc_busy_hysteresis_enable_cpus
}

configure_core_ctl() {
    if [ -d /sys/devices/system/cpu/cpu4/core_ctl ]; then
        echo "0 0 0" > /sys/devices/system/cpu/cpu4/core_ctl/not_preferred
        echo 0   > /sys/devices/system/cpu/cpu4/core_ctl/min_cpus
        echo 60  > /sys/devices/system/cpu/cpu4/core_ctl/busy_up_thres
        echo 30  > /sys/devices/system/cpu/cpu4/core_ctl/busy_down_thres
        echo 100 > /sys/devices/system/cpu/cpu4/core_ctl/offline_delay_ms
        echo 2   > /sys/devices/system/cpu/cpu4/core_ctl/task_thres
    fi

    if [ -d /sys/devices/system/cpu/cpu7/core_ctl ]; then
        echo 0   > /sys/devices/system/cpu/cpu7/core_ctl/min_cpus
        echo 60  > /sys/devices/system/cpu/cpu7/core_ctl/busy_up_thres
        echo 30  > /sys/devices/system/cpu/cpu7/core_ctl/busy_down_thres
        echo 100 > /sys/devices/system/cpu/cpu7/core_ctl/offline_delay_ms
        echo 1   > /sys/devices/system/cpu/cpu7/core_ctl/task_thres
        echo 1   > /sys/devices/system/cpu/cpu7/core_ctl/nr_prev_assist_thresh
    fi

    [ -e /sys/devices/system/cpu/cpu0/core_ctl/enable ] && \
    echo 0 > /sys/devices/system/cpu/cpu0/core_ctl/enable
}

set_schedutil() {
    POLICY=$1
    HISPEED=$2
    MIN_FREQ=$3
    HISPEED_LOAD=$4
    UP_RATE_LIMIT=$5
    DOWN_RATE_LIMIT=$6
    BASE="/sys/devices/system/cpu/cpufreq/policy${POLICY}"

    [ -d "$BASE" ] || return

    echo schedutil > $BASE/scaling_governor

    [ -e "$BASE/schedutil/up_rate_limit_us" ]    && echo ${UP_RATE_LIMIT:-0}      > $BASE/schedutil/up_rate_limit_us
    [ -e "$BASE/schedutil/down_rate_limit_us" ]  && echo ${DOWN_RATE_LIMIT:-5000} > $BASE/schedutil/down_rate_limit_us
    [ -e "$BASE/schedutil/hispeed_freq" ]        && echo $HISPEED  > $BASE/schedutil/hispeed_freq
    [ -e "$BASE/scaling_min_freq" ]              && echo $MIN_FREQ > $BASE/scaling_min_freq
    [ -e "$BASE/schedutil/pl" ]                  && echo 1         > $BASE/schedutil/pl

    if [ -n "$HISPEED_LOAD" ]; then
       [ -e "$BASE/schedutil/hispeed_load" ]     && echo $HISPEED_LOAD > $BASE/schedutil/hispeed_load
       [ -e "$BASE/schedutil/rtg_boost_freq" ]   && echo 0             > $BASE/schedutil/rtg_boost_freq
    fi
}

configure_cpu() {
    set_schedutil 0 1804800 300000 "" 500
    [ -e /sys/devices/system/cpu/cpufreq/policy0/schedutil/rtg_boost_freq ] && \
    echo 1497600 > /sys/devices/system/cpu/cpufreq/policy0/schedutil/rtg_boost_freq

    set_schedutil 4 2400000 576000 70 1000
    echo -3 > /sys/devices/system/cpu/cpu4/sched_load_boost 2>/dev/null
    echo -3 > /sys/devices/system/cpu/cpu5/sched_load_boost 2>/dev/null
    echo -3 > /sys/devices/system/cpu/cpu6/sched_load_boost 2>/dev/null

    set_schedutil 7 2515200 652800 80 1000
    echo -3 > /sys/devices/system/cpu/cpu7/sched_load_boost 2>/dev/null
}

configure_input_boost() {
    [ -e /sys/devices/system/cpu/cpu_boost/input_boost_freq ] && \
    echo "0:1324800 4:1900800 7:2054400" > /sys/devices/system/cpu/cpu_boost/input_boost_freq

    [ -e /sys/devices/system/cpu/cpu_boost/input_boost_ms ] && \
    echo 200 > /sys/devices/system/cpu/cpu_boost/input_boost_ms
}

configure_cpuset() {
    [ -e /dev/cpuset/background/cpus ]        && echo 0-1 > /dev/cpuset/background/cpus
    [ -e /dev/cpuset/system-background/cpus ] && echo 0-3 > /dev/cpuset/system-background/cpus
}

# ── GPU ─────────────────────────────────────────────────────

configure_gpu() {
    GPU_PATH="/sys/class/kgsl/kgsl-3d0/devfreq"
    if [ -d "$GPU_PATH" ]; then
       [ -e "$GPU_PATH/governor" ] && echo msm-adreno-tz > $GPU_PATH/governor
    fi

    [ -e /sys/class/kgsl/kgsl-3d0/idle_timer ] && \
    echo 40 > /sys/class/kgsl/kgsl-3d0/idle_timer

    [ -e /sys/class/kgsl/kgsl-3d0/min_pwrlevel ] && \
    echo 7 > /sys/class/kgsl/kgsl-3d0/min_pwrlevel
}

# ── BUS / DCVS ──────────────────────────────────────────────

configure_memlat() {
    ddr_type=$(od -An -tx /proc/device-tree/memory/ddr_device_type 2>/dev/null)
    ddr_type4="07"
    ddr_type5="08"

    for node in /sys/devices/system/cpu/memlat/c0_memlat/cpu0-cpu-l3-lat; do
        [ -d "$node" ] || continue
        cat $node/available_frequencies | cut -d " " -f 1 > $node/min_freq
        echo 300 > $node/ratio_ceil
        echo 3   > $node/sample_ms
    done

    for node in /sys/devices/system/cpu/memlat/c4_memlat/cpu4-cpu-l3-lat; do
        [ -d "$node" ] || continue
        cat $node/available_frequencies | cut -d " " -f 1 > $node/min_freq
        echo 3000  > $node/ratio_ceil
        echo 3     > $node/sample_ms
        echo 60    > $node/l2wb_pct
        echo 25000 > $node/l2wb_filter
    done

    for node in /sys/devices/system/cpu/memlat/c7_memlat/cpu7-cpu-l3-lat; do
        [ -d "$node" ] || continue
        cat $node/available_frequencies | cut -d " " -f 1 > $node/min_freq
        echo 15000 > $node/ratio_ceil
        echo 3     > $node/sample_ms
        echo 60    > $node/l2wb_pct
        echo 25000 > $node/l2wb_filter
    done

    for device in /sys/devices/platform/soc; do

        for cpubw in $device/*cpu-cpu-llcc-bw/devfreq/*cpu-cpu-llcc-bw; do
            [ -e "$cpubw/available_frequencies" ] || continue
            cat $cpubw/available_frequencies | cut -d " " -f 1 > $cpubw/min_freq
            echo "2288 4577 7110 9155 12298 14236 15258" > $cpubw/bw_hwmon/mbps_zones
            echo 8    > $cpubw/bw_hwmon/sample_ms
            echo 65   > $cpubw/bw_hwmon/io_percent
            echo 20   > $cpubw/bw_hwmon/hist_memory
            echo 0    > $cpubw/bw_hwmon/hyst_length
            echo 70   > $cpubw/bw_hwmon/down_thres
            echo 0    > $cpubw/bw_hwmon/guard_band_mbps
            echo 200  > $cpubw/bw_hwmon/up_scale
            echo 1600 > $cpubw/bw_hwmon/idle_mbps
            echo 40   > $cpubw/polling_interval
        done

        for llccbw in $device/*cpu-llcc-ddr-bw/devfreq/*cpu-llcc-ddr-bw; do
            [ -e "$llccbw/available_frequencies" ] || continue
            cat $llccbw/available_frequencies | cut -d " " -f 1 > $llccbw/min_freq
            if [ "${ddr_type:4:2}" = "$ddr_type4" ]; then
                echo "1144 1720 2086 2929 3879 5931 6515 8136" > $llccbw/bw_hwmon/mbps_zones
            elif [ "${ddr_type:4:2}" = "$ddr_type5" ]; then
                echo "1144 1720 2086 2929 3879 5931 6515 7980 12191" > $llccbw/bw_hwmon/mbps_zones
            fi
            echo 8    > $llccbw/bw_hwmon/sample_ms
            echo 65   > $llccbw/bw_hwmon/io_percent
            echo 20   > $llccbw/bw_hwmon/hist_memory
            echo 0    > $llccbw/bw_hwmon/hyst_length
            echo 70   > $llccbw/bw_hwmon/down_thres
            echo 0    > $llccbw/bw_hwmon/guard_band_mbps
            echo 200  > $llccbw/bw_hwmon/up_scale
            echo 1600 > $llccbw/bw_hwmon/idle_mbps
            echo 48   > $llccbw/polling_interval
        done

        for l3bw in $device/*snoop-l3-bw/devfreq/*snoop-l3-bw; do
            [ -e "$l3bw/available_frequencies" ] || continue
            cat $l3bw/available_frequencies | cut -d " " -f 1 > $l3bw/min_freq
            echo 8    > $l3bw/bw_hwmon/sample_ms
            echo 10   > $l3bw/bw_hwmon/io_percent
            echo 20   > $l3bw/bw_hwmon/hist_memory
            echo 10   > $l3bw/bw_hwmon/hyst_length
            echo 0    > $l3bw/bw_hwmon/down_thres
            echo 0    > $l3bw/bw_hwmon/guard_band_mbps
            echo 0    > $l3bw/bw_hwmon/up_scale
            echo 1600 > $l3bw/bw_hwmon/idle_mbps
            echo 9155 > $l3bw/max_freq
            echo 40   > $l3bw/polling_interval
        done

        for memlat in $device/*lat/devfreq/*lat; do
            [ -e "$memlat/available_frequencies" ] || continue
            cat $memlat/available_frequencies | cut -d " " -f 1 > $memlat/min_freq
            echo 12  > $memlat/polling_interval
            echo 300 > $memlat/mem_latency/ratio_ceil
        done

        for latfloor in $device/*cpu0-cpu*latfloor/devfreq/*cpu0-cpu*latfloor; do
            [ -e "$latfloor/available_frequencies" ] || continue
            cat $latfloor/available_frequencies | cut -d " " -f 1 > $latfloor/min_freq
            echo 10 > $latfloor/polling_interval
        done

        for latfloor in $device/*cpu4-cpu*latfloor/devfreq/*cpu4-cpu*latfloor; do
            [ -e "$latfloor/available_frequencies" ] || continue
            cat $latfloor/available_frequencies | cut -d " " -f 1 > $latfloor/min_freq
            echo 10 > $latfloor/polling_interval
        done

        for latfloor in $device/*cpu7-cpu*latfloor/devfreq/*cpu7-cpu*latfloor; do
            [ -e "$latfloor/available_frequencies" ] || continue
            cat $latfloor/available_frequencies | cut -d " " -f 1 > $latfloor/min_freq
            echo 10    > $latfloor/polling_interval
            echo 20000 > $latfloor/mem_latency/ratio_ceil
        done

        for qoslat in $device/*qoslat/devfreq/*qoslat; do
            [ -e "$qoslat/mem_latency/ratio_ceil" ] && \
            echo 40 > $qoslat/mem_latency/ratio_ceil
        done

    done
}

# ── SLEEP ───────────────────────────────────────────────────

configure_sleep() {
    [ -e /sys/module/lpm_levels/parameters/sleep_disabled ] && \
    echo N > /sys/module/lpm_levels/parameters/sleep_disabled

    [ -e /sys/power/mem_sleep ] && \
    echo s2idle > /sys/power/mem_sleep
}

# ── MAIN ────────────────────────────────────────────────────

main() {
    configure_read_ahead
    configure_vm
    configure_scheduler
    configure_core_ctl
    configure_cpu
    configure_input_boost
    configure_cpuset
    configure_gpu
    configure_memlat
    configure_sleep

    setprop vendor.post_boot.parsed 1
}

main
