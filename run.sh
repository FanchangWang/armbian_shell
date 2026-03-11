#!/bin/bash

# 检查必须是 root 用户
if [[ "$(id -u)" != 0 ]]; then
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

# 扫描所有脚本
scan_scripts() {
    local -a scripts=()
    local script id name

    # 使用 -print0 安全处理文件名，-regextype 精确匹配
    while IFS= read -r -d '' script; do
        # 提取文件名部分
        local basename="${script##*/}"

        # 严格匹配：数字_名称.sh（名称只允许字母数字下划线）
        if [[ "$basename" =~ ^([0-9]+)_([a-zA-Z0-9_]+)\.sh$ ]]; then
            id="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"
            # 直接按数字排序存储，避免二次排序
            scripts+=("$id:$name:$script")
        fi
    done < <(find . -regextype posix-extended \
        -regex '.*/[0-9]+_[a-zA-Z0-9_]+\.sh' \
        -type f -print0 | sort -z -t/ -k2 -n)

    # 输出结果（已经是数字排序）
    echo "${scripts[@]}"
}

# 读取脚本信息
read_script_info() {
    local script="$1"
    # 尝试获取脚本名和说明
    local script_name=$(grep -E "^script_name=" "$script" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d '\r' || echo "未定义")
    echo "$script_name"
}

# 显示菜单
show_menu() {
    local scripts=($1)
    echo -e "\n-------------- 功能列表 ------------------\n"
    printf "%3s | %-30s | %-30s\n" "ID" "name" "说明"
    echo "----+--------------------------------+------------------------------"
    for script in "${scripts[@]}"; do
        IFS=":" read -r id name path <<<"$script"
        script_name=$(read_script_info "$path")
        printf "%3s | %-30s | %-30s\n" "$id" "$name" "$script_name"
    done
    echo "----+--------------------------------+------------------------------"
    printf "%3s | %-30s | %-30s\n" "0" "exit" "退出脚本"
    echo -e "\n"
}

# 执行脚本
execute_script() {
    local scripts=($1)
    local choice="$2"

    for script in "${scripts[@]}"; do
        IFS=":" read -r id name path <<<"$script"
        if [[ "$id" == "$choice" ]]; then
            echo "执行脚本: $path"
            "$path"
            return 0
        fi
    done

    echo "无效的选项"
    return 1
}

# 主循环
main() {
while true; do
    # 在主循环开始时获取脚本列表
    local script_list=$(scan_scripts)
    show_menu "$script_list"
    read -r -p "请输入脚本标号: " choice
    if [[ "$choice" == "0" ]]; then
        exit 0
    fi
    execute_script "$script_list" "$choice"

    echo -e "\n按任意键继续..."
    read -s -n 1
done
}

main
