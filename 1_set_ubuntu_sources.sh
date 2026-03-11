#!/bin/bash

# 脚本标识
script_name="配置 Ubuntu 系统源"

# 设置软件源
function set_ubuntu_sources() {
    echo "当前软件源:"
    cat /etc/apt/sources.list

    # 定义源信息映射 (格式: 协议://域名/)
    declare -A sources
    sources["1"]="http://ports.ubuntu.com/"
    sources["2"]="https://mirrors.aliyun.com/ubuntu-ports/"
    sources["3"]="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/"

    # 定义源名称映射
    declare -A source_names
    source_names["1"]="Ubuntu 原站"
    source_names["2"]="阿里云容器站"
    source_names["3"]="清华大学容器站"

    echo "请选择要设置的软件源:"
    # 遍历 source_names 数组生成菜单
    for key in $(echo "${!source_names[@]}" | tr ' ' '\n' | sort -n); do
        echo "$key. ${source_names[$key]}"
    done

    read -r -p "请输入选项 (1-${#source_names[@]}): " mirror_choice

    # 检查选择是否有效
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

    # 执行 apt-get update
    echo "正在更新软件源..."
    apt-get update
    echo "软件源更新完成"
}

# 主函数
set_ubuntu_sources
