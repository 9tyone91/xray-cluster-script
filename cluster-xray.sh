#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
bold='\033[1m'

[[ $EUID -ne 0 ]] && echo -e "${red}${bold}错误：必须root运行！${plain}" && exit 1

CONF_DIR="/etc/xray/conf"
XRAY_BIN="/etc/xray/bin/xray"

if [[ ! -d "$CONF_DIR" ]]; then
    echo -e "${green}安装 233boy Xray...${plain}"
    bash <(wget -qO- https://github.com/233boy/Xray/raw/main/install.sh) || exit 1
    sleep 5
fi

gen_uuid() {
    if ! command -v uuidgen >/dev/null 2>&1; then
        echo -e "${yellow}安装 uuidgen...${plain}"
        apt update -qq && apt install -y uuid-runtime
    fi
    uuidgen
}

gen_shortid() {
    local sid=$(openssl rand -hex 8)
    while [[ ! $sid =~ ^[0-9a-fA-F]{16}$ ]]; do
        sid=$(openssl rand -hex 8)
    done
    echo "$sid"
}

view_configs() {
    echo -e "\n${green}${bold}===== 查看已配置节点信息 =====${plain}\n"

    # 查找所有出口文件（按时间降序）
    local export_files=$(ls -t $CONF_DIR/VLESS-REALITY-EXPORT-*.json 2>/dev/null)
    if [[ -n "$export_files" ]]; then
        echo -e "${yellow}出口节点（EXPORT）：${plain}"
        for file in $export_files; do
            echo -e "\n${bold}文件: $file${plain}"
            jq -r '
            "端口: \(.inbounds[0].port)",
            "UUID: \(.inbounds[0].settings.clients[0].id)",
            "Short ID: \(.inbounds[0].streamSettings.realitySettings.shortIds[0])",
            "伪装网站: \(.inbounds[0].streamSettings.realitySettings.dest | split(":")[0])",
            "Public Key: \(.inbounds[0].streamSettings.realitySettings.publicKey)",
            "Private Key: \(.inbounds[0].streamSettings.realitySettings.privateKey)"
            ' "$file" 2>/dev/null || echo "无法解析该文件（格式异常）"
        done
    else
        echo "暂无出口节点配置"
    fi

    # 查找所有中转文件（按时间降序）
    local transit_files=$(ls -t $CONF_DIR/VLESS-REALITY-TRANSIT-*.json 2>/dev/null)
    if [[ -n "$transit_files" ]]; then
        echo -e "\n${yellow}中转节点（TRANSIT）：${plain}"
        for file in $transit_files; do
            echo -e "\n${bold}文件: $file${plain}"
            jq -r '
            "端口: \(.inbounds[0].port)",
            "UUID: \(.inbounds[0].settings.clients[0].id)",
            "Short ID: \(.inbounds[0].streamSettings.realitySettings.shortIds[0])",
            "伪装网站: \(.inbounds[0].streamSettings.realitySettings.dest | split(":")[0])",
            "Public Key: \(.inbounds[0].streamSettings.realitySettings.publicKey)",
            "Private Key: \(.inbounds[0].streamSettings.realitySettings.privateKey)",
            "出口IP: \(.outbounds[0].settings.vnext[0].address)",
            "出口端口: \(.outbounds[0].settings.vnext[0].port)"
            ' "$file" 2>/dev/null || echo "无法解析该文件（格式异常）"
        done
    else
        echo "暂无中转节点配置"
    fi

    echo -e "\n${yellow}查看原始文件命令：${plain}"
    echo "ls -lt $CONF_DIR/VLESS-REALITY-* | head -n 10"
    echo "cat $CONF_DIR/VLESS-REALITY-EXPORT-*.json   # 出口"
    echo "cat $CONF_DIR/VLESS-REALITY-TRANSIT-*.json   # 中转"
}

config_node() {
    local node_type="$1"
    local is_transit=0
    [[ "$node_type" == "中转" ]] && is_transit=1

    echo -e "\n${green}${bold}===== 开始配置 $node_type 节点 =====${plain}\n"

    local port
    if [[ $is_transit -eq 1 ]]; then
        port=$(($RANDOM % 40000 + 20000))
        read -p "中转端口 (默认 $port，推荐随机高位): " port_input && [[ -n "$port_input" ]] && port=$port_input
    else
        port=$(($RANDOM % 50000 + 10000))
        read -p "端口 (默认 $port): " port_input && [[ -n "$port_input" ]] && port=$port_input
    fi

    local uuid=$(gen_uuid)
    local short_id=$(gen_shortid)

    local dest
    read -p "伪装网站 (默认 www.microsoft.com): " dest && [[ -z "$dest" ]] && dest="www.microsoft.com"

    echo -e "${yellow}请手动输入 Reality keypair（推荐先运行 $XRAY_BIN x25519 获取）：${plain}"
    read -p "Private key (服务器用): " private_key
    read -p "Public key (客户端pbk用): " public_key

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        echo -e "${red}key 未输入，退出${plain}"
        exit 1
    fi

    local conf_file
    if [[ $is_transit -eq 1 ]]; then
        conf_file="$CONF_DIR/VLESS-REALITY-TRANSIT-$port.json"
    else
        conf_file="$CONF_DIR/VLESS-REALITY-EXPORT-$port.json"
    fi

    if [[ $is_transit -eq 1 ]]; then
        read -p "出口IP: " landing_ip
        read -p "出口端口: " landing_port
        read -p "出口UUID: " landing_uuid
        read -p "出口Public Key: " landing_pubkey
        read -p "出口Short ID: " landing_shortid

        cat > "$conf_file" <<EOF
{
  "inbounds": [{
    "port": $port,
    "protocol": "vless",
    "settings": {"clients": [{"id": "$uuid", "flow": ""}], "decryption": "none"},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "$dest:443", "serverNames": ["$dest"], "privateKey": "$private_key", "publicKey": "$public_key", "shortIds": ["$short_id"]}},
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
    else
        cat > "$conf_file" <<EOF
{
  "inbounds": [{
    "port": $port,
    "protocol": "vless",
    "settings": {"clients": [{"id": "$uuid", "flow": ""}], "decryption": "none"},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"dest": "$dest:443", "serverNames": ["$dest"], "privateKey": "$private_key", "publicKey": "$public_key", "shortIds": ["$short_id"]}},
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
    fi

    local server_ip=$(curl -s ifconfig.me || echo "你的服务器IP")
    local vless_link="vless://$uuid@$server_ip:$port?encryption=none&security=reality&pbk=$public_key&fp=chrome&type=tcp&sni=$dest&sid=$short_id#${node_type}节点"

    echo -e "\n${green}${bold}===== $node_type 节点配置完成 =====${plain}\n"
    echo -e "${yellow}基本信息：${plain}"
    echo "  UUID          : $uuid"
    echo "  Short ID      : $short_id"
    echo "  端口          : $port"
    echo "  伪装网站      : $dest"
    echo "  Private Key   : $private_key"
    echo "  Public Key    : $public_key"

    echo -e "\n${green}完整 vless 链接（直接复制导入客户端）：${plain}"
    echo -e "${bold}$vless_link${plain}"

    echo -e "\n${yellow}防火墙提示（如果未开端口，请执行）：${plain}"
    echo "ufw allow $port/tcp || iptables -A INPUT -p tcp --dport $port -j ACCEPT && iptables-save > /etc/iptables.rules"

    echo -e "\n${yellow}查看配置信息命令：${plain}"
    echo "ls -lt $CONF_DIR/VLESS-REALITY-* | head -n 10"
    echo "cat $conf_file   # 查看完整配置文件"

    systemctl restart xray || $XRAY_BIN restart
}

show_menu() {
    echo -e "\n${green}${bold}233boy Xray 集群脚本${plain}\n"
    echo "1. 配置出口节点"
    echo "2. 配置中转节点"
    echo "3. 查看已配置节点信息"
    echo "4. 退出"
    read -p "选择: " choice

    case $choice in
        1) config_node "出口" ;;
        2) config_node "中转" ;;
        3) view_configs ;;
        4) exit 0 ;;
        *) echo "无效选择" ;;
    esac

    # 循环菜单
    show_menu
}

show_menu
