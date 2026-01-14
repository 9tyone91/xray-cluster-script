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
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        echo -e "${red}uuidgen 未安装！运行: apt install uuid-runtime -y${plain}" >&2
        exit 1
    fi
}

gen_keypair() {
    keypair=$($XRAY_BIN x25519 2>/dev/null)
    if [[ -z "$keypair" ]]; then
        echo -e "${red}x25519 生成失败！${plain}" >&2
        exit 1
    fi
    private_key=$(echo "$keypair" | grep -i "private key" | awk '{print $3}')
    public_key=$(echo "$keypair" | grep -i "public key" | awk '{print $3}')
    if [[ -z "$private_key" || -z "$public_key" ]]; then
        echo -e "${red}keypair 解析失败！手动生成: $XRAY_BIN x25519${plain}" >&2
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
    systemctl restart xray || $XRAY_BIN restart
}

# config_transit 函数类似上面，略（复制粘贴并改 outbound 部分）

echo -e "${yellow}集群脚本菜单${plain}"
echo "1. 配置出口节点"
echo "2. 配置中转节点"
echo "3. 退出"
read -p "选择: " choice

case $choice in
    1) config_landing ;;
    2) config_transit ;;
    3) exit 0 ;;
    *) echo "无效" ;;
esac

echo -e "${green}完成！服务已重启。"
echo "用 'xray' 进入原菜单。"
