#!/bin/bash
if ! [ -d /tmp/log ];then
        mkdir -p /tmp/log
fi
if ! [ -d /opt/script ];then
        mkdir -p /opt/script
fi
check_cron(){
        cat /var/spool/cron/root | grep "check_idis.sh" | grep -v "grep" >> /dev/null
        stat=$?
        if [  $stat -ne 0 ];then
              echo "*/5 * * * * sh /opt/script/check_idis.sh > /dev/null 2>&1" >> /var/spool/cron/root
        fi
}

#添加进程监测
chattr -i /opt/script/check_idis.sh
cat > /opt/script/check_idis.sh <<EOF
#!/bin/bash
LOG_DIR='/tmp/log'
DATE=\$(date +%Y%m%d%H%M)
check_cron(){
        cat /var/spool/cron/root | grep "check_idis.sh" | grep -v "grep" >> /dev/null
        stat=\$?
        if [  \$stat -ne 0 ];then
                echo "*/5 * * * * sh /opt/script/check_idis.sh > /dev/null 2>&1" >> /var/spool/cron/root
        fi
}
check_mq() {
	if [ -d /opt/rabbitmq_down ];then
	mq=\`ps -ef |grep beam|grep -v "grep"|wc -l\`
		if [ 0 == \$mq  ];then
			/opt/rabbitmq_down/sbin/rabbitmq-server -detached 
			/opt/rabbitmq_up/sbin/rabbitmq-server -detached
			echo "\$DATE mq is shutdown ">>\$LOG_DIR/mq.log
		fi
	fi
	}
check_lhsrs() {
        if  [ -d /usr/local/lhsrs ];then
                lhsrs=\`ps -ef |grep lhsrs |grep -v "grep" |wc -l\`
                if [ 0 == \$lhsrs ];then
                        echo "\$DATE lhsrs is shutdown " >>\$LOG_DIR/lhsrs.log
                        sh /usr/local/lhsrs/bin/startup.sh >/dev/null 2>&1
        	fi
        fi        
	}
check_shsrs() {
        if  [ -d /usr/local/shsrs ];then
                shsrs=\`ps -ef |grep shsrs |grep -v "grep" |wc -l\`
                if [ 0 == \$shsrs ];then
                        echo "\$DATE shsrs is shutdown " >>\$LOG_DIR/shsrs.log
                        sh /usr/local/shsrs/bin/startup.sh >/dev/null 2>&1
        	fi
        fi        
	}
check_shns() {
        if  [ -d /usr/local/shns ];then
                shns=\`ps -ef |grep shns |grep -v "grep" |wc -l\`
                if [ 0 == \$shns ];then
                        echo "\$DATE shns is shutdown " >>\$LOG_DIR/shns.log
                        sh /usr/local/shns/bin/startup.sh >/dev/null 2>&1
        	fi
	fi
	}
check_idisapi() {
        if  [ -d /usr/local/idisapi ];then
                idisapi=\`netstat -ntpl |grep idisapi |grep -v "grep" |wc -l\`
                if [ 0 == \$idisapi ];then
                        echo "\$DATE idisapi is shutdown " >>\$LOG_DIR/idisapi.log
                        sh /usr/local/idisapi/bin/startup.sh >/dev/null 2>&1
       		fi
	fi
	}
check_handleproxy() {
        if  [ -d /usr/local/idis-proxy ];then
                handleproxy=\`ps -ef |grep idis-proxy |grep -v "grep" |wc -l\`
                if [ 0 == \$handleproxy ];then
                        echo "\$DATE idis-proxy is shutdown " >>\$LOG_DIR/idis-proxy.log
                        sh /usr/local/idis-proxy/bin/startup.sh >/dev/null 2>&1
       		fi
	fi
	}
check_snms() {
	if  [ -d /opt/snms ];then
                snms=\`ps -ef |grep snms-web |grep -v "grep" |wc -l\`
                if [ 0 == \$snms ];then
                        echo "\$DATE snms is shutdown " >>\$LOG_DIR/snms.log
                        systemctl start docker
			cd /opt/snms
			docker-compose up -d
       		fi
	fi
	}
check() {
check_cron
check_mq
check_lhsrs
check_shsrs
check_shns
check_idisapi
check_handleproxy
check_snms
}
check
EOF

chmod +x /opt/script/check_idis.sh
chattr +i /opt/script/check_idis.sh
check_cron
