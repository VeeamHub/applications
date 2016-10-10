#!/bin/bash

timeout=300

if [ -f /var/run/mysqld/mysqld.pid ]
then
	mysql_pid=$(cat /var/run/mysqld/mysqld.pid) >/dev/null 2>&1
else
	echo "$0 : Mysql not started or bad mysql pid file location" | logger
	exit 1
fi

echo "$0 : Processing pre-freeze backup script" | logger

/etc/init.d/mysqld stop mysql & > /dev/null 2>&1

c=0
while [ true ]
do
	if [ $c -gt $timeout ]
	then
		echo "$0 : timed out, mysql shutdown failed" | logger
		exit 2
	fi
	# check if mysql is running
	if [ -f /var/run/mysqld/mysqld.pid ]
	then
		echo "$0 : Waiting 5 more seconds for mysql shutdown" | logger
		sleep 5
		c=$((c+5))
	else
		echo "$0 : Mysql stopped" | logger
		sync;sync	
		break
	fi
done