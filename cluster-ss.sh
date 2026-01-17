#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
bold='\033[1m'

[[ $EUID -ne 0 ]] && echo -e "${red}${bold}错误：必须root运行！${plain}" && exit 1

SS_CONF="/etc/shadowsocks-libev/config.json"
OBFS_PLUGIN="/usr/bin/simple-obfs-server"

setup_alias() {
    local alias_name="ssobfs"
    local script_url="https://raw.githubusercontent.com/9tyone91/xray-cluster-script/main/cluster-ss-obfs.sh"
    local alias_file="/usr/local/bin/$alias_name"

    if [[ ! -f "$alias_file" ]]; then
        echo -e "${green}自动设置永久别名 '$alias_name'...${plain}"
        echo "bash <(curl -Ls $script_url)" > "$alias_file"
        chmod +x "$alias_file"
        echo -e "${green}设置成功！以后直接输入 '$alias_name' 启动${plain}"
    fi
}

setup_alias

install_ss_obfs() {
    if ! command -v ss-server >/dev/null 2>&1; then
        apt update -qq && apt install -y shadowsocks-libev
    fi
    if ! command -v simple-obfs-server >/dev/null 2>&1; then
        apt install -y simple-obfs
    fi
}

config_export() {
    echo -e "\n${green}${bold}===== 配置出口节点 (SS + obfs) =====${plain}\n"
    local port=$(($RANDOM % 40000 + 20000))
    read -p "出口端口 (默认 $port): " port_input && [[ -n "$port_input" ]] && port=$port_input
    local password=$(openssl rand -hex 8)
    read -p "密码 (默认 $password): " pass_input && [[ -n "$pass_input" ]] && password=$pass_input

    ufw allow $port/tcp || iptables -A INPUT -p tcp --dport $port -j ACCEPT && iptables-save > /etc/iptables.rules

    cat > $SS_CONF <<EOF
{
  "server": "0.0.0.0",
  "server_port": $port,
  "password": "$password",
  "method": "aes-128-gcm",
  "plugin": "simple-obfs-server",
  "plugin_opts": "obfs=http",
  "mode": "tcp_and_udp",
  "fast_open": true
}
EOF

    killall ss-server 2>/dev/null
    ss-server -c $SS_CONF -d start

    echo -e "\n${green}出口节点完成！${plain}"
    echo "端口: $port"
    echo "密码: $password"
    echo "加密: aes-128-gcm"
    echo "混淆: http"
    echo "查看: cat $SS_CONF"
}

config_transit() {
    echo -e "\n${green}${bold}===== 配置中转节点 (SS + obfs) =====${plain}\n"
    read -p "出口IP: " export_ip
    read -p "出口端口: " export_port
    read -p "出口密码: " export_password

    local port=$(($RANDOM % 40000 + 20000))
    read -p "中转端口 (默认 $port): " port_input && [[ -n "$port_input" ]] && port=$port_input

    ufw allow $port/tcp || iptables -A INPUT -p tcp --dport $port -j ACCEPT && iptables-save > /etc/iptables.rules

    cat > $SS_CONF <<EOF
{
  "server": "0.0.0.0",
  "server_port": $port,
  "password": "$export_password",
  "method": "aes-128-gcm",
  "plugin": "simple-obfs-server",
  "plugin_opts": "obfs=http",
  "mode": "tcp_and_udp",
  "fast_open": true
}
EOF

    killall ss-server 2>/dev/null
    ss-server -c $SS_CONF -d start

    local server_ip=$(curl -s ifconfig.me || echo "你的中转IP")
    echo -e "\n${green}中转节点完成！${plain}"
    echo "中转端口: $port"
    echo "密码: $export_password (同出口)"
    echo "加密: aes-128-gcm"
    echo "混淆: http"
    echo "客户端 SS 链接: ss://aes-128-gcm:$export_password@$server_ip:$port?plugin=simple-obfs;obfs=http#中转节点"
    echo "查看: cat $SS_CONF"
}

view_config() {
    echo -e "\n${green}${bold}===== 查看当前配置 =====${plain}\n"
    if [[ -f $SS_CONF ]]; then
        cat $SS_CONF
    else
        echo "暂无配置"
    fi
}

echo -e "\n${green}${bold}Shadowsocks + obfs 集群脚本${plain}\n"
echo "1. 配置出口节点"
echo "2. 配置中转节点"
echo "3. 查看当前配置"
echo "4. 退出"
read -p "选择: " choice

case $choice in
    1) install_ss_obfs; config_export ;;
    2) install_ss_obfs; config_transit ;;
    3) view_config ;;
    4) exit 0 ;;
    *) echo "无效选择" ;;
esac

echo -e "\n${green}操作完成！${plain}"
echo "服务状态: ss-server -c $SS_CONF -d status"
