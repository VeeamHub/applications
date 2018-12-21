#!/bin/bash

timeout=300

if [ -f /var/run/mariadb/mariadb.pid ]
then
	mysql_pid=$(cat /var/run/mariadb/mariadb.pid) >/dev/null 2>&1
else
	echo "$0 : MariaDB not started or bad MariaDB pid file location" | logger
	exit 1
fi

echo "$0 : Processing pre-freeze backup script" | logger

systemctl stop mariadb & > /dev/null 2>&1

c=0
while [ true ]
do
	if [ $c -gt $timeout ]
	then
		echo "$0 : timed out, MariaDB shutdown failed" | logger
		exit 2
	fi
	# check if MariaDB is running
	if [ -f /var/run/mariadb/mariadb.pid ]
	then
		echo "$0 : Waiting 5 more seconds for MariaDB shutdown" | logger
		sleep 5
		c=$((c+5))
	else
		echo "$0 : MariaDB stopped" | logger
		sync;sync	
		break
	fi
done
