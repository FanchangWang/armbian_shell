#!/bin/bash

# 脚本标识
script_name="更新 mihomo 配置"

# 获取脚本所在目录的绝对路径
script_dir=$(dirname "$0")
script_file=$(realpath "$0")
software_dir="/opt"
mihomo_dir="$software_dir/mihomo"
mihomo_config_dir="$mihomo_dir/config"
mihomo_config_file="$mihomo_config_dir/config.yaml"
mihomo_config_file_tmp="$mihomo_config_dir/config.yaml.tmp"
mihomo_config_file_bak="$mihomo_config_dir/config.yaml.bak"

# 函数：从环境变量或 .env 文件获取 GitHub Token
get_github_token() {
    # 首先检查环境变量
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$GITHUB_TOKEN"
        return 0
    fi

    # 检查 .env 文件
    local env_file="$script_dir/.env"
    if [ -f "$env_file" ]; then
        local token=$(grep -o "GITHUB_TOKEN=.*" "$env_file" | cut -d'=' -f2 | tr -d ' "')
        if [ -n "$token" ]; then
            echo "$token"
            return 0
        fi
    fi

    # 没有找到 Token
    return 1
}

# 函数：设置 crontab 定时任务
crontab_setup() {
    # 定义条目
    local update_cron="40 * * * * bash $script_file >> $mihomo_config_dir/update_config.log 2>&1"
    local cleanup_cron="10 3 */7 * * truncate -s 0 $mihomo_config_dir/update_config.log 2>&1"

    # 获取当前内容（处理空 crontab 的情况）
    local current_crontab=$(crontab -l 2>/dev/null)
    local new_crontab="$current_crontab"
    local changed=0

    # 逻辑判断：如果不存在则追加到变量
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

    # 如果有变化，写回 crontab
    if [ $changed -eq 1 ]; then
        # 移除空行并写入
        echo "$new_crontab" | sed '/^\s*$/d' | crontab -
        echo "✓ crontab 已成功自动更新"
    else
        echo "✓ 所有 crontab 任务均已存在，无需操作"
    fi
}

# 函数：计算 Git SHA 值
calculate_git_sha() {
    local file_path="$1"
    {
        size=$(wc -c < "$file_path")
        printf "blob %d\0" "$size"
        cat "$file_path"
    } | sha1sum | awk '{print $1}'
}

# 函数：从 API 获取 SHA 和内容
fetch_from_api() {
    # 导入公共 GitHub 下载模块
    if [[ ! -f "$script_dir/github_downloader.sh" ]]; then
        echo "公共 GitHub 下载模块不存在: $script_dir/github_downloader.sh"
        exit 1
    fi
    source "$script_dir/github_downloader.sh" || {
        echo "导入公共 GitHub 下载模块失败: $script_dir/github_downloader.sh"
        exit 1
    }

    local API_URL="https://api.github.com/repos/FanchangWang/clash_config/contents/config.yaml"
    local HEADERS=("Accept: application/vnd.github.v3+json")

    # 获取 GitHub Token
    local github_token
    if github_token=$(get_github_token); then
        HEADERS+=("Authorization: token $github_token")
        echo "已添加 GitHub Token 认证头"
    fi

    echo "从 GitHub API 获取 SHA 和内容..."

    # 获取 GitHub 加速源列表
    local github_proxies
    github_proxies=$(get_github_proxies)

    # 随机打乱加速源
    local shuffled_proxies
    IFS=$'\n' read -d '' -r -a shuffled_proxies < <(shuf -e $github_proxies)

    # 尝试使用代理源获取数据
    local response
    for proxy in "${shuffled_proxies[@]}"; do
        echo "尝试从 $proxy 获取 API 数据..."
        local proxy_url="${proxy}${API_URL}"
        if response=$(curl -s -H "${HEADERS[@]}" "$proxy_url"); then
            # 检查响应是否有效
            if echo "$response" | grep -q '"sha":'; then
                echo "API 请求成功"
                break
            fi
        fi
    done

    # 如果代理源都失败，尝试原始地址
    if [[ -z "$response" || ! $(echo "$response" | grep -q '"sha":') ]]; then
        echo "尝试从原始地址获取 API 数据..."
        if ! response=$(curl -s -H "${HEADERS[@]}" "$API_URL"); then
            echo "错误：无法从 GitHub API 获取数据。"
            exit 1
        fi
    fi

    # 直接使用全局变量，无需local声明
    api_sha=$(echo "$response" | grep -o '"sha": "[^"]*' | cut -d'"' -f4)
    local content_base64=$(echo "$response" | grep -o '"content": "[^"]*' | cut -d'"' -f4 | sed 's/\\n/\n/g')
    content=$(echo "$content_base64" | base64 --decode)

    if [[ -z "$api_sha" || -z "$content" ]]; then
        echo "错误：无法从 API 响应中解析 sha 或 content。"
        exit 1
    fi
}

# 函数：读取本地文件的 SHA 值
get_local_sha() {
    local CONFIG_FILE="$1"
    if [[ -f "$CONFIG_FILE" ]]; then
        calculate_git_sha "$CONFIG_FILE"
    else
        echo ""
    fi
}

# 函数：备份并更新文件
backup_and_update() {
    echo "正在备份当前的 $mihomo_config_file 到 $mihomo_config_file_bak..."
    cp "$mihomo_config_file" "$mihomo_config_file_bak"

    echo "正在用新内容更新 $mihomo_config_file..."
    echo "$content" > "$mihomo_config_file_tmp"
    mv "$mihomo_config_file_tmp" "$mihomo_config_file"
}

# 函数：验证更新后的文件 SHA
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

# 主函数
function update_mihomo_config() {
    echo "================================================"
    echo "时间：$(TZ='Asia/Shanghai' date +%Y%m%d\ %H:%M:%S)"

    echo -e "\n设置 crontab 定时任务..."
    crontab_setup

    echo -e "\n开始执行配置更新..."
    fetch_from_api

    local local_sha
    local_sha=$(get_local_sha "$mihomo_config_file")

    echo "API SHA: $api_sha"
    echo "API content length: ${#content}"
    echo "Local SHA: $local_sha"

    if [[ "$local_sha" == "$api_sha" ]]; then
        echo "本地配置文件是最新的，无需更新。"
        exit 0
    fi

    backup_and_update
    validate_updated_file

    echo "重启 mihomo service..."
    systemctl restart mihomo

    echo "脚本执行完毕。"
}

# 执行主函数
update_mihomo_config
