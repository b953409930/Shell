#!/bin/bash
#先执行initCheckIdis.sh
sh $PWD/initCheckIdis.sh

mkdir -p /opt/script/
chattr -i /opt/script/autostart.sh
cat > /opt/script/autostart.sh <<EOF
#!/bin/bash
#description:开机自启脚本
/usr/local/shns/bin/shutdown.sh
/usr/local/shns/bin/startup.sh
EOF

        cat /etc/rc.d/rc.local | grep "autostart.sh" | grep -v "grep" >> /dev/null
        stat=$?
        if [ $stat -ne 0 ];then
                echo "/opt/script/autostart.sh" >> /etc/rc.d/rc.local
        fi

chmod +x /opt/script/autostart.sh
chmod +x /etc/rc.d/rc.local
chattr +i /opt/script/autostart.sh
