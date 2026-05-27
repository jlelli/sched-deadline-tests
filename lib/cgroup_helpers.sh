#!/bin/bash
# cgroup helpers - support both v1 and v2

# Detect cgroup version
detect_cgroup_version() {
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        echo "v2"
    else
        echo "v1"
    fi
}

# Setup cpuset (works for both v1 and v2)
setup_cpuset() {
    local cgroup_dir=$1
    local cgroup_name=$2
    local cpus=$3
    local mems=${4:-0}

    local version=$(detect_cgroup_version)

    if [ "$version" = "v2" ]; then
        # cgroups v2
        mkdir -p ${cgroup_dir}/${cgroup_name}

        # Must enable cpuset controller in parent first
        if [ ! -f ${cgroup_dir}/cgroup.subtree_control ]; then
            echo "+cpuset" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
        fi
        echo "+cpuset" > ${cgroup_dir}/cgroup.subtree_control 2>/dev/null || true

        # Set CPUs and memory nodes
        echo "$cpus" > ${cgroup_dir}/${cgroup_name}/cpuset.cpus
        echo "$mems" > ${cgroup_dir}/${cgroup_name}/cpuset.mems

        # Make it a partition root (equivalent to cpu_exclusive in v1)
        echo "root" > ${cgroup_dir}/${cgroup_name}/cpuset.cpus.partition 2>/dev/null || true
    else
        # cgroups v1
        mkdir -p ${cgroup_dir}/${cgroup_name}
        echo "$cpus" > ${cgroup_dir}/${cgroup_name}/cpuset.cpus
        echo "$mems" > ${cgroup_dir}/${cgroup_name}/cpuset.mems
        echo 1 > ${cgroup_dir}/${cgroup_name}/cpuset.cpu_exclusive
        echo 1 > ${cgroup_dir}/${cgroup_name}/cpuset.sched_load_balance
    fi
}

# Move task to cgroup
move_task_to_cgroup() {
    local cgroup_dir=$1
    local cgroup_name=$2
    local pid=$3

    local version=$(detect_cgroup_version)

    if [ "$version" = "v2" ]; then
        echo "$pid" > ${cgroup_dir}/${cgroup_name}/cgroup.procs
    else
        echo "$pid" > ${cgroup_dir}/${cgroup_name}/tasks
    fi
}

# Cleanup cpuset
cleanup_cpuset() {
    local cgroup_dir=$1
    local cgroup_name=$2

    local version=$(detect_cgroup_version)

    # Move tasks back to root
    if [ "$version" = "v2" ]; then
        for pid in $(cat ${cgroup_dir}/${cgroup_name}/cgroup.procs 2>/dev/null); do
            echo $pid > ${cgroup_dir}/cgroup.procs 2>/dev/null || true
        done
    else
        for pid in $(cat ${cgroup_dir}/${cgroup_name}/tasks 2>/dev/null); do
            echo $pid > ${cgroup_dir}/tasks 2>/dev/null || true
        done
    fi

    rmdir ${cgroup_dir}/${cgroup_name} 2>/dev/null || true
}
