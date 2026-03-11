#!/bin/bash

# 脚本标识
script_name="安装 mihomo 代理软件"

# 获取 arch 平台架构
if [[ "$(dpkg --print-architecture)" == "arm64" ]]; then
    arch="arm64"
elif [[ "$(dpkg --print-architecture)" == "armhf" ]]; then
    arch="armv7"
else
    echo "不支持的架构: $(dpkg --print-architecture)"
    exit 1
fi

# 安装 mihomo 代理软件
function install_mihomo() {

    script_dir=$(dirname "$0")
    software_dir="/opt"
    mihomo_dir="$software_dir/mihomo"
    mihomo_config_dir="$mihomo_dir/config"

    # 导入公共 GitHub 下载模块
    if [[ ! -f "$script_dir/github_downloader.sh" ]]; then
        echo "公共 GitHub 下载模块不存在: $script_dir/github_downloader.sh"
        exit 1
    fi
    source "$script_dir/github_downloader.sh" || {
        echo "导入公共 GitHub 下载模块失败: $script_dir/github_downloader.sh"
        exit 1
    }

    if ! mkdir -p "$mihomo_dir"; then
        echo "创建 mihomo 目录失败: $mihomo_dir"
        exit 1
    fi
    if ! mkdir -p "$mihomo_config_dir"; then
        echo "创建 mihomo 配置目录失败: $mihomo_config_dir"
        exit 1
    fi
    if ! cd "$mihomo_dir"; then
        echo "切换到 mihomo 目录失败: $mihomo_dir"
        exit 1
    fi

    if [[ ! -f "./mihomo-linux-${arch}" ]]; then
        echo "下载 mihomo..."
        # 获取 version
        download_from_github "version.txt" "https://github.com/MetaCubeX/mihomo/releases/latest/download/version.txt"
        local version
        if ! version=$(cat version.txt | tr -d ' '); then
            echo "读取版本文件失败: version.txt"
            exit 1
        fi
        if ! rm -f version.txt; then
            echo "删除版本文件失败: version.txt"
            exit 1
        fi
        # 下载 mihomo-linux-${arch}-${version}.gz 文件
        download_from_github "mihomo-linux-${arch}-${version}.gz" "https://github.com/MetaCubeX/mihomo/releases/download/${version}/mihomo-linux-${arch}-${version}.gz"
        if ! gzip -dN "mihomo-linux-${arch}-${version}.gz"; then
            echo "解压 mihomo 二进制文件失败: mihomo-linux-${arch}-${version}.gz"
            exit 1
        fi
        if ! chmod +x "./mihomo-linux-${arch}"; then
            echo "设置 mihomo 二进制文件执行权限失败: ./mihomo-linux-${arch}"
            exit 1
        fi
    fi



    # 检查 UI 文件
    if [[ ! -d "$mihomo_config_dir/ui" ]]; then
        echo "下载 UI 文件..."
        if ! mkdir -p "$mihomo_config_dir/ui"; then
            echo "创建 UI 目录失败: $mihomo_config_dir/ui"
            exit 1
        fi
        download_from_github "ui.tgz" "https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz"
        if ! tar -xzf ui.tgz -C "$mihomo_config_dir/ui"; then
            echo "解压 UI 文件失败: ui.tgz"
            exit 1
        fi
        if ! rm -f ui.tgz; then
            echo "删除 UI 压缩包失败: ui.tgz"
            exit 1
        fi
    fi

    if ! cd "$mihomo_config_dir"; then
        echo "切换到 mihomo 配置目录失败: $mihomo_config_dir"
        exit 1
    fi

    # 下载 geo 文件
    local files=("GeoIP.dat" "GeoSite.dat" "GeoIP.metadb" "GeoLite2-ASN.mmdb")
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo "下载 $file..."
            case $file in
                "GeoIP.dat")
                    download_from_github "GeoIP.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
                    ;;
                "GeoSite.dat")
                    download_from_github "GeoSite.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
                    ;;
                "GeoIP.metadb")
                    download_from_github "GeoIP.metadb" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
                    ;;
                "GeoLite2-ASN.mmdb")
                    download_from_github "GeoLite2-ASN.mmdb" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb"
                    ;;
            esac
        fi
    done

    # 下载 config.yaml
    download_from_github "config.yaml" "https://raw.githubusercontent.com/FanchangWang/clash_config/main/config.yaml"

    # 创建并启动 mihomo 服务
    local service_file="/etc/systemd/system/mihomo.service"
    if [[ ! -f "$service_file" ]]; then
        echo "创建 mihomo 服务文件..."
        cat <<EOL > "$service_file"
[Unit]
Description=mihomo Daemon, Another Clash Kernel.
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=$mihomo_dir/mihomo-linux-${arch} -d $config_dir
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOL
        if ! systemctl daemon-reload; then
            echo "重新加载系统服务配置失败"
            exit 1
        fi
        if ! systemctl enable mihomo; then
            echo "启用 mihomo 服务失败"
            exit 1
        fi
        if ! systemctl start mihomo; then
            echo "启动 mihomo 服务失败"
            exit 1
        fi
        echo "mihomo 服务已成功启动"
    else
        echo "mihomo 服务已存在, 重启服务..."
        if ! systemctl restart mihomo; then
            echo "重启 mihomo 服务失败"
            exit 1
        fi
        echo "mihomo 服务已成功重启"
    fi
}

# 主函数
install_mihomo
