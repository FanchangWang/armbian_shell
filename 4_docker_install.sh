#!/bin/bash

# 脚本标识
script_name="安装 Docker 容器化平台"

# 安装 Docker
function install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker 未安装，正在安装..."
        apt update
        curl -fsSL https://get.docker.com | sh
    else
        echo "Docker 已安装"
    fi
    # 检查 docker 加速是否已设置，未设置则设置
    if [[ ! -f "/etc/docker/daemon.json" ]]; then
        echo "设置 Docker 加速..."
        mkdir -p /etc/docker
        cat <<EOL > /etc/docker/daemon.json
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.1panel.live",
    "https://docker.ketches.cn",
    "https://docker.allproxy.dpdns.org",
    "https://docker.guyuexuan.ip-ddns.com"
  ]
}
EOL
        systemctl restart docker
        echo "Docker 加速设置完成"
    fi
}

# 主函数
install_docker
