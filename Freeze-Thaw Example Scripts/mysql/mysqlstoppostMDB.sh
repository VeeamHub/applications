#!/bin/bash

timeout=300

echo "$0 : processing post-thaw backup script" | logger

if [ -f /var/run/mariadb/mariadb.pid ]
then
	MariaDB_pid=$(cat /var/run/mariadb/mariadb.pid) >/dev/null 2>&1
	echo "$0 : MariaDB already started with PID $MariaDB_pid " | logger
	exit 1
fi

systemctl start mariadb & > /dev/null 2>&1

c=0
while [ true ]
do
	if [ $c -gt $timeout ]
	then
		echo "$0 : timed out, MariaDB startup failed" | logger
		exit 2
	fi
	# check if MariaDB is running
	if [ -f /var/run/mariadb/mariadb.pid ]
	then
		MariaDB_pid =$(cat /var/run/mariadb/mariadb.pid) >/dev/null 2>&1
		echo "$0 : MariaDB started with pid $MariaDB_pid " | logger
		break
	else
		echo "$0 : Waiting 5 more seconds for MariaDB startup"
		sleep 5
		c=$((c+5))
	fi
done