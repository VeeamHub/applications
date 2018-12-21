#!/bin/bash

timeout=300

echo "$0 : processing post-thaw backup script" | logger

if [ -f /var/run/mysqld/mysqld.pid ]
then
	mysql_pid=$(cat /var/run/mysqld/mysqld.pid) >/dev/null 2>&1
	echo "$0 : Mysql already started with PID $mysql_pid" | logger
	exit 1
fi

/etc/init.d/mysqld start mysql & > /dev/null 2>&1

c=0
while [ true ]
do
	if [ $c -gt $timeout ]
	then
		echo "$0 : timed out, mysql startup failed" | logger
		exit 2
	fi
	# check if mysql is running
	if [ -f /var/run/mysqld/mysqld.pid ]
	then
		mysql_pid=$(cat /var/run/mysqld/mysqld.pid) >/dev/null 2>&1
		echo "$0 : MySQL started with pid $mysql_pid" | logger
		break
	else
		echo "$0 : Waiting 5 more seconds for mysql startup"
		sleep 5
		c=$((c+5))
	fi
done