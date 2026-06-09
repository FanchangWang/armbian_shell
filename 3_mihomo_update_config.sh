#!/bin/bash

script_name="更新 mihomo 软件及配置"

script_dir=$(dirname "$0")
software_dir="/opt"
mihomo_dir="$software_dir/mihomo"
mihomo_config_dir="$mihomo_dir/config"
mihomo_config_file="$mihomo_config_dir/config.yaml"
mihomo_config_file_tmp="$mihomo_config_dir/config.yaml.tmp"
mihomo_config_file_bak="$mihomo_config_dir/config.yaml.bak"

if [[ "$(dpkg --print-architecture)" == "arm64" ]]; then
    arch="arm64"
elif [[ "$(dpkg --print-architecture)" == "armhf" ]]; then
    arch="armv7"
else
    echo "不支持的架构: $(dpkg --print-architecture)"
    exit 1
fi

if [[ ! -f "$script_dir/github_downloader.sh" ]]; then
    echo "公共 GitHub 下载模块不存在: $script_dir/github_downloader.sh"
    exit 1
fi
source "$script_dir/github_downloader.sh" || {
    echo "导入公共 GitHub 下载模块失败: $script_dir/github_downloader.sh"
    exit 1
}

get_github_token() {
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$GITHUB_TOKEN"
        return 0
    fi
    local env_file="$script_dir/.env"
    if [ -f "$env_file" ]; then
        local token=$(grep -o "GITHUB_TOKEN=.*" "$env_file" | cut -d'=' -f2 | tr -d ' "')
        if [ -n "$token" ]; then
            echo "$token"
            return 0
        fi
    fi
    return 1
}

crontab_setup() {
    local update_cron="40 * * * * bash $script_file >> $mihomo_config_dir/update_config.log 2>&1"
    local cleanup_cron="10 3 */7 * * truncate -s 0 $mihomo_config_dir/update_config.log 2>&1"

    local current_crontab=$(crontab -l 2>/dev/null)
    local new_crontab="$current_crontab"
    local changed=0

    if ! echo "$current_crontab" | grep -Fq "$script_file"; then
        new_crontab=$(printf "%s\n%s" "$new_crontab" "$update_cron")
        echo "添加任务：定时更新配置"
        changed=1
    fi

    if ! echo "$current_crontab" | grep -Fq "truncate -s 0 $mihomo_config_dir/update_config.log"; then
        new_crontab=$(printf "%s\n%s" "$new_crontab" "$cleanup_cron")
        echo "添加任务：定时清理日志"
        changed=1
    fi

    if [ $changed -eq 1 ]; then
        echo "$new_crontab" | sed '/^\s*$/d' | crontab -
        echo "✓ crontab 已成功自动更新"
    else
        echo "✓ 所有 crontab 任务均已存在，无需操作"
    fi
}

calculate_git_sha() {
    local file_path="$1"
    {
        size=$(wc -c < "$file_path")
        printf "blob %d\0" "$size"
        cat "$file_path"
    } | sha1sum | awk '{print $1}'
}

fetch_from_api() {
    local API_URL="https://api.github.com/repos/FanchangWang/clash_config/contents/config.yaml"
    local HEADERS=("Accept: application/vnd.github.v3+json")

    local github_token
    if github_token=$(get_github_token); then
        HEADERS+=("Authorization: token $github_token")
        echo "已添加 GitHub Token 认证头"
    fi

    echo "从 GitHub API 获取 SHA 和内容..."

    local github_proxies
    github_proxies=$(get_github_proxies)

    local shuffled_proxies
    IFS=$'\n' read -d '' -r -a shuffled_proxies < <(shuf -e $github_proxies)

    local response
    for proxy in "${shuffled_proxies[@]}"; do
        echo "尝试从 $proxy 获取 API 数据..."
        local proxy_url="${proxy}${API_URL}"
        if response=$(curl -s -H "${HEADERS[@]}" "$proxy_url"); then
            if echo "$response" | grep -q '"sha":'; then
                echo "API 请求成功"
                break
            fi
        fi
    done

    if [[ -z "$response" || ! $(echo "$response" | grep -q '"sha":') ]]; then
        echo "尝试从原始地址获取 API 数据..."
        if ! response=$(curl -s -H "${HEADERS[@]}" "$API_URL"); then
            echo "错误：无法从 GitHub API 获取数据。"
            exit 1
        fi
    fi

    api_sha=$(echo "$response" | grep -o '"sha": "[^"]*' | cut -d'"' -f4)
    local content_base64=$(echo "$response" | grep -o '"content": "[^"]*' | cut -d'"' -f4 | sed 's/\\n/\n/g')
    content=$(echo "$content_base64" | base64 --decode)

    if [[ -z "$api_sha" || -z "$content" ]]; then
        echo "错误：无法从 API 响应中解析 sha 或 content。"
        exit 1
    fi
}

get_local_sha() {
    local CONFIG_FILE="$1"
    if [[ -f "$CONFIG_FILE" ]]; then
        calculate_git_sha "$CONFIG_FILE"
    else
        echo ""
    fi
}

backup_and_update() {
    echo "正在备份当前的 $mihomo_config_file 到 $mihomo_config_file_bak..."
    cp "$mihomo_config_file" "$mihomo_config_file_bak"

    echo "正在用新内容更新 $mihomo_config_file..."
    echo "$content" > "$mihomo_config_file_tmp"
    mv "$mihomo_config_file_tmp" "$mihomo_config_file"
}

validate_updated_file() {
    local updated_sha
    updated_sha=$(get_local_sha "$mihomo_config_file")
    if [[ "$updated_sha" != "$api_sha" ]]; then
        echo "错误：新配置文件 SHA 不匹配 ( 新配置文件值：$updated_sha, API 值：$api_sha )。"
        echo "恢复备份..."
        mv "$mihomo_config_file_bak" "$mihomo_config_file"
        echo "备份已恢复。"
        exit 1
    fi
    echo "新配置文件 SHA 验证成功。"
}

function update_mihomo() {
    echo "================================================"
    echo "时间：$(TZ='Asia/Shanghai' date +%Y%m%d\ %H:%M:%S)"

    echo -e "\n设置 crontab 定时任务..."
    crontab_setup

    local need_restart=false

    # 1. 检查配置更新
    echo -e "\n开始检查配置更新..."
    fetch_from_api

    local local_sha
    local_sha=$(get_local_sha "$mihomo_config_file")

    echo "API SHA: $api_sha"
    echo "API content length: ${#content}"
    echo "Local SHA: $local_sha"

    if [[ "$local_sha" != "$api_sha" ]]; then
        backup_and_update
        validate_updated_file
        echo "配置文件已更新"
        need_restart=true
    else
        echo "本地配置文件是最新的，无需更新。"
    fi

    # 2. 检查 mihomo 版本更新
    echo -e "\n开始检查 mihomo 版本更新..."

    local binary_path="$mihomo_dir/mihomo-linux-${arch}"
    if [[ ! -f "$binary_path" ]]; then
        echo "错误: mihomo 二进制文件不存在: $binary_path"
        exit 1
    fi

    local current_version
    current_version=$("$binary_path" -v 2>/dev/null | head -1 | grep -oP 'v\d+\.\d+\.\d+')
    if [[ -z "$current_version" ]]; then
        echo "错误: 无法获取当前 mihomo 版本"
        exit 1
    fi
    echo "当前版本: $current_version"

    echo "获取最新版本..."
    download_from_github "version.txt" "https://github.com/MetaCubeX/mihomo/releases/latest/download/version.txt"
    local latest_version
    latest_version=$(cat version.txt | tr -d ' ')
    rm -f version.txt
    echo "最新版本: $latest_version"

    if [[ "$current_version" != "$latest_version" ]]; then
        echo "发现新版本 $latest_version，开始更新..."
        download_from_github "mihomo-linux-${arch}-${latest_version}.gz" \
            "https://github.com/MetaCubeX/mihomo/releases/download/${latest_version}/mihomo-linux-${arch}-${latest_version}.gz"
        if ! gzip -d "mihomo-linux-${arch}-${latest_version}.gz"; then
            echo "错误: 解压失败"
            exit 1
        fi
        mv "mihomo-linux-${arch}-${latest_version}" "$binary_path"
        chmod +x "$binary_path"
        echo "mihomo 已更新到 $latest_version"
        need_restart=true
    else
        echo "mihomo 已是最新版本。"
    fi

    # 3. 根据是否需要更新重启服务
    if [[ "$need_restart" == true ]]; then
        echo -e "\n配置或软件有更新，重启 mihomo 服务..."
        systemctl restart mihomo
        echo "mihomo 服务已重启。"
    else
        echo -e "\n无需更新，跳过重启。"
    fi

    echo -e "\n脚本执行完毕。"
}

update_mihomo
