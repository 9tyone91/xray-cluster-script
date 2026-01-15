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

gen_keypair() {
    echo -e "${green}自动生成 Reality keypair...${plain}"
    local keypair_raw=$($XRAY_BIN x25519 2>/dev/null)

    # 打印原始完整输出（你从这里看清 key）
    echo -e "${yellow}原始完整输出（请查看 Private/Public key）：${plain}"
    echo "$keypair_raw"

    # 最宽松提取：找包含 "private" 或 "public" 的行，取冒号后所有内容
    private_key=$(echo "$keypair_raw" | grep -i "private" | cut -d':' -f2- | sed 's/^ *//;s/ *$//')
    public_key=$(echo "$keypair_raw" | grep -i "public" | cut -d':' -f2- | sed 's/^ *//;s/ *$//')

    # 如果提取失败，使用原始输出作为 fallback（完整字符串）
    if [[ -z "$private_key" ]]; then
        private_key=$(echo "$keypair_raw" | grep -i "private" | cut -d':' -f2-)
    fi
    if [[ -z "$public_key" ]]; then
        public_key=$(echo "$keypair_raw" | grep -i "public" | cut -d':' -f2-)
    fi

    # 最终强制显示
    echo -e "${green}提取的 Private Key: $private_key${plain}"
    echo -e "${green}提取的 Public Key: $public_key${plain}"

    echo "$private_key $public_key"
}

gen_shortid() { openssl rand -hex 8; }

config_landing() {
    echo -e "${green}配置出口节点${plain}"
    port=$(($RANDOM % 50000 + 10000))
    read -p "端口 (默认 $port): " port_input && [[ -n "$port_input" ]] && port=$port_input

    uuid=$(gen_uuid)
    keypair=$(gen_keypair)
    private_key=$(echo "$keypair" | awk '{print $1}')
    public_key=$(echo "$keypair" | awk '{print $2}')
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
    echo "Short ID: $short_id"
    echo "端口: $port"
    echo "伪装: $dest"

    echo -e "${green}Private Key: $private_key${plain}"
    echo -e "${green}Public Key: $public_key${plain}"

    server_ip=$(curl -s ifconfig.me || echo "你的服务器IP")
    echo -e "${yellow}完整 vless 链接（直接复制导入客户端）:${plain}"
    echo "vless://$uuid@$server_ip:$port?encryption=none&security=reality&pbk=$public_key&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$dest&sid=$short_id#出口节点"

    systemctl restart xray || $XRAY_BIN restart
}

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
    transit_private=$(echo "$keypair" | awk '{print $1}')
    transit_public=$(echo "$keypair" | awk '{print $2}')
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
    echo -e "${green}完成！文件: $conf_file${plain}"
    echo "UUID: $transit_uuid"
    echo "Public Key: $transit_public"
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
echo "检查: ls $CONF_DIR && cat $CONF_DIR/VLESS-REALITY-*.json"
echo "用 'xray' 进入原菜单。"
