#!/bin/bash
#先执行initCheckIdis.sh
sh $PWD/initCheckIdis.sh

mkdir -p /opt/script/
chattr -i /opt/script/autostart.sh
cat > /opt/script/autostart.sh <<EOF
#!/bin/bash
#description:开机自启脚本
export PATH=\$PATH:/usr/local/erlang/bin
export HOME=/opt/rabbitmq_up/
hostnamectl set-hostname shsrs1
/opt/rabbitmq_up/sbin/rabbitmq-server -detached
while true
do
a=\$(netstat -nltp |grep 5673)
if [ ! -n "\$a" ];then
/opt/rabbitmq_up/sbin/rabbitmq-server -detached
sleep 5
else
/usr/local/shsrs/bin/shutdown.sh
/usr/local/shsrs/bin/startup.sh
/usr/local/idis-proxy/bin/shutdown.sh
/usr/local/idis-proxy/bin/startup.sh
chmod +x /usr/local/idisapi/bin/*.sh
/usr/local/idisapi/bin/shutdown.sh
/usr/local/idisapi/bin/startup.sh
break
fi
done
EOF

        cat /etc/rc.d/rc.local | grep "autostart.sh" | grep -v "grep" >> /dev/null
        stat=$?
        if [ $stat -ne 0 ];then
                echo "/opt/script/autostart.sh" >> /etc/rc.d/rc.local
        fi

chmod +x /opt/script/autostart.sh
chmod +x /etc/rc.d/rc.local
chattr +i /opt/script/autostart.sh
