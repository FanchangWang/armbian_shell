#!/bin/bash

# 脚本标识
script_name="Docker Compose 管理工具"



# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取所有数字开头的 yaml 配置文件
function get_compose_files() {
    local compose_dir="./compose"

    if [ ! -d "$compose_dir" ]; then
        echo -e "${RED}错误：目录 $compose_dir 不存在！${NC}" >&2
        exit 1
    fi

    local -a compose_files=()
    local file basename id name

    # 直接用 find + sort，避免数组转换问题
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        basename="${file##*/}"

        # 调试：取消注释看是否匹配
        # echo "Checking: $basename" >&2

        if [[ "$basename" =~ ^([0-9]+)_([a-zA-Z0-9_-]+)\.yaml$ ]]; then
            id="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"
            compose_files+=("$id:$name:$file")
        # else
            # echo "No match: $basename" >&2
        fi
    done < <(find "$compose_dir" -maxdepth 1 -name "[0-9]*.yaml" -type f | sort -V)

    echo "${compose_files[@]}"
}

# 获取容器状态
function get_container_status() {
    local compose_file="$1"

    # 使用 docker compose ps 检查是否有运行中的容器
    local running_containers=$(docker compose -f "$compose_file" ps -q | wc -l)

    if [ "$running_containers" -gt 0 ]; then
        echo "已启动"
    else
        echo "已停止"
    fi
}

# 展示配置文件菜单
function show_menu() {
    local compose_files=($@)

    # 一次性获取所有容器状态
    local -A container_status_map

    # 先初始化所有项目为已停止状态
    for item in "${compose_files[@]}"; do
        IFS=":" read -r id name path <<<"$item"
        container_status_map["$path"]="已停止"
    done

    # 使用 docker ps -a 获取所有容器信息，包括名称和状态
    # 输出格式：CONTAINER ID   IMAGE     COMMAND                  CREATED          STATUS                     PORTS     NAMES
    local all_containers=$(docker ps -a --format "{{.Names}} {{.Status}}")

    # 遍历所有配置文件，检查是否有对应项目的运行中容器
    for item in "${compose_files[@]}"; do
        IFS=":" read -r id name path <<<"$item"

        # 检查是否有该项目的运行中容器
        # Docker Compose 容器名称格式：项目名称_服务名称_序号
        if echo "$all_containers" | grep "^$name" | grep " Up "; then
            container_status_map["$path"]="已启动"
        fi
    done

    echo -e "\n${GREEN}=== Docker Compose 配置列表 ===${NC}"
    echo -e "${YELLOW}ID  | 容器名                      | 状态${NC}"
    echo -e "----+--------------------------------+-------"

    for item in "${compose_files[@]}"; do
        IFS=":" read -r id name path <<<"$item"
        local status=${container_status_map["$path"]}
        printf "%2s  | %-30s | %s\n" "$id" "$name" "$status"
    done

    echo -e "${YELLOW}--------------------------------+-------${NC}"
    printf "%2s  | %-30s | %s\n" "0" "exit" "退出脚本"
    echo -e "\n"
}

# 获取绑定的端口
function get_ports() {
    local compose_file="$1"

    # 获取绑定的端口
    local ports=$(docker compose -f "$compose_file" config --format json 2>/dev/null | jq -r '.services[].ports[].published' 2>/dev/null | grep -E '^[0-9]+$')

    if [ -n "$ports" ]; then
        # 获取内部 IP 地址
        local internal_ip=$(hostname -I | awk '{print $1}')

        echo -e "\n${YELLOW}存在端口绑定，如果存在 WEB UI，请尝试访问以下地址:${NC}"
        for port in $ports; do
            echo -e "http://${internal_ip}:${port}"
        done
        echo -e "\n按任意键继续..."
        read -s -n 1
    fi
}

# 启动 Docker Compose 配置
function start_compose() {
    local compose_file="$1"

    echo -e "\n${GREEN}启动 $compose_file...${NC}"
    docker compose -f "$compose_file"  up -d
    get_ports "$compose_file"
}

# 停止 Docker Compose 配置
function stop_compose() {
    local compose_file="$1"

    echo -e "\n${RED}停止 $compose_file...${NC}"
    docker compose -f "$compose_file" down
}

# 重启 Docker Compose 配置
function restart_compose() {
    local compose_file="$1"

    echo -e "\n${YELLOW}重启 $compose_file...${NC}"
    docker compose -f "$compose_file" restart
    get_ports "$compose_file"
}

# 根据选择的文件ID查找对应的文件路径
function find_file_by_id() {
    local id="$1"
    local compose_files=($2)

    for item in "${compose_files[@]}"; do
        IFS=":" read -r file_id name path <<<"$item"
        if [[ "$file_id" == "$id" ]]; then
            echo "$path"
            return 0
        fi
    done

    echo ""
    return 1
}

# 主函数
function up_docker_compose() {
    # 获取所有配置文件
    local compose_files=($(get_compose_files))
    local total_files=${#compose_files[@]}

    if [ "$total_files" -eq 0 ]; then
        echo -e "\n${RED}没有找到任何数字开头的 yaml 配置文件！${NC}"
        exit 1
    fi

    # 主循环
    while true; do
        # 显示配置列表
        show_menu "${compose_files[@]}"

        # 手动输入 ID 编号
        read -r -p "请输入要操作的容器 ID: " selected_id

        # 处理退出脚本
        if [[ "$selected_id" == "0" ]]; then
            echo -e "\n${GREEN}退出脚本！${NC}"
            break
        fi

        # 查找对应的文件路径
        local selected_file=$(find_file_by_id "$selected_id" "${compose_files[*]}")

        if [ -z "$selected_file" ]; then
            echo -e "${RED}错误：无效的 ID 编号！${NC}"
            continue
        fi

        # 显示当前操作的容器信息
        echo -e "\n${YELLOW}当前操作的容器：${NC}"
        echo -e "ID: $selected_id\t文件: $selected_file\n正在校准状态..."

        # 获取当前状态
        local current_status=$(get_container_status "$selected_file")
        echo -e "当前状态：${current_status}"

        # 根据状态显示不同的操作选项
        local operation
        if [ "$current_status" = "已启动" ]; then
            # 已启动状态：只显示重启、退出选项
            echo -e "\n请选择操作："
            echo -e "1) 重启 compose"
            echo -e "2) 停止 compose"
            echo -e "0) 返回主菜单"
            read -r -p "请输入操作选择 [0-2]: " operation

            case $operation in
                1) # 重启 compose
                    restart_compose "$selected_file"
                    ;;
                2) # 停止 compose
                    stop_compose "$selected_file"
                    ;;
                0) # 返回主菜单
                    echo -e "\n${GREEN}操作已取消！${NC}"
                    continue
                    ;;
                *)
                    echo -e "${RED}错误：无效的操作选择！${NC}"
                    continue
                    ;;
            esac
        else
            # 已停止状态：只显示启动选项
            echo -e "\n请选择操作："
            echo -e "1) 启动 compose"
            echo -e "0) 返回主菜单"
            read -r -p "请输入操作选择 [0-1]: " operation

            case $operation in
                1) # 启动 compose
                    start_compose "$selected_file"
                    ;;
                0) # 返回主菜单
                    echo -e "\n${GREEN}操作已取消！${NC}"
                    continue
                    ;;
                *)
                    echo -e "${RED}错误：无效的操作选择！${NC}"
                    continue
                    ;;
            esac
        fi

        echo -e "\n${GREEN}操作完成！${NC}"
    done
}

# 主函数调用
up_docker_compose
