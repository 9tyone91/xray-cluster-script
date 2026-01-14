#!/bin/bash

# 颜色
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}必须root运行！${plain}" && exit 1

echo -e "${yellow}混合脚本：先安装233boy Xray，再自动加集群relay配置${plain}"
echo "脚本会先跑官方233boy安装（https://github.com/233boy/Xray）"
echo "安装完后生成中转/出口 config（Reality模式）"
echo ""

# 步骤1: 安装233boy Xray
echo -e "${green}步骤1: 安装233boy Xray...${plain}"
bash <(wget -qO- https://github.com/233boy/Xray/raw/main/install.sh) || {
    echo -e "${red}233boy安装失败！请检查网络或手动安装。${plain}"
    exit 1
}

# 等待服务启动
sleep 5
systemctl restart xray

# 工具函数
gen_uuid() { uuidgen; }
gen_keypair() {
    keypair=$(xray x25519 2>/dev/null || /usr/local/bin/xray x25519)
    private_key=$(echo "$keypair" | grep "Private" | awk '{print $3}')
    public_key=$(echo "$keypair" | grep "Public" | awk '{print $3}')
    echo "$private_key $public_key"
}
gen_shortid() { openssl rand -hex 8; }

# 配置出口节点 config
config_landing() {
    echo -e "${green}配置为出口节点（统一出站IP）${plain}"
    port=$(($RANDOM % 50000 + 10000))
    read -p "出口端口 (默认随机 $port): " input_port
    [[ ! -z "$input_port" ]] && port=$input_port

    uuid=$(gen_uuid)
    keypair=$(gen_keypair)
    private_key=$(echo $keypair | awk '{print $1}')
    public_key=$(echo $keypair | awk '{print $2}')
    short_id=$(gen_shortid)

    read -p "伪装网站 (推荐 www.microsoft.com / www.apple.com): " dest_domain
    [[ -z "$dest_domain" ]] && dest_domain="www.microsoft.com"

    config_file="/etc/xray/conf/config.json"  # 233boy常用路径，或 /usr/local/etc/xray/config.json，根据你的安装调整
    [ ! -f "$config_file" ] && config_file="/usr/local/etc/xray/config.json"

    cp "$config_file" "${config_file}.bak.$(date +%s)"

    cat > "$config_file" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": $port,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$uuid", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$dest_domain:443",
          "serverNames": ["$dest_domain"],
          "privateKey": "$private_key",
          "publicKey": "$public_key",
          "shortIds": ["$short_id"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

    echo -e "${green}出口节点配置完成！${plain}"
    echo "端口: $port | UUID: $uuid | Public Key: $public_key | Short ID: $short_id"
    echo "伪装: $dest_domain"
}

# 配置中转节点 config
config_transit() {
    echo -e "${green}配置为中转节点（转发到出口）${plain}"
    read -p "出口节点 IP: " landing_ip
    read -p "出口节点端口: " landing_port
    read -p "出口节点 UUID: " landing_uuid
    read -p "出口节点 Public Key: " landing_pubkey
    read -p "出口节点 Short ID: " landing_shortid

    read -p "中转入口端口 (推荐443): " transit_port
    [[ -z "$transit_port" ]] && transit_port=443

    read -p "伪装网站 (建议与出口一致): " dest_domain
    [[ -z "$dest_domain" ]] && dest_domain="www.microsoft.com"

    transit_uuid=$(gen_uuid)
    keypair=$(gen_keypair)
    transit_private=$(echo $keypair | awk '{print $1}')
    transit_public=$(echo $keypair | awk '{print $2}')
    transit_shortid=$(gen_shortid)

    config_file="/etc/xray/conf/config.json"
    [ ! -f "$config_file" ] && config_file="/usr/local/etc/xray/config.json"

    cp "$config_file" "${config_file}.bak.$(date +%s)"

    cat > "$config_file" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": $transit_port,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$transit_uuid", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$dest_domain:443",
          "serverNames": ["$dest_domain"],
          "privateKey": "$transit_private",
          "publicKey": "$transit_public",
          "shortIds": ["$transit_shortid"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
  ],
  "outbounds": [
    {
      "tag": "to-landing",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$landing_ip",
            "port": $landing_port,
            "users": [{"id": "$landing_uuid", "flow": "xtls-rprx-vision", "encryption": "none"}]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$dest_domain:443",
          "serverNames": ["$dest_domain"],
          "privateKey": "$transit_private",
          "shortIds": ["$landing_shortid"]
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "outboundTag": "to-landing", "network": "tcp,udp"}
    ]
  }
}
EOF

    echo -e "${green}中转节点配置完成！${plain}"
    echo "入口端口: $transit_port | UUID: $transit_uuid | Public Key: $transit_public"
    echo "Short ID: $transit_shortid | 伪装: $dest_domain"
}

# 主菜单
echo -e "${yellow}请选择节点类型：${plain}"
echo "1. 配置为出口节点（统一出站）"
echo "2. 配置为中转节点（指向出口）"
echo "0. 只安装233boy，不改config"
read -p "输入数字: " choice

case $choice in
    1) config_landing ;;
    2) config_transit ;;
    0) echo "已完成233boy安装，无改动。" ;;
    *) echo "无效，选择默认不改。" ;;
esac

# 重启并提示
systemctl restart xray
echo -e "${green}全部完成！Xray已重启。${plain}"
echo "用 'xray' 命令管理（add/del/info/qr/url 等）"
echo "查看状态: systemctl status xray"
echo "日志: journalctl -u xray -f"
echo "如果config路径不对，手动检查 /etc/xray/conf/ 或 /usr/local/etc/xray/"
echo "测试连通后，客户端加多个中转节点即可（出口IP固定）"
