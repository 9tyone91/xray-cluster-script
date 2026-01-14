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
        read -p "自动安装 uuid-runtime？(y/n，默认y): " ch
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
    private_key=$(echo "$keypair" | grep -i "private" | awk '{print $3}')
    public_key=$(echo "$keypair" | grep -i "public" | awk '{print $3}')
    if [[ -z "$private_key" || -z "$public_key" ]]; then
        echo -e "${yellow}keypair 自动生成失败！请手动输入${plain}"
        read -p "Private key: " private_key
        read -p "Public key: " public_key
        if [[ -z "$private_key" || -z "$public_key" ]]; then
            echo -e "${red}未输入 key，退出${plain}"
            exit 1
        fi
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
    echo -e "${green}完成！文件: $conf_file${plain}"
    echo "UUID: $uuid"
    echo "Public Key: $public_key"
    echo "Short ID: $short_id"
    echo "端口: $port"
    systemctl restart xray || $XRAY_BIN restart
}

echo -e "${yellow}集群脚本菜单${plain}"
echo "1. 配置出口节点"
echo "2. 退出（中转后面再加）"
read -p "选择: " choice

case $choice in
    1) config_landing ;;
    2) exit 0 ;;
    *) echo "无效" ;;
esac

echo -e "${green}完成！服务已重启。"
echo "检查: ls $CONF_DIR && cat $CONF_DIR/VLESS-REALITY-*.json"
echo "用 'xray' 进入原菜单。"
