#!/bin/bash

script_name="配置 Ubuntu 系统源"

function set_ubuntu_sources() {
    echo "当前软件源:"
    cat /etc/apt/sources.list

    declare -A sources
    sources["1"]="http://ports.ubuntu.com/"
    sources["2"]="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/"

    declare -A source_names
    source_names["1"]="Ubuntu 原站"
    source_names["2"]="清华大学容器站"

    declare -A armbian_sources
    armbian_sources["1"]="http://apt.armbian.com"
    armbian_sources["2"]="https://mirrors.tuna.tsinghua.edu.cn/armbian"

    declare -A armbian_names
    armbian_names["1"]="Armbian 原站"
    armbian_names["2"]="清华大学"

    declare -A docker_sources
    docker_sources["1"]="https://download.docker.com/linux/ubuntu"
    docker_sources["2"]="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu"

    declare -A docker_gpg_urls
    docker_gpg_urls["1"]="https://download.docker.com/linux/ubuntu/gpg"
    docker_gpg_urls["2"]="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg"

    echo "请选择要设置的软件源:"
    for key in $(echo "${!source_names[@]}" | tr ' ' '\n' | sort -n); do
        echo "$key. ${source_names[$key]}"
    done

    read -r -p "请输入选项 (1-${#source_names[@]}): " mirror_choice

    if [[ -z ${sources[$mirror_choice]} || -z ${source_names[$mirror_choice]} ]]; then
        echo "无效的选项"
        return
    fi

    local source_url=${sources[$mirror_choice]}
    local name=${source_names[$mirror_choice]}

    echo "设置为 $name..."
    cat <<EOL > /etc/apt/sources.list
deb $source_url jammy main restricted universe multiverse
deb $source_url jammy-security main restricted universe multiverse
deb $source_url jammy-updates main restricted universe multiverse
deb $source_url jammy-backports main restricted universe multiverse
EOL

    local armbian_url=${armbian_sources[$mirror_choice]}
    local armbian_name=${armbian_names[$mirror_choice]}

    echo "同步设置 armbian 源 ($armbian_name)..."
    mkdir -p /etc/apt/sources.list.d
    cat <<EOL > /etc/apt/sources.list.d/armbian.list
deb [signed-by=/usr/share/keyrings/armbian.gpg] $armbian_url jammy main jammy-utils jammy-desktop
EOL

    local docker_url=${docker_sources[$mirror_choice]}
    local docker_gpg_url=${docker_gpg_urls[$mirror_choice]}

    echo "同步设置 Docker 源..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL "$docker_gpg_url" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    local codename
    codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    cat <<EOL > /etc/apt/sources.list.d/docker.list
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $docker_url $codename stable
EOL

    echo "正在更新软件源..."
    apt-get update
    echo "软件源更新完成"
}

set_ubuntu_sources
