#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}必须root运行！${plain}" && exit 1

install_ss() {
    apt update && apt install shadowsocks-libev -y
}

config_export() {
    echo -e "${green}配置出口节点${plain}"
    read -p "端口 (默认 18564): " port && [[ -z "$port" ]] && port=18564
    read -p "密码 (默认 random): " password && [[ -z "$password" ]] && password=$(openssl rand -hex 8)
    ufw allow $port/tcp || iptables -A INPUT -p tcp --dport $port -j ACCEPT
    cat > /etc/shadowsocks-libev/config.json <<EOF
{
  "server":"0.0.0.0",
  "server_port":$port,
  "password":"$password",
  "method":"aes-256-gcm",
  "mode": "tcp_and_udp"
}
EOF
    ss-server -c /etc/shadowsocks-libev/config.json -d start
    echo -e "${green}出口节点完成！端口: $port, 密码: $password${plain}"
}

config_transit() {
    echo -e "${green}配置中转节点${plain}"
    read -p "出口IP: " export_ip
    read -p "出口端口: " export_port
    read -p "出口密码: " export_password
    read -p "中转端口 (默认 50000): " port && [[ -z "$port" ]] && port=50000
    ufw allow $port/tcp || iptables -A INPUT -p tcp --dport $port -j ACCEPT
    cat > /etc/shadowsocks-libev/config.json <<EOF
{
  "server":"0.0.0.0",
  "server_port":$port,
  "password":"$export_password",
  "method":"aes-256-gcm",
  "mode": "tcp_and_udp",
  "plugin":"ss-local",
  "plugin_opts": "server;$export_ip:$export_port;password=$export_password"
}
EOF
    ss-server -c /etc/shadowsocks-libev/config.json -d start
    echo -e "${green}中转节点完成！端口: $port, 密码: $export_password${plain}"
    echo -e "${yellow}客户端 SS 链接: ss://aes-256-gcm:$export_password@你的中转IP:$port#中转节点${plain}"
}

echo -e "${yellow}Shadowsocks 集群脚本${plain}"
echo "1. 配置出口节点"
echo "2. 配置中转节点"
echo "3. 退出"
read -p "选择: " choice

case $choice in
    1) install_ss; config_export ;;
    2) install_ss; config_transit ;;
    3) exit 0 ;;
    *) echo "无效选择" ;;
esac

echo -e "${green}完成！服务已启动。${plain}"
echo "检查: ss-server -c /etc/shadowsocks-libev/config.json -d status"
