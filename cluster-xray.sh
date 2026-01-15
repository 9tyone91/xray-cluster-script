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
        apt update && apt install uuid-runtime -y
    fi
    uuidgen
}

gen_shortid() {
    local sid
    sid=$(openssl rand -hex 8)
    while [[ ! $sid =~ ^[0-9a-fA-F]{16}$ ]]; do
        sid=$(openssl rand -hex 8)
    done
    echo "$sid"
}

config_node() {
    local node_type="$1"  # "出口" or "中转"
    local is_transit=0
    [[ "$node_type" == "中转" ]] && is_transit=1

    echo -e "${green}配置${node_type}节点${plain}"
    local port
    if [[ $is_transit -eq 1 ]]; then
        port=443
        read -p "中转端口 (默认443): " port_input && [[ -n "$port_input" ]] && port=$port_input
    else
        port=$(($RANDOM % 50000 + 10000))
        read -p "端口 (默认 $port): " port_input && [[ -n "$port_input" ]] && port=$port_input
    fi

    local uuid=$(gen_uuid)
    local short_id=$(gen_shortid)

    local dest
    read -p "伪装网站 (默认 www.microsoft.com): " dest && [[ -z "$dest" ]] && dest="www.microsoft.com"

    echo -e "${yellow}请先运行 $XRAY_BIN x25519 获取 key，然后粘贴：${plain}"
    read -p "Private key (服务器用): " private_key
    read -p "Public key (客户端pbk用): " public_key

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        echo -e "${red}key 未输入，退出${plain}"
        exit 1
    fi

    echo -e "${green}你输入的 Private Key: $private_key${plain}"
    echo -e "${green}你输入的 Public Key: $public_key${plain}"
    echo -e "${green}Short ID: $short_id${plain}"

    local conf_file
    if [[ $is_transit -eq 1 ]]; then
        conf_file="$CONF_DIR/VLESS-REALITY-TRANSIT-$port.json"
    else
        conf_file="$CONF_DIR/VLESS-REALITY-EXPORT-$port.json"
    fi

    local config_content
    if [[ $is_transit -eq 1 ]]; then
        read -p "出口IP: " landing_ip
        read -p "出口端口: " landing_port
        read -p "出口UUID: " landing_uuid
        read -p "出口Public Key: " landing_pubkey
        read -p "出口Short ID: " landing_shortid

        config_content=$(cat <<EOF
{
  "inbounds": [{
    "port": $port,
    "protocol": "vless",
    "settings": {"clients": [{"id": "$uuid", "flow": "xtls-rprx-vision"}], "decryption": "none"},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "$dest:443", "serverNames": ["$dest"], "privateKey": "$private_key", "publicKey": "$public_key", "shortIds": ["$short_id"]}},
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }],
  "outbounds": [{
    "tag": "to-landing",
    "protocol": "vless",
    "settings": {"vnext": [{"address": "$landing_ip", "port": $landing_port, "users": [{"id": "$landing_uuid", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "$dest:443", "serverNames": ["$dest"], "privateKey": "$private_key", "shortIds": ["$landing_shortid"]}}
  }],
  "routing": {"rules": [{"type": "field", "outboundTag": "to-landing", "network": "tcp,udp"}]}
}
EOF
)
    else
        config_content=$(cat <<EOF
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
)
    fi

    echo "$config_content" > "$conf_file"
    echo -e "${green}完成！文件: $conf_file${plain}"
    echo "UUID: $uuid"
    echo "Short ID: $short_id"
    echo "端口: $port"
    echo "伪装: $dest"

    local server_ip=$(curl -s ifconfig.me || echo "你的服务器IP")
    local link
    if [[ $is_transit -eq 1 ]]; then
        link="vless://$uuid@$server_ip:$port?encryption=none&security=reality&pbk=$public_key&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$dest&sid=$short_id#中转节点（固定出口IP）"
    else
        link="vless://$uuid@$server_ip:$port?encryption=none&security=reality&pbk=$public_key&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$dest&sid=$short_id#出口节点"
    fi

    echo -e "${yellow}完整 vless 链接（直接复制导入客户端）:${plain}"
    echo "$link"

    echo -e "${yellow}请开防火墙端口（如果未开）：${plain}"
    echo "ufw allow $port/tcp || iptables -A INPUT -p tcp --dport $port -j ACCEPT && iptables-save > /etc/iptables.rules"

    systemctl restart xray || $XRAY_BIN restart
}

echo -e "${yellow}集群脚本菜单${plain}"
echo "1. 配置出口节点"
echo "2. 配置中转节点"
echo "3. 退出"
read -p "选择: " choice

case $choice in
    1) config_node "出口" ;;
    2) config_node "中转" ;;
    3) exit 0 ;;
    *) echo "无效选择" ;;
esac

echo -e "${green}完成！服务已重启。"
echo "检查: ls $CONF_DIR && cat $CONF_DIR/VLESS-REALITY-*.json"
echo "用 'xray' 进入原菜单。"
