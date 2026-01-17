#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
bold='\033[1m'

[[ $EUID -ne 0 ]] && echo -e "${red}${bold}错误：必须root运行！${plain}" && exit 1

# 检查系统
if ! grep -q "release 9" /etc/redhat-release 2>/dev/null; then
    echo -e "${red}此脚本专为 CentOS 9 / AlmaLinux 9 / Rocky 9 设计${plain}"
    exit 1
fi

SS_CONF="/etc/shadowsocks-libev/config.json"
SS_BIN="/usr/local/bin/ss-server"
REDIR_BIN="/usr/local/bin/ss-redir"
OBFS_BIN="/usr/local/bin/simple-obfs-server"

# 自动设置别名
setup_alias() {
    local alias_name="ssjiqun"
    local script_url="https://raw.githubusercontent.com/9tyone91/xray-cluster-script/main/cluster-ss.sh"
    local alias_file="/usr/local/bin/$alias_name"

    if [[ ! -f "$alias_file" ]]; then
        echo -e "${green}设置别名 '$alias_name'...${plain}"
        echo "bash <(curl -Ls $script_url)" > "$alias_file"
        chmod +x "$alias_file"
    fi
}

setup_alias

install_all_dependencies() {
    echo -e "${green}安装所有编译依赖...${plain}"
    dnf update -y
    dnf install -y epel-release dnf-plugins-core
    dnf config-manager --set-enabled crb
    dnf groupinstall -y "Development Tools" "C Development Tools and Libraries"
    dnf install -y git gcc gcc-c++ make cmake autoconf libtool pkgconfig libev-devel libsodium-devel mbedtls-devel pcre-devel c-ares-devel libxml2-devel libevent-devel zlib-devel openssl-devel pwgen xmlto libcap-devel libcurl-devel libjson-c-devel
}

compile_ss_libev() {
    if [[ ! -f "$SS_BIN" ]]; then
        echo -e "${green}编译 shadowsocks-libev...${plain}"
        git clone https://github.com/shadowsocks/shadowsocks-libev.git /tmp/ss-libev
        cd /tmp/ss-libev
        git submodule update --init --recursive
        ./autogen.sh
        ./configure --prefix=/usr/local --disable-documentation
        make -j$(nproc)
        make install
        cd ..
        rm -rf /tmp/ss-libev
    fi
}

compile_simple_obfs() {
    if [[ ! -f "$OBFS_BIN" ]]; then
        echo -e "${green}编译 simple-obfs...${plain}"
        git clone https://github.com/shadowsocks/simple-obfs.git /tmp/simple-obfs
        cd /tmp/simple-obfs
        git submodule update --init --recursive
        ./autogen.sh
        ./configure --prefix=/usr/local
        make -j$(nproc)
        make install
        cd ..
        rm -rf /tmp/simple-obfs
    fi
}

config_export() {
    echo -e "\n${green}${bold}===== 配置出口节点 =====${plain}\n"
    local port=$(($RANDOM % 40000 + 20000))
    read -p "出口端口 (默认 $port): " port_input && [[ -n "$port_input" ]] && port=$port_input
    local password=$(openssl rand -hex 8)
    read -p "密码 (默认 $password): " pass_input && [[ -n "$pass_input" ]] && password=$pass_input

    firewall-cmd --permanent --add-port=$port/tcp --add-port=$port/udp
    firewall-cmd --reload

    mkdir -p /etc/shadowsocks-libev
    cat > $SS_CONF <<EOF
{
  "server": "0.0.0.0",
  "server_port": $port,
  "password": "$password",
  "method": "aes-128-gcm",
  "mode": "tcp_and_udp",
  "fast_open": true,
  "reuse_port": true
}
EOF

    killall ss-server 2>/dev/null
    $SS_BIN -c $SS_CONF -d start

    echo -e "\n${green}出口节点完成！${plain}"
    echo "端口: $port"
    echo "密码: $password"
    echo "加密: aes-128-gcm"
}

config_transit() {
    echo -e "\n${green}${bold}===== 配置中转节点 =====${plain}\n"
    read -p "出口IP: " export_ip
    read -p "出口端口: " export_port
    read -p "出口密码: " export_password

    local port=$(($RANDOM % 40000 + 20000))
    read -p "中转端口 (默认 $port): " port_input && [[ -n "$port_input" ]] && port=$port_input

    firewall-cmd --permanent --add-port=$port/tcp --add-port=$port/udp
    firewall-cmd --reload

    mkdir -p /etc/shadowsocks-libev
    cat > $SS_CONF <<EOF
{
  "server": "0.0.0.0",
  "server_port": $port,
  "password": "$export_password",
  "method": "aes-128-gcm",
  "mode": "tcp_and_udp",
  "fast_open": true,
  "reuse_port": true
}
EOF

    killall ss-server 2>/dev/null
    killall ss-redir 2>/dev/null
    $SS_BIN -c $SS_CONF -d start
    $REDIR_BIN -c $SS_CONF -l 1080 -d start

    # nftables 透明转发
    nft add table ip nat
    nft add chain ip nat prerouting { type nat hook prerouting priority 0 \; }
    nft add rule ip nat prerouting tcp dport $port redirect to 1080
    nft add rule ip nat prerouting udp dport $port redirect to 1080

    local server_ip=$(curl -s ifconfig.me || echo "你的中转IP")
    echo -e "\n${green}中转节点完成！${plain}"
    echo "中转端口: $port"
    echo "密码: $export_password"
    echo "加密: aes-128-gcm"
    echo "客户端 SS 链接: ss://aes-128-gcm:$export_password@$server_ip:$port#中转节点"
}

view_config() {
    echo -e "\n${green}${bold}查看当前配置${plain}\n"
    cat $SS_CONF 2>/dev/null || echo "暂无配置"
}

echo -e "\n${green}${bold}Shadowsocks 集群脚本 (CentOS 9 专用版)${plain}\n"
echo "1. 配置出口节点"
echo "2. 配置中转节点"
echo "3. 查看当前配置"
echo "4. 退出"
read -p "选择: " choice

case $choice in
    1) install_dependencies; compile_ss_libev; compile_simple_obfs; config_export ;;
    2) install_dependencies; compile_ss_libev; compile_simple_obfs; config_transit ;;
    3) view_config ;;
    4) exit 0 ;;
    *) echo "无效选择" ;;
esac

echo -e "\n${green}操作完成！${plain}"
