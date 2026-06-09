#!/bin/bash

script_name="安装 Docker 容器化平台"

function install_docker() {
    if command -v docker &> /dev/null; then
        echo "Docker 已安装"
        return
    fi

    echo "Docker 未安装，正在安装..."

    read -r -p "是否执行 apt update? (y/n, 默认 n): " do_update
    if [[ "$do_update" == "y" || "$do_update" == "Y" ]]; then
        apt update
    fi

    local installed=false
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # 1. 尝试清华大学镜像源加速安装
    echo "尝试清华大学镜像源安装..."
    if [[ -f "$script_dir/github_downloader.sh" ]]; then
        source "$script_dir/github_downloader.sh"
        local tmp_file
        tmp_file=$(mktemp)
        if download_from_github "$tmp_file" "https://raw.githubusercontent.com/docker/docker-install/master/install.sh"; then
            export DOWNLOAD_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce"
            if sh "$tmp_file"; then
                installed=true
            fi
        fi
        rm -f "$tmp_file"
    else
        echo "github_downloader.sh 未找到，尝试直接下载..."
        export DOWNLOAD_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce"
        if curl -fsSL https://raw.githubusercontent.com/docker/docker-install/master/install.sh | sh; then
            installed=true
        fi
    fi

    # 2. 清华源失败，尝试 DaoCloud
    if [[ "$installed" == false ]]; then
        echo "清华大学镜像源安装失败，尝试 DaoCloud 镜像..."
        if curl -fsSL https://get.daocloud.io/docker | sh; then
            installed=true
        fi
    fi

    # 3. DaoCloud 失败，尝试官方源
    if [[ "$installed" == false ]]; then
        echo "DaoCloud 镜像失败，尝试官方源..."
        if curl -fsSL https://get.docker.com | sh; then
            installed=true
        fi
    fi

    if [[ "$installed" == false ]]; then
        echo "所有 Docker 安装方式均失败"
        exit 1
    fi

    echo "Docker 安装成功"
    if [[ ! -f "/etc/docker/daemon.json" ]]; then
        echo "设置 Docker 加速..."
        mkdir -p /etc/docker
        cat <<EOL > /etc/docker/daemon.json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://docker.1panel.live",
    "https://docker.ketches.cn",
    "https://docker.allproxy.dpdns.org"
  ]
}
EOL
        systemctl restart docker
        echo "Docker 加速设置完成"
    fi
}

install_docker
