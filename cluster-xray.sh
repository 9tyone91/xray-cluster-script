#!/bin/bash

# 颜色定义
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

# 工具函数
gen_uuid() {
    if ! command -v uuidgen >/dev/null 2>&1; then
        echo -e "${yellow}uuidgen 命令未安装！${plain}"
        read -p "是否自动安装 uuid-runtime 包？(y/n，默认y): " install_choice
        install_choice=${install_choice:-y}
        if [[ "$install_choice" == "y" || "$install_choice" == "Y" ]]; then
            echo -e "${green}正在安装 uuid-runtime...${plain}"
            apt update && apt install uuid-runtime -y
            if ! command -v uuidgen >/dev/null 2>&1; then
                echo -e "${red}安装失败！请手动运行: apt install uuid-runtime -y${plain}" >&2
                exit 1
            fi
            echo -e "${green}uuidgen 安装成功！${plain}"
        else
            echo -e "${red}用户取消安装，退出脚本。${plain}"
            exit 1
        fi
    fi
    uuidgen
}

gen_keypair() {
    keypair=$($XRAY_BIN x25519 2>/dev/null)
    if [[ -z "$keypair" ]]; then
        echo -e "${red}x25519 生成失败！请检查 Xray 安装。${plain}" >&2
        exit 1
    fi
    private_key=$(echo "$keypair" | grep -i "private key" | awk '{print $3}')
    public_key=$(echo "$keypair" | grep -i "public key" | awk '{print $3}')
    if [[ -z "$private_key" || -z "$public_key" ]]; then
        echo -e "${red}keypair 解析失败！请手动运行 $XRAY_BIN x25519 查看输出格式。${plain}" >&2
        exit 1
    fi
    echo "$private_key $public_key"
}

gen_shortid() { openssl rand -hex 8; }

config_landing() {
    echo -e "${green}配置出口节点${plain}"
    port=$(($RANDOM % 50000 + 10000))
    read -p "端口 (默认 $port): " port_input && [[ -n "$port_input" ]] && port=$port_input

    uuid=$(gen_uuid)
    keypair=$(gen_keypair)
    private_key=$(echo $keypair | awk '{print $1}')
    public_key=$(echo $keypair | awk '{print $2}')
    short_id=$(gen_shortid)

    read -p "伪装网站 (默认 www.microsoft.com): " dest && [[ -z "$dest" ]] && dest="www.microsoft.com"

    conf_file="$CONF_DIR/VLESS-REALITY-EXPORT-$port.json"
    cat > "$conf_file" <<EOF
{
  "inbounds": [{
    "port": $port,
    "protocol": "vless",
    "settings": {"clients": [{"id": "$uuid", "flow": "xtls-rprx-vision"}], "decryption": "none"},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "$dest:443", "serverNames": ["$dest"], "privateKey": "$private_key", "publicKey": "$public_key", "shortIds": ["$short_id"]}},
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
    echo -e "${green}出口完成！文件: $conf_file${plain}"
    echo "UUID: $uuid"
    echo "Public Key: $public_key"
    echo "Short ID: $short_id"
    echo "端口: $port"
    echo "伪装: $dest"
    systemctl restart xray || $XRAY_BIN restart
}

# config_transit 函数（复制 config_landing 并修改 outbound/routing 部分）
config_transit() {
    echo -e "${green}配置中转节点${plain}"
    read -p "出口IP: " landing_ip
    read -p "出口端口: " landing_port
    read -p "出口UUID: " landing_uuid
    read -p "出口Public Key: " landing_pubkey
    read -p "出口Short ID: " landing_shortid

    transit_port=443
    read -p "中转端口 (默认443): " tport && [[ -n "$tport" ]] && transit_port=$tport

    read -p "伪装网站 (默认 www.microsoft.com): " dest && [[ -z "$dest" ]] && dest="www.microsoft.com"

    transit_uuid=$(gen_uuid)
    keypair=$(gen_keypair)
    transit_private=$(echo $keypair | awk '{print $1}')
    transit_public=$(echo $keypair | awk '{print $2}')
    transit_shortid=$(gen_shortid)

    conf_file="$CONF_DIR/VLESS-REALITY-TRANSIT-$transit_port.json"
    cat > "$conf_file" <<EOF
{
  "inbounds": [{
    "port": $transit_port,
    "protocol": "vless",
    "settings": {"clients": [{"id": "$transit_uuid", "flow": "xtls-rprx-vision"}], "decryption": "none"},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "$dest:443", "serverNames": ["$dest"], "privateKey": "$transit_private", "publicKey": "$transit_public", "shortIds": ["$transit_shortid"]}},
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }],
  "outbounds": [{
    "tag": "to-landing",
    "protocol": "vless",
    "settings": {"vnext": [{"address": "$landing_ip", "port": $landing_port, "users": [{"id": "$landing_uuid", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "$dest:443", "serverNames": ["$dest"], "privateKey": "$transit_private", "shortIds": ["$landing_shortid"]}}
  }],
  "routing": {"rules": [{"type": "field", "outboundTag": "to-landing", "network": "tcp,udp"}]}
}
EOF
    echo -e "${green}中转完成！文件: $conf_file${plain}"
    echo "UUID: $transit_uuid"
    echo "Public Key: $transit_public"
    echo "Short ID: $transit_shortid"
    systemctl restart xray || $XRAY_BIN restart
}

echo -e "${yellow}集群脚本菜单${plain}"
echo "1. 配置出口节点"
echo "2. 配置中转节点"
echo "3. 退出"
read -p "选择: " choice

case $choice in
    1) config_landing ;;
    2) config_transit ;;
    3) exit 0 ;;
    *) echo "无效选择" ;;
esac

echo -e "${green}完成！服务已重启。"
echo "检查配置: ls $CONF_DIR"
echo "查看文件: cat $CONF_DIR/VLESS-REALITY-*.json"
echo "用 'xray' 进入原233boy菜单管理。"
