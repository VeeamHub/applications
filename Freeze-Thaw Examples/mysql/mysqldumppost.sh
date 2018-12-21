#!/bin/bash

dump_file="/tmp/mysql_dump.sql"

if [ -f $dump_file ]
then
        echo "$0 deleting mysql dump file $dump_file" | logger
        rm -f $dump_file > /dev/null 2>&1
        exit 0
else
        echo "$0 could not locate mysql dump file  $dump_file" | logger
        exit 1
fi