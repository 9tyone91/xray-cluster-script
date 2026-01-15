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
    echo -e "${green}生成 Reality keypair...${plain}"
    echo -e "${yellow}请从下面原始完整输出中复制 Private key 和 Public key，然后补到文件：${plain}"
    echo -e "${yellow}补文件命令: nano $CONF_DIR/VLESS-REALITY-EXPORT-*.json${plain}"
    echo -e "${yellow}替换 \"privateKey\": \"\" 和 \"publicKey\": \"\"，然后重启: systemctl restart xray${plain}"

    keypair_raw=$($XRAY_BIN x25519 2>/dev/null)
    echo -e "${yellow}原始完整输出（复制这里的长字符串key）：${plain}"
    echo "$keypair_raw"

    # 不再自动提取，直接让用户手动补
    echo -e "${green}Private Key 和 Public Key 已打印在上面原始输出中，请复制使用。${plain}"
    exit 0  # 退出，让用户手动补
}

gen_shortid() { openssl rand -hex 8; }

config_landing() {
    echo -e "${green}配置出口节点${plain}"
    port=$(($RANDOM % 50000 + 10000))
    read -p "端口 (默认 $port): " port_input && [[ -n "$port_input" ]] && port=$port_input

    uuid=$(gen_uuid)
    keypair=$(gen_keypair)  # 这里会打印原始输出并退出
    short_id=$(gen_shortid)

    read -p "伪装网站 (默认 www.microsoft.com): " dest && [[ -z "$dest" ]] && dest="www.microsoft.com"

    conf_file="$CONF_DIR/VLESS-REALITY-EXPORT-$port.json"
    cat > "$conf_file" <<EOF
{
  "inbounds": [{
    "port": $port,
    "protocol": "vless",
    "settings": {"clients": [{"id": "$uuid", "flow": "xtls-rprx-vision"}], "decryption": "none"},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "$dest:443", "serverNames": ["$dest"], "privateKey": "", "publicKey": "", "shortIds": ["$short_id"]}},
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
    echo -e "${green}文件已生成 (key为空，请手动补): $conf_file${plain}"
    echo "UUID: $uuid"
    echo "Short ID: $short_id"
    echo "端口: $port"
    echo "伪装: $dest"

    server_ip=$(curl -s ifconfig.me || echo "你的服务器IP")
    echo -e "${yellow}vless 链接模板（补pbk后使用）:${plain}"
    echo "vless://$uuid@$server_ip:$port?encryption=none&security=reality&pbk=你的PublicKey&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$dest&sid=$short_id#出口节点"

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
    short_id=$(gen_shortid)

    conf_file="$CONF_DIR/VLESS-REALITY-TRANSIT-$transit_port.json"
    cat > "$conf_file" <<EOF
{
  "inbounds": [{
    "port": $transit_port,
    "protocol": "vless",
    "settings": {"clients": [{"id": "$transit_uuid", "flow": "xtls-rprx-vision"}], "decryption": "none"},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "$dest:443", "serverNames": ["$dest"], "privateKey": "", "publicKey": "", "shortIds": ["$short_id"]}},
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }],
  "outbounds": [{
    "tag": "to-landing",
    "protocol": "vless",
    "settings": {"vnext": [{"address": "$landing_ip", "port": $landing_port, "users": [{"id": "$landing_uuid", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "$dest:443", "serverNames": ["$dest"], "privateKey": "", "shortIds": ["$landing_shortid"]}}
  }],
  "routing": {"rules": [{"type": "field", "outboundTag": "to-landing", "network": "tcp,udp"}]}
}
EOF
    echo -e "${green}完成！文件: $conf_file${plain}"
    echo "UUID: $transit_uuid"
    echo "Short ID: $short_id"
    echo "请手动补 privateKey 和 publicKey 到文件，然后重启服务"
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
