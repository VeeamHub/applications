#!/bin/bash

lock_file=/tmp/mysql_tables_read_lock
###

mysql_pid=$(cat $lock_file)
echo "$0 sending sigterm to $mysql_pid" | logger
pkill -9 -P $mysql_pid
rm -f $lock_file
exit 0