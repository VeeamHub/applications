#!/bin/bash

# config:
# when running on debian we can use existing debian-sys-maint account using defaults file
# otherwise, specify username and password below using use_credentials

#use_credentials="-uroot -p"
defaults_file="/etc/my.cnf"
dump_file="/tmp/mysql_dump.sql"
database="--all-databases"

sleep 120

if [ -f $defaults_file ]
then
	opts="--defaults-file=$defaults_file"
elif [ -n $use_credentials ]
then
	opts="$opts $use_credentials"
else
	echo "$0 : error, no mysql authentication method set" | logger
	exit 1
fi

opts="$opts $database"

echo "$0 executing mysqldump" | logger
mysqldump $opts >$dump_file 2>/dev/null
if [ $? -ne 0 ]
then
	echo "$0 : mysqldump failed" | logger
	exit 2
else
	echo "$0 : mysqldump suceeded" | logger
	sync;sync
fi