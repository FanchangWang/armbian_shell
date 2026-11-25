#!/bin/bash

# 脚本标识
script_name="设置 Docker 加速镜像"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

DAEMON_JSON="/etc/docker/daemon.json"

# 加速镜像列表（只替换 registry-mirrors，保留 daemon.json 中的其他配置）
MIRRORS=(
    "https://docker.m.daocloud.io"
    "https://docker.1ms.run"
    "https://docker.1panel.live"
    "https://docker.ketches.cn"
    "https://gh-proxy.org/docker/"
    "https://v4.gh-proxy.org/docker/"
    "https://v6.gh-proxy.org/docker/"
    "https://cdn.gh-proxy.org/docker/"
)

# 构造 registry-mirrors 的 JSON 数组
function mirrors_json() {
    local result=""
    local mirror
    for mirror in "${MIRRORS[@]}"; do
        [[ -n "$result" ]] && result+=","
        result+="\"$mirror\""
    done
    printf '[%s]' "$result"
}

# 只改 registry-mirrors 字段，其余字段原样保留
function write_config() {
    local mirrors tmp_file target config_dir
    mirrors=$(mirrors_json)

    # 若 daemon.json 是软链接，操作真实目标，避免 mv 覆盖链接本身
    target="$DAEMON_JSON"
    if [[ -L "$DAEMON_JSON" ]]; then
        target=$(readlink -f "$DAEMON_JSON") || return 1
        [[ -n "$target" ]] || return 1
    fi
    config_dir=$(dirname "$target")

    # 临时文件与目标同目录，最后用 mv 原子替换，避免写坏现有配置
    mkdir -p "$config_dir" || return 1
    tmp_file=$(mktemp "$config_dir/.daemon.json.XXXXXX") || return 1
    # 新建文件默认 644，不沿用 mktemp 的 600
    chmod 644 "$tmp_file" || { rm -f "$tmp_file"; return 1; }

    if command -v jq >/dev/null 2>&1; then
        if [[ -s "$target" ]] && jq -e -s 'length == 1 and (.[0] | type == "object")' "$target" >/dev/null 2>&1; then
            jq --argjson mirrors "$mirrors" '."registry-mirrors" = $mirrors' "$target" > "$tmp_file"
        else
            [[ -s "$target" ]] && echo -e "${YELLOW}警告：原配置不是单个合法 JSON 对象，已备份并重建${NC}"
            jq -n --argjson mirrors "$mirrors" '{ "registry-mirrors": $mirrors }' > "$tmp_file"
        fi
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$target" "$mirrors" > "$tmp_file" <<'PY'
import json
import sys

path = sys.argv[1]
mirrors = json.loads(sys.argv[2])
config = {}
try:
    with open(path, encoding="utf-8") as f:
        loaded = json.load(f)
    if isinstance(loaded, dict):
        config = loaded
    else:
        print("警告：原配置不是 JSON 对象，已忽略", file=sys.stderr)
except FileNotFoundError:
    pass
except json.JSONDecodeError:
    print("警告：原配置不是合法 JSON，已备份并重建", file=sys.stderr)

config["registry-mirrors"] = mirrors
print(json.dumps(config, ensure_ascii=False, indent=2))
PY
    else
        # 没有 jq / python3 时，绝不覆盖已有配置，避免丢失用户自定义内容
        if [[ -s "$target" ]]; then
            echo -e "${RED}错误：缺少 jq 或 python3，无法安全修改现有配置（请先安装 jq）${NC}" >&2
            rm -f "$tmp_file"
            return 1
        fi
        printf '{\n  "registry-mirrors": %s\n}\n' "$mirrors" > "$tmp_file"
    fi

    # 写入前校验生成结果，确保不会写入损坏的 JSON
    if command -v jq >/dev/null 2>&1; then
        if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$tmp_file" >/dev/null 2>&1; then
            echo -e "${RED}错误：生成的配置不是单个合法 JSON 对象，未改动原文件${NC}" >&2
            rm -f "$tmp_file"
            return 1
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if ! python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$tmp_file"; then
            echo -e "${RED}错误：生成的配置不是合法 JSON，未改动原文件${NC}" >&2
            rm -f "$tmp_file"
            return 1
        fi
    fi

    if [[ -f "$target" ]]; then
        if ! cp -a "$target" "${target}.bak.$(date +%Y%m%d%H%M%S)"; then
            echo -e "${RED}错误：备份失败，未改动原配置${NC}" >&2
            rm -f "$tmp_file"
            return 1
        fi
        # 沿用原文件的属主和权限
        chmod --reference="$target" "$tmp_file" 2>/dev/null || true
        chown --reference="$target" "$tmp_file" 2>/dev/null || true
        echo -e "${YELLOW}已备份原配置：${target}.bak.*${NC}"
    fi
    if ! mv -f "$tmp_file" "$target"; then
        echo -e "${RED}错误：写入 $target 失败${NC}" >&2
        rm -f "$tmp_file"
        return 1
    fi
}

function restart_docker() {
    local status

    if ! command -v systemctl >/dev/null 2>&1 && ! command -v service >/dev/null 2>&1; then
        echo -e "${YELLOW}未找到 systemctl / service，请手动重启 Docker 以使配置生效${NC}"
        return 0
    fi

    echo -e "${YELLOW}正在重启 Docker 服务，可能需要几十秒，请稍候...${NC}"
    # 后台打印进度点，避免用户以为脚本卡住
    ( while true; do printf "."; sleep 2; done ) &
    local spinner_pid=$!

    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart docker
        status=$?
    else
        service docker restart
        status=$?
    fi

    kill "$spinner_pid" 2>/dev/null
    wait "$spinner_pid" 2>/dev/null
    printf "\n"

    if [[ $status -eq 0 ]]; then
        echo -e "${GREEN}Docker 已重启${NC}"
    else
        echo -e "${RED}警告：Docker 重启失败（退出码 $status），请手动执行 systemctl restart docker${NC}"
    fi
}

function set_docker_mirrors() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}错误：未检测到 Docker，请先执行编号 4 安装 Docker${NC}"
        return 1
    fi

    echo -e "${GREEN}仅修改 ${DAEMON_JSON} 中的 registry-mirrors，其他配置保持不变${NC}"
    if [[ -f "$DAEMON_JSON" ]]; then
        echo -e "${YELLOW}当前配置：${NC}"
        cat "$DAEMON_JSON"
    else
        echo -e "${YELLOW}当前没有 ${DAEMON_JSON}，将新建${NC}"
    fi
    echo -e "${YELLOW}即将设置的加速镜像：${NC}"
    printf '  %s\n' "${MIRRORS[@]}"

    if ! read -r -p "确认设置并重启 Docker? (y/n, 默认 y): " confirm; then
        echo -e "${YELLOW}未收到输入，已取消${NC}"
        return 1
    fi
    case "$confirm" in
        [nN]|[nN][oO])
            echo "已取消"
            return 0
            ;;
        ""|[yY]|[yY][eE][sS])
            ;;
        *)
            echo -e "${RED}无效输入，已取消${NC}"
            return 1
            ;;
    esac

    write_config || return 1
    echo -e "${GREEN}registry-mirrors 设置完成${NC}"
    restart_docker
}

set_docker_mirrors
