#!/bin/bash
ssh_remote_pasword=""
ssh_remote_port="1111"
ssh_remote_user="test"
ssh_remote_host="139"
ssh_pub="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLlgc1nlfXkXnVmO1MmhgYrbjznkjhamt5jSytFVpGqsYUVp/1e60G7qdytWktuVUDTjkZCtUX9d6BF1E8bzNtAjUY295SBbwp7dmzX4nfXAEB7SXnvYdbCbpmSpK26pWAGGsyNWq/IpnwSE7UvSQiJAobxmTIBVij4eReBQVmbH687A6+zLK8R5U4wbLT6lENSRnbhBrYCGy5QTcPt7mUg5lWHPzJhK8hj/qeaEPtngp2PiSKiZxY+72xlR44O1IrCv80YL1LkfqgXh8WCpyFDC8jMtygWWNcc2ZMjif/60iGJ9d/OtNEsH0R00p4W8WpVVPgiJLtjCN3vWDLjxnh root@es3"
local_port="22"

version=2.0
function usage(){
    cat  << EOF
    Usage: $0 [options] [parameter]
        --help           查看帮助手册
        -l,--local_port  指定要转发的本地端口,不写默认为本地22 ssh端口
        -r,--remote_port 指定转发到远程主机的哪个端口,不写,会从2000~65535随机生成一个端口
        -h,--host        指定远程主机的ip,不写默认xxxx 1111端口青云服务器的
        -p,--pasword     指定远程主机的密码,不写默认为xxxx 1111端口青云服务器的
        -p,--Port        指定远程主机的登录端口,不写默认为xxxx  1111端口青云服务器的
        -u,--user        指定远程主机的登录用户,不写默认为xxxx  1111端口青云服务器的
EOF
}

#生成指定范围随机数用于随机监听端口
function rand(){
  min=$1
  max=$(($2-$min+1))
  num=$(($RANDOM+1000000000))
  echo $(($num%$max+$min))
}


#设置选项
args=$(getopt  -n "$0"  -o l:h:vr:p:u:P:  -l local_port:,version,help,remote_port:,user:,password:,Port:    -- "$@"    )
#判断getopt解析是否报错，不正确退出不执行后面选项参数判断
[ $? != 0 ] && exit 1
#echo "args:$args"

#通过 set --  把 getopt 解析整理的选项、参数设置成bash的位置变量
eval set -- "$args"
while true;do
    case  "$1" in
        --help)
            usage
            shift
            exit 1
            ;;
        -v|--version)
            echo "${version}"
            exit 1
            ;;
        -l|--local_port)
            local_port=$2
            shift 2
            ;;
        -r|--remote_port)
            remote_port=$2
            shift 2
            ;;
        -u|--user)
            ssh_remote_user=$2
            shift 2
            ;;
        -p|--password)
            ssh_remote_pasword=$2
            shift 2
            ;;
        -P|--Port)
            ssh_remote_port=$2
            shift 2
            ;; 
        -h|--host)
            ssh_remote_host=$2
            shift 2
            ;;
        --)
            if [ -n "$2" ];then
                usage
                exit 1
            else
                mode=true
                break
            fi
            ;;                    
        *)
            usage
            exit 1 
    esac
done

#判断是否是在snms节点并且要转发的端口是否为ssh端口，如果上述条件满足则设置转发到远程服务器的端口为该二级前缀去掉.和第一位数8(端口必须小于65535)的数如88.186 -> 8186，并且设置密钥对登录，通过青云服务器ssh -p88186 127.0.0.1可以免密登录该服务器，并设置开机自动转发端口
ss -ntpl|grep "${local_port}\b" |grep sshd &>/dev/null
if [ "$?" == "0" ] | [ "$local_port" == "22" ];then
    if [ -f /opt/snms/docker-compose.yml ];then
        epp_qz=$(awk '/.*EPP_SHRPREFIX[=:]/{print}' /opt/snms/docker-compose.yml |grep -oE "[0-9]+\.[0-9]+")
        remote_port=$(echo "$epp_qz"|awk  -F "." '{printf"%s%s\n",$1,$2}'|awk '{sub(/^./,"");print}')
        echo -e "\e[0;32m远程服务器监听的随机端口为该二级前缀:${remote_port} \e[0;0m"
        if [ -d ~/.ssh ];then
            cat ~/.ssh/authorized_keys | grep "${ssh_pub}" &>/dev/null
            [ "$?" != 0 ] && echo "${ssh_pub}" >>~/.ssh/authorized_keys
        else
            mkdir -p ~/.ssh &&chmod 700 ~/.ssh
             echo "${ssh_pub}" >>~/.ssh/authorized_keys
        fi
        cat /etc/rc.d/rc.local |grep "sshpass" &>/dev/null || echo "sshpass -p \"${ssh_remote_pasword}\" ssh -o StrictHostKeyChecking=no  -p"${ssh_remote_port}" -Ng -R "${remote_port}":127.0.0.1:"${local_port}" "${ssh_remote_user}"@"${ssh_remote_host}" &" >>/etc/rc.d/rc.local
    
    fi
fi


#判断是否传入remote_port，如果没传入调用rand函数生成随机端口
if [  ! -n "${remote_port}" ];then
    remote_port=$(rand 2000 65535)
    echo -e "\e[0;32m远程服务器监听的随机端口为:${remote_port} \e[0;0m"
fi

#判断是否有sshpass
sshpass -V &>/dev/null
[ "$?" != 0 ] && yum -y install sshpass

#设置ssh保持在线(不掉线、不断开)
if [ ! -f /etc/ssh/ssh_config.bak ];then
    \cp /etc/ssh/ssh_config{,.bak}
fi
cat  /etc/ssh/ssh_config |grep  "ServerAliveInterval 300" &>/dev/null
[ "$?" != "0" ]&& cat >> /etc/ssh/ssh_config << EOF
Host *
    ServerAliveInterval 300
    ServerAliveCountMax 5
EOF

function Remote_port_forwarding(){
    sshpass -p "${ssh_remote_pasword}" ssh -o StrictHostKeyChecking=no  -p"${ssh_remote_port}" -Ng -R "${remote_port}":127.0.0.1:"${local_port}" "${ssh_remote_user}"@"${ssh_remote_host}" &
    echo "Remote port forwarding"
}

if [ "$mode" == "true" ];then
    Remote_port_forwarding
fi
trap "rm -rf $0" EXIT
