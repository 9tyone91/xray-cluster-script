#!/bin/bash

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}必须root运行！${plain}" && exit 1

# 路径自动检测（你的服务器是 /etc/xray/）
CONF_DIR="/etc/xray/conf"
MAIN_CONF="/etc/xray/config.json"
XRAY_BIN="/etc/xray/bin/xray"  # 你的实际 xray 命令路径

if [[ ! -d "$CONF_DIR" ]]; then
    echo -e "${red}未找到 Xray 配置目录！请先运行233boy安装。${plain}"
    exit 1
fi

# 工具函数
gen_uuid() { uuidgen; }
gen_keypair() {
    keypair=$($XRAY_BIN x25519)
    private_key=$(echo "$keypair" | grep "Private" | awk '{print $3}')
    public_key=$(echo "$keypair" | grep "Public" | awk '{print $3}')
    echo "$private_key $public_key"
}
gen_shortid() { openssl rand -hex 8; }

# 配置出口节点
config_landing() {
    echo -e "${green}配置出口节点（统一出站IP）${plain}"
    port=$(($RANDOM % 50000 + 10000))
    read -p "端口 (默认随机 $port): " input_port
    [[ -n "$input_port" ]] && port=$input_port

    uuid=$(gen_uuid)
    keypair=$(gen_keypair)
    private_key=$(echo $keypair | awk '{print $1}')
    public_key=$(echo $keypair | awk '{print $2}')
    short_id=$(gen_shortid)

    read -p "伪装网站 (默认 www.microsoft.com): " dest_domain
    [[ -z "$dest_domain" ]] && dest_domain="www.microsoft.com"

    conf_file="$CONF_DIR/VLESS-REALITY-EXPORT-$port.json"
    cat > "$conf_file" <<EOF
{
  "inbounds": [
    {
      "port":
