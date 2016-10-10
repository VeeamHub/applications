#!/bin/bash

# config:
# when running on debian we can use existing debian-sys-maint account using defaults file
# otherwise, specify username and password below using use_credentials

#use_credentials="-uroot -p"
defaults_file="/etc/my.cnf"
timeout=300
lock_file=/tmp/mysql_tables_read_lock
###

if [ -f $defaults_file ]; then
        opts="--defaults-file=$defaults_file"
fi

if [ -n $use_credentials ]; then
        opts="$opts $use_credentials"
fi

sleep_time=$((timeout+10))

rm -f $lock_file
echo "$0 executing FLUSH TABLES WITH READ LOCK" | logger
mysql $opts -e "FLUSH TABLES WITH READ LOCK; system touch $lock_file; system nohup sleep $sleep_time; system echo lock released|logger; " > /dev/null &
mysql_pid=$!
echo "$0 child pid $mysql_pid" | logger

c=0
while [ ! -f $lock_file ]
do
        # check if mysql is running
        if ! ps -p $mysql_pid 1>/dev/null ; then
                echo "$0 mysql command has failed (bad credentials?)" | logger
                exit 1
        fi
        sleep 1
        c=$((c+1))
        if [ $c -gt $timeout ]; then
                echo "$0 timed out waiting for lock" | logger
                touch $lock_file
                kill $mysql_pid
        fi
done
echo $mysql_pid > $lock_file
exit 0