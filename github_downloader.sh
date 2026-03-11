#!/bin/bash

# 获取 GitHub 加速源列表
get_github_proxies() {
    local github_proxies=(
        "https://gh-proxy.com/"
        "https://ghfast.top/"
        "https://github.allproxy.dpdns.org/"
        "https://github.guyuexuan.ip-ddns.com/"
    )
    echo "${github_proxies[@]}"
}

# 从 GitHub 下载文件的公共函数
download_from_github() {
    local output="$1"  # 文件存放路径
    local url="$2"  # URL 下载地址

    local github_proxies
    github_proxies=$(get_github_proxies)

    echo "准备下载文件: $output"
    # 随机打乱加速源
    local shuffled_proxies
    IFS=$'\n' read -d '' -r -a shuffled_proxies < <(shuf -e $github_proxies)

    for proxy in "${shuffled_proxies[@]}"; do
        echo "尝试从 $proxy 下载..."
        local new_url="${proxy}${url}"  # 在链接前加上加速源

        if wget -O "$output" "$new_url"; then
            echo "下载成功"
            return 0
        fi
    done

    # 尝试下载原始地址
    echo "尝试从 github.com 下载..."
    if wget -O "$output" "$url"; then
        echo "下载成功"
        return 0
    fi

    echo "所有下载尝试失败"
    exit 1
}
