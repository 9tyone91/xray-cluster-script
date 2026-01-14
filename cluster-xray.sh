#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $$   EUID -ne 0 ]] && echo -e "   $${red}必须root运行！${plain}" && exit 1

CONF_DIR="/etc/xray/conf"
MAIN_CONF="/etc/xray/config.json"
XRAY_BIN="/etc/xray/bin/xray"  # 你的实际路径

if [[ ! -d "$CONF_DIR" ]]; then
    echo -e "$$   {red}未找到配置目录！   $${plain}"
    exit 1
fi

gen_uuid() { uuidgen; }
gen_keypair() {
    keypair=$($XRAY_BIN x25519)
    private_key=$(echo "$keypair" | grep "Private" | awk '{print $3}')
    public_key=$(echo "$keypair" | grep "Public" | awk '{print $3}')
    echo "$private_key $public_key"
}
gen_shortid() { openssl rand -hex 8; }

config_landing() {
    echo -e "$$   {green}配置出口节点   $${plain}"
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
    echo "完成！UUID: $uuid | PubKey: $public_key"
    $XRAY_BIN restart
}

# config_transit 函数（类似，添加 outbound "to-landing"）
config_transit() {
    echo -e "$$   {green}配置中转节点   $${plain}"
    read -p "出口IP: " landing_ip
    read -p "出口端口: " landing_port
    read -p "出口UUID: " landing_uuid
    read -p "出口PubKey: " landing_pubkey
    read -p "出口ShortID: " landing_shortid

    transit_port=443
    read -p "中转端口 (默认443): " transit_input && [[ -n "$transit_input" ]] && transit_port=$transit_input

    read -p "伪装网站: " dest && [[ -z "$dest" ]] && dest="www.microsoft.com"

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
    echo "完成！UUID: $transit_uuid | PubKey: $transit_public"
    $XRAY_BIN restart
}

list_configs() {
    echo -e "$$   {green}配置列表   $${plain}"
    ls -l $CONF_DIR/*.json 2>/dev/null || echo "无配置"
    for f in $CONF_DIR/*.json; do
        echo "文件: $(basename $f)"
        grep -E '"tag": "to-landing"|"address":' $f || echo "无relay"
        echo "---"
    done
}

main_menu() {
    echo -e "$$   {yellow}集群管理菜单   $${plain}"
    echo "1. 配置出口"
    echo "2. 配置中转"
    echo "3. 列表检查"
    echo "4. 原xray菜单"
    echo "0. 退出"
    read -p "选择: " ch
    case $ch in
        1) config_landing ;;
        2) config_transit ;;
        3) list_configs ;;
        4) $XRAY_BIN ;;
        0) exit ;;
        *) echo "无效" ;;
    esac
    main_menu
}

main_menu
