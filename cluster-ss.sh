#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
bold='\033[1m'

[[ $EUID -ne 0 ]] && echo -e "${red}${bold}错误：必须root运行！${plain}" && exit 1

# 检查系统是否 CentOS 9 / RHEL 9 系
if ! grep -q "release 9" /etc/redhat-release 2>/dev/null; then
    echo -e "${red}此脚本专为 CentOS 9 / AlmaLinux 9 / Rocky 9 设计，你的系统不是，请先重装 CentOS Stream 9${plain}"
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
        echo -e "${green}自动设置永久别名 '$alias_name'...${plain}"
        echo "bash <(curl -Ls $script_url)" > "$alias_file"
        chmod +x "$alias_file"
        echo -e "${green}设置成功！以后直接输入 '$alias_name' 启动${plain}"
    fi
}

setup_alias

install_dependencies() {
    echo -e "${green}安装编译依赖...${plain}"
    dnf install -y epel-release dnf-plugins-core
    dnf config-manager --set-enabled crb
    dnf groupinstall -y "Development Tools"
    dnf install -y git gcc make cmake autoconf libtool libev-devel libsodium-devel mbedtls-devel pcre-devel c-ares-devel libxml2-devel libevent-devel zlib-devel openssl-devel pwgen
}

compile_ss_libev() {
    if [[ ! -f "$SS_BIN" ]]; then
        echo -e "${green}编译 shadowsocks-libev...${plain}"
        git clone https://github.com/shadowsocks/shadowsocks-libev.git /tmp/ss-libev || exit 1
        cd /tmp/ss-libev || exit 1
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
        git clone https://github.com/shadowsocks/simple-obfs.git /tmp/simple-obfs || exit 1
        cd /tmp/simple-obfs || exit 1
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
    echo "查看配置: cat $SS_CONF"
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

    # iptables 透明转发（CentOS 9 用 iptables-legacy）
    iptables -t nat -A PREROUTING -p tcp --dport $port -j REDIRECT --to-ports 1080
    iptables -t nat -A PREROUTING -p udp --dport $port -j REDIRECT --to-ports 1080
    iptables-save > /etc/iptables.rules

    local server_ip=$(curl -s ifconfig.me || echo "你的中转IP")
    echo -e "\n${green}中转节点完成！${plain}"
    echo "中转端口: $port"
    echo "密码: $export_password"
    echo "加密: aes-128-gcm"
    echo "客户端 SS 链接: ss://aes-128-gcm:$export_password@$server_ip:$port#中转节点"
    echo "查看配置: cat $SS_CONF"
}

view_config() {
    echo -e "\n${green}${bold}===== 查看当前配置 =====${plain}\n"
    if [[ -f $SS_CONF ]]; then
        cat $SS_CONF
    else
        echo "暂无配置"
    fi
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
