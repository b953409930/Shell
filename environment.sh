#!/bin/bash
#  * Author        : Bai Jie
#  * Email         : b953409930@126.com
#  * Last modified : 2022-04-12 
#  * Filename      : test_environment.sh
#  * Description   : 系统测试/对顶测试，snms_1.3.5版本，备份mysql，配置测试epp信息，还原环境,登录mysql，登录mongo,查询统计数据

docker_compose_yml_bak_name=online
date=$(date +%Y%m%d)
function yellow_echo () {
        local what=$*
        echo -e "\e[1;33m ${what} \e[0m"
}

function green_echo () {
        local what=$*
        echo -e "\e[1;32m ${what} \e[0m"
}

function red_echo () {
        local what=$*
        echo -e "\e[1;31m ${what} \e[0m"
}


function get_mysql_conf(){
    mysql --help &>/dev/null
    [ "$?" != 0 ] &&yum -y install mysql &>/dev/null &&[ "$?" != 0 ] && red_echo "安装mysql客户端失败 请检查服务器网络环境/yum源/DNS等信息"&&exit 1
    if [ -f /opt/snms/docker-compose.yml ];then
        mysql_db_user=$(awk '{if($1 ~ /MYSQL_USERNAME/){print $2;exit}}' /opt/snms/docker-compose.yml)
        mysql_db_password=$(awk '{if($1 ~ /MYSQL_PASSWORD/){print $2;exit}}' /opt/snms/docker-compose.yml)
        mysql_db_url=$(awk  -F "[:/]"  '/^[[:space:]]+MYSQL_URL/{print$6;exit}' /opt/snms/docker-compose.yml)
        mysql_db_port=$(awk  -F "[:/]"  '/^[[:space:]]+MYSQL_URL/{print$7;exit}' /opt/snms/docker-compose.yml)
        shsrs_host=$(awk  -F "[:( )]" '  /^[[:space:]]+IDIS_SECOND_API_URL/{print$(NF-1);exit}' /opt/snms/docker-compose.yml)
    elif [ -f /usr/local/shsrs/conf/hsrs.conf ];then
        mysql_db_url=$(awk '/^.*db_server_url/{print$NF}' /usr/local/shsrs/conf/hsrs.conf)
        mysql_db_user=$(awk '/^.*db_server_user/{print$NF}' /usr/local/shsrs/conf/hsrs.conf)
        mysql_db_password=$(awk '/^.*db_server_password/{print$NF}' /usr/local/shsrs/conf/hsrs.conf)
        mysql_db_port=$(awk '/^.*db_server_port/{print$NF}' /usr/local/shsrs/conf/hsrs.conf)
        shsrs_host=127.0.0.1
    else
        yellow_echo "\n当前节点不在snms服务器，无法读取数据库配置，请输入mysql相关配置或到snms服务器执行，【Ctrl+c】退出\n"  
        read -p "请输入mysql 地址:" mysql_db_url
        read -p "请输入mysql 用户:" mysql_db_user
        read -p "请输入mysql 端口:" mysql_db_port
        read -p "请输入mysql 密码 " mysql_db_password
#        echo $mysql_db_url $mysql_db_user $mysql_db_passowrd $mysql_db_port
    fi

}


function get_mongo_conf(){
    if [ -f /opt/snms/docker-compose.yml ];then    
    mongo_url=$(awk '/MONGODB_URL/{print$2;exit}' /opt/snms/docker-compose.yml)
    else
        yellow_echo "\n当前节点不在snms服务器，无法读取数据库配置，请到snms服务器执行\n" 
        return 1
    fi

    mongo_repo(){
    cat >/etc/yum.repos.d/mongo.repo <<EOF
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/4.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.0.asc
EOF
    }
    mongo --help&>/dev/null
    [ "$?" != 0  ] && yellow_echo "\n当前环境未发现mongo客户端，下载客户端中..."&&mongo_repo && yum clean all &>/dev/null   && yum makecache&>/dev/null &&yum -y install mongodb-org&>/dev/null &&systemctl disable mongod &>/dev/null &&green_echo "mongo客户端下载成功，登录中..."
    mongo --help &>/dev/null
    [ "$?" != 0  ] && yellow_echo "\n安装mongo失败,请检查服务器是否可以访问外网,DNS是否配置正确" && return 0 


    
}

function backup_mysql(){

    get_mysql_conf

    if  ! [ -d ${date}_bak ];then
        mkdir -p ${date}_bak
        mysqldump -u${mysql_db_user} -h${mysql_db_url} -p${mysql_db_password} -P${mysql_db_port} snms> ${date}_bak/snms_${date}.sql
        size=$(du -sh ${date}_bak/snms_${date}.sql|awk '{print$1}')
        [ "${size}" == "0"  ] && red_echo "\n备份失败，数据库账号无权限备份;或数据库连接异常\n" && rm -rf ${date}_bak &&return 1 || green_echo "\n数据库备份成功在当前目录下的./${date}_bak内"
    else
        size=$(du -sh ${date}_bak/snms_${date}.sql|awk '{print$1}')
        if [ "${size}" != "0" ];then
            yellow_echo "\n该日数据已备份，请勿重复执行将会覆盖备份"
        else
            rm -rf ./${date}_bak&&red_echo "\n备份失败，数据库账号无权限备份;或数据库连接异常" && return 1
        fi
    fi

}

function set_test_epp(){
    date=$(date +%Y%m%d)
    if [ -f /opt/snms/docker-compose.yml ];then
        grep "1.3.5" /opt/snms/docker-compose.yml &>/dev/null
        if [ ! "$?" == "0" ];then
            red_echo  "\n当前snms版本不是1.3.5,不适用此脚本\n" && return 1
        fi
    else
        yellow_echo   "\n当前节点不存在/opt/snms/docker-compose.yml，请在snms服务器执行脚本\n" && return 1
    fi
    if [ $(ls *epp信息* 2>/dev/null |wc -l) -gt 0 ];then
        dos2unix --help&>/dev/null || yum -y install dos2unix &>/dev/null
        [ "$?" != "0" ] &&red_echo "安装dos2unix失败 请检查服务器网络环境/yum源/DNS等信息"&&exit 1
        epp_conf=$(ls *epp信息* |awk 'NR==1{print $NF}')
        #将上传的windos格式的epp信息.txt转化为linux格式
        dos2unix $epp_conf &>/dev/null
        epp_qz=$(awk -F "[:：]" 'BEGIN{IGNORECASE=1} /前缀/{gsub(/ /,"");print $NF}' "${epp_conf}") 
        epp_appid=$(awk -F "[:：]" 'BEGIN{IGNORECASE=1} /appid/{gsub(/ /,"");print $NF}' "${epp_conf}")
        epp_url="http://36.112.25.14:7002"
        epp_priv_pem=$(awk '{if($0 ~ /BEGIN PRIVATE KEY/){$1=$1;print;flag=!flag;next};if(flag){$1=$1;print};if($0 ~ /END/){flag=!flag;next} }' "${epp_conf}")
        echo -e "${epp_conf}\n${epp_qz}\n${epp_appid}\n${epp_url}\n${epp_priv_pem}"
    else 
        yellow_echo "\n请上传epp信息至当前目录"
        return 1
    fi
    ls /opt/snms/docker-compose.yml_${docker_compose_yml_bak_name}* &>/dev/null
  
    if [ $? == "0" ];then
        yellow_echo "\n当前已处于测试环境,无需配置epp信息"
        return 0
    else
        cp /opt/snms/docker-compose.yml{,_${docker_compose_yml_bak_name}_${date}_bak}
    fi
    #修改epp_url
    sed -i "/EPP_APPURL/s#[^ ]*\$#${epp_url}#"   /opt/snms/docker-compose.yml
    #修改epp_appid
    sed -i "/APPID/s#[^ ]*\$#${epp_appid}#"   /opt/snms/docker-compose.yml
    #修改epp前缀
    sed -i "/EPP_SHRPREFIX\b/s#[^ ]*\$#'${epp_qz}'#" /opt/snms/docker-compose.yml
    sed -i "/SELF_ENT_PREFIX/s#[^ ]*\$#'${epp_qz}.000000'#" /opt/snms/docker-compose.yml
    #开启模板
    sed -i  "/TEMPLATE/s#false#true#" /opt/snms/docker-compose.yml
    #修改epp私钥
    echo -e "${epp_priv_pem}" > 1.conf
    sed -i "s/^/                /" 1.conf
    sed -i "1i\            EPP_APPKEY: |-" 1.conf
    sed -i "/.*EPP_APPKEY: |-/,/.*-----END PRIVATE KEY-----/d" /opt/snms/docker-compose.yml
    sed -i "/            EPP_APPID*/r 1.conf" /opt/snms/docker-compose.yml
    rm -rf 1.conf
    yellow_echo "\n配置成功重启服务中..."
    cd /opt/snms  &&docker-compose down &&docker-compose up -d && cd -
    green_echo "\n配置测试epp信息成功"

}


function online_environment(){
    

    ls /opt/snms/docker-compose.yml_${docker_compose_yml_bak_name}_* &>/dev/null
    if [ "$?" != "0" ];then
        yellow_echo "\n未发现docker-compose.yml的备份文件，未处于测试环境无需恢复线上环境" && return 0
    else
        date_bak=$(ls /opt/snms/docker-compose.yml_online_* |awk  '{match($0,/[0-9]+/,arr);print arr[0]}')
        bak_file_name=$(ls /opt/snms/docker-compose.yml_online_*)
        ls -d ${date_bak}* &>/dev/null
        [ "$?" != "0" ] && yellow_echo "\n当前目录下未找到${date_bak}测试当天的备份" && echo "" &&read -p "是否只恢复线上epp信息，请输入y/n："  pattern
        if [ "$?" == "0" ];then
            if [[ "${pattern}" =~ y|Y|yes|是 ]];then
                green_echo  "\n恢复中....."
                \mv ${bak_file_name} /opt/snms/docker-compose.yml
                cd /opt/snms/&&docker-compose down&&docker-compose up -d && green_echo "\n恢复线上环境成功\n"
                return 1 
            else
                return 1
            fi
        fi
        get_mysql_conf
        mysqldump -u${mysql_db_user} -h${mysql_db_url} -p${mysql_db_password} -P${mysql_db_port} snms handle_count> handle_count_${date}.sql
        mysql -u${mysql_db_user} -h${mysql_db_url} -p${mysql_db_password} -P${mysql_db_port} snms < ${date_bak}_bak/snms_${date_bak}.sql
        mysql -u${mysql_db_user} -h${mysql_db_url} -p${mysql_db_password} -P${mysql_db_port} snms <  handle_count_${date}.sql  
        if [ "$?" == "0" ];then
            green_echo "\nmysql 还原线上数据成功\n"
            mode="true"
        else
            red_echo "\nmysql 异常还原线上数据上失败"
            return 1
        fi
        if [ "${mode}" == "true" ];then
            \mv ${bak_file_name} /opt/snms/docker-compose.yml
            cd /opt/snms/&&docker-compose down&&docker-compose up -d && green_echo "\n恢复线上环境成功\n" &&return 1
        else
            return 1
        fi
    fi

}

function login_to_mysql(){
    
    get_mysql_conf

    mysql -u"${mysql_db_user}" -h"${mysql_db_url}" -p"${mysql_db_password}" -P"${mysql_db_port}" 


}

function login_to_mongo(){
    
    get_mongo_conf
    eval mongo "${mongo_url}"

}

function request_count(){
    if [ -f /opt/snms/docker-compose.yml ];then    
        epp_qz=$(awk  -F"'" '/EPP_SHRPREFIX:/{print$(NF-1)}' /opt/snms/docker-compose.yml) 
        idmonitor_host=$(awk  -F'[:[:space:]]'  '/IDPOINT_API_URL:/{print$(NF-1)}' /opt/snms/docker-compose.yml)
    elif [ -f /opt/log-chart-job/docker-compose.yml ];then
        epp_qz=$(awk -F"[=,]" '/app.shr-prefix-list/{print$NF}' docker-compose.yml)
        idmonitor_host=127.0.0.1
    else
        yellow_echo "\n当前节点不在snms服务器，无法读取数据库配置，请到snms服务器执行\n" 
        return 1
    fi
    while true;
do
echo -e "\e[1;35m"
echo "---------------------------------------------"
echo -e "| \e[1;32m 请输入选项[0-3];q返回上一级;[Ctrl+c]退出 \e[1;35m|"
echo -e "---------------------------------------------"
cat <<EOF
(1)  查询所有统计量
(2)  查询当天统计量
(3)  按指定日期范围查询统计量
EOF
    echo -e "\e[0;0m"
    read -p "请输入[0-3]: " input1
    case "$input1" in
    q)
    return 0
    ;;
    1)
    start_date="2018-01-01"
    end_date="$(date "+%F")"
    curl -H "Content-Type: application/json" -X POST -d {'"from":"'${start_date}'","to":"'${end_date}'"'} "http://${idmonitor_host}:56566/traffic-record/${epp_qz}?type=date" | python -m json.tool
    ;;
    2)
    start_date="$(date "+%F")"
    end_date="$(date "+%F")"
    curl -H "Content-Type: application/json" -X POST -d {'"from":"'${start_date}'","to":"'${end_date}'"'} "http://${idmonitor_host}:56566/traffic-record/${epp_qz}?type=date" | python -m json.tool
    ;;
    3)
    break
    ;;
    *)
    echo "" 
    echo "" 
    yellow_echo "----------------------------------"
    yellow_echo "|            Warning             |"
    yellow_echo "|     请输入正确的选项[0-3]      |"
    yellow_echo "----------------------------------"
        sleep 1;
    esac
done
    [ -f /etc/init.d/functions ] && source /etc/init.d/functions || echo "函数库文件不存在！"
    function check_date(){
        read -p "请输入一个纯8位数字组成的日期(如20220101/2022-01-01/2022 01 01/2022.01.01)：" Date
        Date=${Date//[-[:space:]._]/""}
        if [[ ! $Date =~ ^[0-9]+$ ]];then
            action "日期不合法！请重新输入" /bin/false
            return 1
        fi
        if [ ${#Date} -ne 8 ];then
            action "日期不合法！请重新输入" /bin/false
            return 1
        fi
        Year=$(echo $Date |cut -c 1-4)
        Month=$(echo $Date |cut -c 5-6)
        Day=$(echo $Date |cut -c 7-8)
        if [ $Month -eq 1 ];then
            if [ $Day -gt 0 -a $Day -le 31 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        elif [ $Month -eq 2 ];then
            S=$(echo $Date |cut -c 3-4)
            if [ $S -eq 0 ];then
                #世纪年（xx00）需要被400整除才是闰年
                R=$(($Year % 400))
                if [ $R -eq 0 ];then
                    if [ $Day -gt 0 -a $Day -le 29 ];then
                        action "日期合法！" /bin/true
                    else
                        action "日期不合法！请重新输入" /bin/false
                    fi
                else
                    if [ $Day -gt 0 -a $Day -le 28 ];then
                        action "日期合法！" /bin/true
                    else
                        action "日期不合法！请重新输入" /bin/false
                    fi
                fi
            else
                #非世纪年只要能被4整除就是闰年
                N=$(($Year % 4))
                if [ $N -eq 0 ];then
                    if [ $Day -gt 0 -a $Day -le 29 ];then
                        action "日期合法！" /bin/true
                    else
                        action "日期不合法！请重新输入" /bin/false
                    fi
                else
                    if [ $Day -gt 0 -a $Day -le 28 ];then
                        action "日期合法！" /bin/true
                    else
                        action "日期不合法！请重新输入" /bin/false
                    fi
                fi
            fi
        elif [ $Month -eq 3 ];then
            if [ $Day -gt 0 -a $Day -le 31 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        elif [ $Month -eq 4 ];then
            if [ $Day -gt 0 -a $Day -le 30 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        elif [ $Month -eq 5 ];then
            if [ $Day -gt 0 -a $Day -le 31 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        elif [ $Month -eq 6 ];then
            if [ $Day -gt 0 -a $Day -le 30 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        elif [ $Month -eq 7 ];then
            if [ $Day -gt 0 -a $Day -le 31 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        elif [ $Month -eq 08 ];then
            if [ $Day -gt 0 -a $Day -le 31 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        elif [ $Month -eq 09 ];then
            if [ $Day -gt 0 -a $Day -le 30 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        elif [ $Month -eq 10 ];then
            if [ $Day -gt 0 -a $Day -le 31 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        elif [ $Month -eq 11 ];then
            if [ $Day -gt 0 -a $Day -le 30 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        elif [ $Month -eq 12 ];then
            if [ $Day -gt 0 -a $Day -le 31 ];then
                action "日期合法！" /bin/true
            else
                action "日期不合法！请重新输入" /bin/false
            fi
        else
            action "日期不合法！请重新输入" /bin/false
        fi
    #    echo $Date
    #   echo $?
    }
    declare -a arr_date
    function set_date(){
        for ((i=1;i<=2;i++))
        do  
            if [ $i == 1 ];then
                yellow_echo "\n请输入起始日期"
                check_date
            else
                yellow_echo "\n请输入终止日期"
                check_date
            fi
            if [ "$?" == "0" ];then
        #        arr_date[${#arr_date[*]}]=$Date
                arr_date+=("$Date")
            else
                let i=i-1
            fi
        done
    }
    set_date
    if [ "${arr_date[0]}" -gt "${arr_date[1]}" ];then
        yellow_echo "\n起始日期不能大于终止日期"
        set_date
    fi

    start_date=${arr_date[0]:0:4}-${arr_date[0]:4:2}-${arr_date[0]:6:2}
    end_date=${arr_date[1]:0:4}-${arr_date[1]:4:2}-${arr_date[1]:6:2}


    echo ""
    yellow_echo "\n${start_date}----------->${end_date}\n"
    curl -H "Content-Type: application/json" -X POST -d {'"from":"'${start_date}'","to":"'${end_date}'"'} "http://${idmonitor_host}:56566/traffic-record/${epp_qz}?type=date" | python -m json.tool
    request_count
}


while [ "$?" == "0" ];
do
echo -e "\e[1;35m"
echo "---------------------------------------------"
echo -e "|\e[1;32m           请输入选项[0-6];q退出           \e[1;35m|"
echo -e "---------------------------------------------"
cat <<EOF
(1)  备份mysql
(2)  配置测试环境epp信息
(3)  恢复线上环境
(4)  登录mysql
(5)  登录mongo
(6)  查询统计数据
EOF
echo -e "\e[0;0m"
 read -p "请输入[0-6]: " input
 case "$input" in
   q)
   break 
   ;;
   1)
   backup_mysql
   ;;
   2)
   set_test_epp
   ;;
   3)
   online_environment
   ;;
   4)
   login_to_mysql
   ;;
   5)
   login_to_mongo
   ;;
   6)
   request_count
   ;;
    *)
      echo "" 
      echo "" 
      yellow_echo "----------------------------------"
      yellow_echo "|            Warning             |"
      yellow_echo "|     请输入正确的选项[0-6]      |"
      yellow_echo "----------------------------------"
          sleep 1;
 esac
done