#!/usr/bin/sh

var_access_key_id="your aliyun access_key_id"
var_access_key_secret="your aliyun access_key_secret"
var_root_domain="your root_domain: example.com"
var_sub_domain="your sub_domain: sub.example.com"
var_sub_ip="sub_domain ip"

var_aliyun_ddns_api_host="https://alidns.aliyuncs.com"


#当前时间 格式：2020-03-12 14:36:31
NOW_DATE=$(date "+%Y-%m-%d %H:%M:%S")

#定义字体颜色
color_black_start="\033[30m"
color_red_start="\033[31m"
color_green_start="\033[32m"
color_yellow_start="\033[33m"
color_blue_start="\033[34m"
color_purple_start="\033[35m"
color_sky_blue_start="\033[36m"
color_white_start="\033[37m"
color_end="\033[0m"

#提示信息级别定义
message_info_tag="${color_sky_blue_start}[Info]    ${NOW_DATE} ${color_end}"
message_warning_tag="${color_yellow_start}[Warning] ${NOW_DATE} ${color_end}"
message_error_tag="${color_red_start}[Error]   ${NOW_DATE} ${color_end}"
message_success_tag="${color_green_start}[Success] ${NOW_DATE} ${color_end}"
message_fail_tag="${color_red_start}[Failed]  ${NOW_DATE} ${color_end}"


#操作系统发行名常量
MAC_OS_RELEASE="Darwin"
CENT_OS_RELEASE="centos"
UBUNTU_OS_RELEASE="ubuntu"
DEBIAN_OS_RELEASE="debian"

#是否root权限执行
var_is_root_execute=false
#是否支持sudo执行
var_is_support_sudo=false
#是否已安装curl组件
var_is_installed_curl=false
var_is_installed_jq=false
#是否已安装openssl组件
var_is_installed_openssl=false
#是否已安装nslookup组件
var_is_installed_nslookup=false

# 添加子域名
function AddSubDomain() {
    local query_url="DomainName=$var_sub_domain"
    fun_send_request "GET" "AddDomain" ${query_url} true
}

# 添加子域名解析记录
function AddSubDomainRecord() {
    
    # *@号需url编码两次
    local RR=$(fun_get_url_encryption "@")
    local query_url="DomainName=$var_sub_domain&Type=A&RR=$RR&Value=$var_sub_ip"
    fun_send_request "GET" "AddDomainRecord" ${query_url} true

    local RR=$(fun_get_url_encryption "*")
    local query_url="DomainName=$var_sub_domain&Type=A&RR=$RR&Value=$var_sub_ip"
    fun_send_request "GET" "AddDomainRecord" ${query_url} true

    local RR="www"
    local query_url="DomainName=$var_sub_domain&Type=A&RR=$RR&Value=$var_sub_ip"
    fun_send_request "GET" "AddDomainRecord" ${query_url} true
}

# 添加域名解析记录值
function AddRootDomainRecord() {
    local Value=`echo "$1" | jq -r '.Value'`
    local RR=`echo "$1" | jq -r '.RR'`
    local DomainName=`echo "$1" | jq -r '.DomainName'`
    local query_url="DomainName=$DomainName&Type=TXT&RR=$RR&Value=$Value"
    echo "query_url: $query_url"
    fun_send_request "GET" "AddDomainRecord" ${query_url} true
}

# 查询域名解析记录值请求
function GetTxtRecordForVerify() {
    local query_url="DomainName=$var_sub_domain&Type=ADD_SUB_DOMAIN"
    fun_send_request "GET" "GetTxtRecordForVerify" ${query_url} true
}

# 生成uuid
function fun_get_uuid(){
    echo $(uuidgen | tr '[A-Z]' '[a-z]')
}

# 获取当前时间戳
function fun_get_now_timestamp(){
    var_now_timestamp=`date -u "+%Y-%m-%dT%H%%3A%M%%3A%SZ"`
    #var_now_timestamp=`date -u "+%Y-%m-%dT%H:%M:%SZ"`
}

# 参数字母表排序
function sort_params(){
    local newargs=$(echo $1 | sed -e "s/&/ /g" | xargs -n1 | sort | xargs) 
    echo $(echo $newargs | sed -e "s/ /\&/g")
}


# 发送请求 eg:fun_send_request "GET" "Action" "动态请求参数（看说明）" "控制是否打印请求响应信息：true false"
fun_send_request() {
    local args="AccessKeyId=$var_access_key_id&Action=$2&$3&Timestamp=$var_now_timestamp&SignatureNonce=$(fun_get_uuid)&Version=2015-01-09&Format=json&SignatureMethod=HMAC-SHA1&SignatureVersion=1.0"

    local newargs=$(sort_params "$args")
    local message="$1&$(fun_get_url_encryption "/")&$(fun_get_url_encryption "$newargs")"
    local key="$var_access_key_secret&"
    local string_to_sign=$(get_signature "sha1" "$message" "$key")
    local signature=$(fun_get_url_encryption "$string_to_sign")

    local request_url="$var_aliyun_ddns_api_host/?$args&Signature=$signature"
    #local request_url="$var_aliyun_ddns_api_host/?$url_params"
    #echo "url: "$request_url
    local response=$(curl -s ${request_url})

    fun_wirte_log "${message_info_tag}阿里云$2接口请求返回信息:${response},接口:${request_url}" false

    local code=$(echo "$response" | jq ".Code")
    local message=$(echo "$response" | jq ".Message")


    if [[ $code = null ]]; then
        fun_wirte_log "${message_success_tag}阿里云$2接口请求处理成功,返回消息:${response}"
     else
        fun_wirte_log "${message_error_tag}阿里云$2接口请求处理失败,返回代码:${code}, 消息:${message}"
        exit 1
    fi
    # 获取RecordId时需要过滤出id值 需要打印请求响应信息
    if [[ "$4" != "" || "$4" = true ]]; then
        echo $response
    fi
}

# url编码
function fun_url_encode() {
    out=""
    while read -n1 c
    do
        case ${c} in
            [a-zA-Z0-9._-]) out="$out$c" ;;
            *) out="$out`printf '%%%02X' "'$c"`" ;;
        esac
    done
    echo -n ${out}
}

# url加密函数
function fun_get_url_encryption() {
    echo -n "$1" | fun_url_encode
}


#hmac-sha1 签名 usage: get_signature "签名算法" "加密串" "key"
function get_signature() {
    # echo -e "stringToSign: $2" >&2
    echo -ne "$2" | openssl dgst -$1 -hmac "$3" -binary | base64
}

# json转换函数 fun_parse_json "json" "key_name"
function fun_parse_json(){
    echo "${1//\"/}" | sed "s/.*$2:\([^,}]*\).*/\1/"
}


# 写日志到文件并显示 usage：fun_wirte_log "日志内容" “是否输出到console中：true（默认） false”
function fun_wirte_log(){
    #fun_setting_file_save_dir
    log_content="$1"
    if [[ "$2" = "" || "$2" = true ]]; then
        echo -e "$log_content" >&2
    fi
    # 处理样式 todo
    #echo "${log_content}" >> ${LOG_FILE_PATH}
}

# 检测root权限
function fun_check_root(){
    if [[ "`id -u`" != "0" ]]; then
        var_is_root_execute=false
    else
        var_is_root_execute=true
    fi
}

# 检测运行环境
function fun_check_run_environment(){
    if [[ -f "/usr/bin/sudo" ]]; then
        var_is_support_sudo=true
    else
        var_is_support_sudo=false
    fi
    if [[ -f "/usr/bin/curl" ]]; then
        var_is_installed_curl=true
    else
        var_is_installed_curl=false
    fi
    if [[ -f "/usr/bin/jq" ]]; then
        var_is_installed_jq=true
    else
        var_is_installed_jq=false
    fi
    if [[ -f "/usr/bin/openssl" ]]; then
        var_is_installed_openssl=true
    else
        var_is_installed_openssl=false
    fi
    if [[ -f "/usr/bin/nslookup" ]]; then
        var_is_installed_nslookup=true
    else
        var_is_installed_nslookup=false
    fi
    if [ -f "/etc/redhat-release" ]; then
        var_os_release="centos"
    elif [ -f "/etc/lsb-release" ]; then
        var_os_release="ubuntu"
    elif [ -f "/etc/debian_version" ]; then
        var_os_release="debian"
    fi
}


# 安装运行必需组件
function fun_install_run_environment(){
    if [[ ${var_is_installed_curl} = false ]] || [[ ${var_is_installed_jq} = false ]] || [[ ${var_is_installed_openssl} = false ]] || [[ ${var_is_installed_nslookup} = false ]]; then
        fun_wirte_log "${message_warning_tag}检测到缺少运行必需组件,正在尝试安装......"
        # 有root权限
        if [[ "${var_is_root_execute}" = true ]]; then
            if [[ "${var_os_release}" = "${CENT_OS_RELEASE}" ]]; then
                fun_wirte_log "${message_info_tag}检测到当前系统发行版本为:${CENT_OS_RELEASE}"
                fun_wirte_log "${message_info_tag}正在安装必需组件......"
                yum install -y curl openssl bind-utils jq
            elif [[ "${var_os_release}" = "${UBUNTU_OS_RELEASE}" ]];then
                fun_wirte_log "${message_info_tag}检测到当前系统发行版本为:${UBUNTU_OS_RELEASE}"
                fun_wirte_log "${message_info_tag}正在安装必需组件......"
                apt-get install curl openssl bind-utils -y
            elif [[ "${var_os_release}" = "${DEBIAN_OS_RELEASE}" ]]; then
                fun_wirte_log "${message_info_tag}检测到当前系统发行版本为:${DEBIAN_OS_RELEASE}"
                fun_wirte_log "${message_info_tag}正在安装必需组件......"
                apt-get install curl openssl bind-utils -y
            else
                fun_wirte_log "${message_warning_tag}当前系统是:${var_os_release},不支持自动安装必需组件,建议手动安装【curl、openssl、bind-utils、jq】"
            fi
            if [[ -f "/usr/bin/curl" ]]; then
                var_is_installed_curl=true
            else
                var_is_installed_curl=false
                fun_wirte_log "${message_error_tag}curl组件自动安装失败!可能会影响到程序运行,建议手动安装!"
            fi
            if [[ -f "/usr/bin/jq" ]]; then
                var_is_installed_jq=true
            else
                var_is_installed_jq=false
                fun_wirte_log "${message_error_tag}jq组件自动安装失败!可能会影响到程序运行,建议手动安装!"
            fi
            if [[ -f "/usr/bin/openssl" ]]; then
                var_is_installed_openssl=true
            else
                var_is_installed_openssl=false
                fun_wirte_log "${message_error_tag}openssl组件自动安装失败!可能会影响到程序运行,建议手动安装!"
            fi
            if [[ -f "/usr/bin/nslookup" ]]; then
                var_is_installed_nslookup=true
            else
                var_is_installed_nslookup=false
                fun_wirte_log "${message_error_tag}nslokkup组件自动安装失败!可能会影响到程序运行,建议手动安装!"
            fi
        elif [[ -f "/usr/bin/sudo" ]]; then
            fun_wirte_log "${message_warning_tag}当前脚本未以root权限执行,正在尝试以sudo命令安装必需组件......"
           if [[ "${var_os_release}" = "${CENT_OS_RELEASE}" ]]; then
                fun_wirte_log "${message_info_tag}检测到当前系统发行版本为:${CENT_OS_RELEASE}"
                fun_wirte_log "${message_info_tag}正在以sudo安装必需组件......"
                sudo yum install curl openssl bind-utils -y
                elif [[ "${var_os_release}" = "${UBUNTU_OS_RELEASE}" ]];then
                fun_wirte_log "${message_info_tag}检测到当前系统发行版本为:${UBUNTU_OS_RELEASE}"
                fun_wirte_log "${message_info_tag}正在以sudo安装必需组件......"
                sudo apt-get install curl openssl bind-utils -y
                elif ["${var_os_release}" = "${DEBIAN_OS_RELEASE}" ]; then
                fun_wirte_log "${message_info_tag}检测到当前系统发行版本为:${DEBIAN_OS_RELEASE}"
                fun_wirte_log "${message_info_tag}正在以sudo安装必需组件......"
                sudo apt-get install curl openssl bind-utils -y
            else
                fun_wirte_log "${message_warning_tag}当前系统是:${var_os_release},不支持自动安装必需组件,建议手动安装【curl、openssl、bind-utils】"
            fi
        else
            fun_wirte_log "${message_error_tag}系统缺少必需组件且无法自动安装,建议手动安装."
        fi
    fi
}

# 获取域名解析记录Id正则
function fun_get_value_regx() {
    grep -Eo '"Value":".+"' | cut -d':' -f2 | tr -d '"'
}

function fun_check_result() {
    local code=$(echo "$1" | jq ".Code")
    if [[ $code != null ]]; then
        return 1
    fi
    return 0
}


# 主入口 仅运行
function main_run(){
    fun_check_root
    fun_check_run_environment
    fun_install_run_environment
    fun_get_now_timestamp
    result=`GetTxtRecordForVerify`
    fun_check_result $result
    [ $? = 0 ] && AddRootDomainRecord "$result"
    echo "Wait 8 seconds for check Verify"
    sleep 8s
    AddSubDomain
    sleep 3s
    AddSubDomainRecord
    ping -c 3 $var_sub_domain
    exit 0
}

main_run


# https://nixers.net/Thread-Function-return-string-in-a-shell-script
# STDIN (0): Standard input. Unless told otherwise, most programs read from this channel.
# STDOUT (1): Standard output. That's where regular output ends up.
# STDERR (2): Standard error. This channel is meant for error messages or diagnostics.