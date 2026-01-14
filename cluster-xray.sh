#!/bin/bash

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}必须root运行！${plain}" && exit 1

# 步骤1: 安装或更新233boy Xray（如果已装，跳过安装但检查）
if ! command -v xray &> /dev/null; then
    echo -e "${green}安装233boy Xray...${plain}"
    bash <(wget -qO- https://github.com/233boy/Xray/raw/main/install.sh) || {
        echo -e "${red}安装失败！检查网络或手动安装。${plain}"
        exit 1
    }
else
    echo -e "${yellow}Xray已安装，跳过。${plain}"
fi

# 确定配置路径（兼容不同安装）
CONF_DIR=$(find /etc /usr/local/etc -type d -name "conf" -path "*/xray/conf" 2>/dev/null | head -1 || echo "/etc/xray/conf")
MAIN_CONF=$(find /etc /usr/local/etc -type f -name "config.json" -path "*/xray/config.json" 2>/dev/null | head -1 || echo "/etc/xray/config.json")

if [[ -z "$CONF_DIR" || -z "$MAIN_CONF" ]]; then
    echo -e "${red}未找到Xray配置路径！请确认安装。${plain}"
    exit 1
fi

# 工具函数（gen_uuid 等，从之前脚本复制）
gen_uuid() { uuidgen; }
gen_keypair() {
    keypair=$(xray x25519)
    private_key=$(echo "$keypair" | grep "Private" | awk '{print $3}')
    public_key=$(echo "$keypair" | grep "Public" | awk '{print $3}')
    echo "$private_key $public_key"
}
gen_shortid() { openssl rand -hex 8; }

# 配置出口节点（生成新json文件到conf/）
config_landing() {
    echo -e "${green}配置出口节点...${plain}"
    port=$(($RANDOM % 50000 + 10000))
    read -p "端口 (默认 $port): " input_port
    [[ ! -z "$input_port" ]] && port=$input_port

    uuid=$(gen_uuid)
    keypair=$(gen_keypair)
    private_key=$(echo $keypair | awk '{print $1}')
    public_key=$(echo $keypair | awk '{print $2}')
    short_id=$(gen_shortid)

    read -p "伪装网站 (默认 www.microsoft.com): " dest_domain
    [[ -z "$dest_domain" ]] && dest_domain="www.microsoft.com"

    conf_file="$CONF_DIR/VLESS-REALITY-$port.json"
    cat > "$conf_file" <<EOF
{
  "inbounds": [{
    "port": $port,
    "protocol": "vless",
    "settings": {"clients": [{"id": "$uuid", "flow": "xtls-rprx-vision"}], "decryption": "none"},
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {"dest": "$dest_domain:443", "serverNames": ["$dest_domain"], "privateKey": "$private_key", "publicKey": "$public_key", "shortIds": ["$short_id"]}
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
    echo -e "${green}出口配置完成！文件: $conf_file${plain}"
    echo "UUID: $uuid | Public Key: $public_key | Short ID: $short_id"
}

# 配置中转节点（类似，生成json）
config_transit() {
    echo -e "${green}配置中转节点...${plain}"
    read -p "出口IP: " landing_ip
    read -p "出口端口: " landing_port
    read -p "出口UUID: " landing_uuid
    read -p "出口Public Key: " landing_pubkey
    read -p "出口Short ID: " landing_shortid

    transit_port=443
    read -p "中转端口 (默认443): " input_port
    [[ ! -z "$input_port" ]] && transit_port=$input_port

    read -p "伪装网站 (默认 www.microsoft.com): " dest_domain
    [[ -z "$dest_domain" ]] && dest_domain="www.microsoft.com"

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
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {"dest": "$dest_domain:443", "serverNames": ["$dest_domain"], "privateKey": "$transit_private", "publicKey": "$transit_public", "shortIds": ["$transit_shortid"]}
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }],
  "outbounds": [{
    "tag": "to-landing",
    "protocol": "vless",
    "settings": {"vnext": [{"address": "$landing_ip", "port": $landing_port, "users": [{"id": "$landing_uuid", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {"dest": "$dest_domain:443", "serverNames": ["$dest_domain"], "privateKey": "$transit_private", "shortIds": ["$transit_shortid"]}
    }
  }],
  "routing": {"rules": [{"type": "field", "outboundTag": "to-landing", "network": "tcp,udp"}]}
}
EOF
    echo -e "${green}中转配置完成！文件: $conf_file${plain}"
    echo "UUID: $transit_uuid | Public Key: $transit_public | Short ID: $transit_shortid"
}

# 列表检查（从之前check脚本复制）
list_configs() {
    configs=($(ls "$CONF_DIR"/*.json 2>/dev/null))
    if [[ ${#configs[@]} -eq 0 ]]; then
        echo -e "${yellow}暂无配置！${plain}"
        return
    fi

    echo -e "${green}配置列表：${plain}"
    echo "序号 | 文件名 | 协议 | 端口 | 是否中转 | 出口IP"
    i=1
    for conf in "${configs[@]}"; do
        filename=$(basename "$conf")
        protocol=$(grep -oP '"protocol":\s*"\K[^"]+' "$conf" | head -1 || echo "-")
        port=$(grep -oP '"port":\s*\K\d+' "$conf" | head -1 || echo "-")
        has_relay=$(grep -q '"tag":\s*"to-landing"' "$conf" && echo "是" || echo "否")
        outbound_ip=$(grep -oP '"address":\s*"\K[^"]+' "$conf" | head -1 || echo "-")
        printf "%-4s | %-30s | %-8s | %-6s | %-8s | %s\n" "$i" "$filename" "$protocol" "$port" "$has_relay" "$outbound_ip"
        ((i++))
    done
}

# 主菜单（扩展233boy风格）
main_menu() {
    xray  # 先显示原233boy菜单
    echo -e "${yellow}=== 集群扩展菜单 ===${plain}"
    echo "11. 配置出口节点"
    echo "12. 配置中转节点"
    echo "13. 列表检查配置（relay）"
    echo "14. 查看日志摘要"
    echo "0. 退出"
    read -p "选择: " choice

    case $choice in
        11) config_landing; xray restart ;;
        12) config_transit; xray restart ;;
        13) list_configs ;;
        14) tail -n 20 /var/log/xray/error.log; echo ""; tail -n 10 /var/log/xray/access.log ;;
        0) exit 0 ;;
        *) echo "调用原xray命令..."; xray $choice ;;
    esac
    main_menu  # 循环
}

# 安装扩展：创建 /usr/local/bin/xray-cluster
cat > /usr/local/bin/xray-cluster <<EOF
#!/bin/bash
main_menu "\\\$@"
EOF
chmod +x /usr/local/bin/xray-cluster

echo -e "${green}整合完成！用 'xray-cluster' 命令管理（原菜单 + 集群扩展）。${plain}"
