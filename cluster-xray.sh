#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}必须root运行！${plain}" && exit 1

CONF_DIR="/etc/xray/conf"
XRAY_BIN="/etc/xray/bin/xray"

if [[ ! -d "$CONF_DIR" ]]; then
    echo -e "${green}安装233boy Xray...${plain}"
    bash <(wget -qO- https://github.com/233boy/Xray/raw/main/install.sh) || exit 1
    sleep 5
fi

gen_uuid() {
    if ! command -v uuidgen >/dev/null 2>&1; then
        echo -e "${yellow}uuidgen 未安装！${plain}"
        read -p "是否自动安装 uuid-runtime？(y/n，默认y): " ch
        ch=${ch:-y}
        [[ "$ch" == "y" || "$ch" == "Y" ]] && apt update && apt install uuid-runtime -y
        if ! command -v uuidgen >/dev/null 2>&1; then
            echo -e "${red}安装失败，请手动: apt install uuid-runtime -y${plain}" >&2
            exit 1
        fi
    fi
    uuidgen
}

gen_keypair() {
    keypair=$($XRAY_BIN x25519 2>/dev/null)
    if [[ -z "$keypair" ]]; then
        echo -e "${red}x25519 生成失败！请手动检查 Xray。${plain}" >&2
        exit 1
    fi
    private_key=$(echo "$keypair" | grep -i "private key" | awk '{print $3}')
    public_key=$(echo "$keypair" | grep -i "public key" | awk '{print $3}')
    if [[ -z "$private_key" || -z "$public_key" ]]; then
        echo -e "${yellow}keypair 解析失败！${plain}"
        echo "请手动运行: $XRAY_BIN x25519"
        echo "复制 Private key 和 Public key"
        read -p "输入 Private key: " private_key
        read -p "输入 Public key: " public_key
        if [[ -z "$private_key" || -z "$public_key" ]]; then
            echo -e "${red}用户未输入 key，退出。${plain}"
            exit 1
        fi
    fi
    echo "$private_key $public_key"
}

gen_shortid() { openssl rand -hex 8; }

# config_landing 函数（同上，略，保持不变）

# ... config_transit 函数同上

# 菜单部分同上

# 在配置函数末尾加 key 检查（示例在 config_landing 后加）
if [[ "$choice" == "1" ]]; then
    conf_file="$CONF_DIR/VLESS-REALITY-EXPORT-$port.json"
    if grep -q '"privateKey": ""' "$conf_file" || grep -q '"publicKey": ""' "$conf_file"; then
        echo -e "${yellow}文件 key 为空！请手动补：nano $conf_file${plain}"
    fi
fi
