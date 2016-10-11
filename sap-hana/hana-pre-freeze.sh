#!/bin/bash

# hana-pre-freeze.sh
#
# Version History
#
# 0.1 - Jan 2, 2016 - First working version, hardcoded commands
# 0.5 - Feb 7, 2016 - First usable version, automatic sapservices discovery
#                     Checks snapshot status prior to exit, no more temp files
# 0.6 - Feb 8, 2016 - Added support for HANA Secure User Store for more
#                     secure login handling  
# 0.7 - Feb 9, 2016 - Added support for optional backup catalog and log purge
#                     Cleaneed up some code and variable names to (hopefully)
#                     improve readability

####################################################################
#
# MIT License
#
#Copyright (c) 2016 Tom Sightler (tom.sightler@veeam.com)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
####################################################################

# User configured options

# This script can use standard username/password or Secure User Store Authentication
# Secure User Store requires a key for each instance which must be configured outside
# of this script using hdbuserstore executable (part of hdbclient install).
# See more details in the Secure User Store section below.

# To use standard Username and Password set these, otherwise leave them empty
USERNAME=""
PASSWORD=""

# To use Secure User Store for SAP HANA authentication select a key prefix.
# This prefix will be combined with the instance number to reference a specific
# key for authentication.  For example, the default prefix is HDB, so for
# instance 00 the script will attempt to use key HDB00 to authenticate.
#
# To create Secure User Store use the following command syntax:
#
# ./hdbuserstore set <key> <host>:3<instance#>15 <user> <password>
# 
# For example, to create keys for instance 00 and 01 on host "hana01"
# using a username "VEEAM" and password "Backup123" run the following commands
# as the OS user that will be running the script to create their secure store:
#
# ./hdbuserstore set HDB00 hana01:30015 VEEAM Backup123
# ./hdbuserstore set HDB01 hana01:30115 VEEAM Backup123
#
# Note that it is completely possible for the accounts to be difference for each
# instance.  The HANA account requires BACKUP ADMIN and CATALOG READ system privledges.
#
KEYPREFIX="HDB" 

# Additional configurable options
USRSAP=/usr/sap # Path to sapservices file/HANA install path
TIMEOUT=300 # Maximum number of seconds to wait for snapshots to enter prepared state

# These options below should normally not be changed
SAPSERVICE_PATH=${USRSAP}/sapservices
DATE=`date`
COMMENT="Veeam Backup Pre-Freeze - ${DATE}"

# SQL command strings
SNAPSQL="BACKUP DATA CREATE SNAPSHOT COMMENT '$COMMENT'"
STATUSSQL="SELECT BACKUP_ID from M_BACKUP_CATALOG WHERE STATE_NAME = 'prepared' \
           and ENTRY_TYPE_NAME LIKE '%snap%'"

#
# Functions
#

#
# This function is copied from "sapinit" script provided by SAP HANA install
# It performs some simple regex matching to grab  the strings specific to HANA
# instance information
#
read_sapservices() {	
        if [ ! -r "${SAPSERVICE_PATH}" ]; then
                echo  "File ${SAPSERVICE_PATH} not found."
                exit_code=1
        fi

        subexp="pf\=.*|-u *[[:alnum:]]{6}|-D"
        expression="/usr/sap/[[:alnum:]]{3}/.*sapstartsrv *${subexp} *${subexp} *${subexp}"

        lines=`cat ${SAPSERVICE_PATH} | wc -l`

        ((l=0));((i=1))
        while ((i <= ${lines}))
        do
                pre_l=`head -${i} ${SAPSERVICE_PATH} | tail -1 | grep -E "${expression}"`
                if [ -n "${pre_l}" ]; then
                        g_commands[${l}]=${pre_l}
                        ((l+=1))
                fi
                ((i+=1))
        done

        unset subexp
        unset expression
        unset pre_l
        unset lines
        unset i
}

# A way too simple error exit handler function
error_exit()
{
        echo "$1" 1>&2
        exit 1
}

#
# Main Script
#

# Call the functin to load up sapservices data
read_sapservices

# Setup the authentication options for hdbsql
if [ -x ${USERNAME} ]; then
        hdbsqlopts="-a -x -j -U ${KEYPREFIX}"
else
        hdbsqlopts="-a -x -j -u ${USERNAME} -p ${PASSWORD} -i "
fi

# This regex grabs the exe path and profile path for each HANA instances
sapservices_regex="LD_LIBRARY_PATH=(.+):.*pf=(\S+)"

# This regex is used to match the SAPSYSTEM envrionment for the instance ID
hdbinst_regex="SAPSYSTEM.*=.*([0-9]{2})"

hdbpath=()
hdbpf=()
hdbinst=()
hdbcmd=()
i=0
for line in "${g_commands[@]}"
do
	[[ $line =~ $sapservices_regex ]]
	hdbpath[$i]="${BASH_REMATCH[1]}"
	hdbpf[$i]="${BASH_REMATCH[2]}"
	hdbpflines=`cat ${hdbpf[$i]} | grep "SAPSYSTEM"`
	for hdbpfline in "${hdbpflines}"
	do
		if [[ $hdbpfline =~ $hdbinst_regex ]]; then 
			hdbinst[$i]="${BASH_REMATCH[1]}"
		fi
	done
	hdbsqlcmd[$i]="${hdbpath[$i]}/hdbsql ${hdbsqlopts}${hdbinst[$i]}"
	${hdbsqlcmd[$i]} "${SNAPSQL}" &> /dev/null
	((i+=1))
done

backupid=()
while (($TIMEOUT > 0)) && ((${#backupid[@]} < ${#hdbpath[@]}));
do
	sync
	sleep 5
	TIMEOUT=$((TIMEOUT-5))
	i=0
	for j in "${hdbpath[@]}"
	do
		id=""
		id=`${hdbsqlcmd[$i]} "${STATUSSQL}"`
		if [ -n "${id}" ]; then
                        backupid[${i}]=${id}
                fi
                ((i+=1))
	done
done

if (($TIMEOUT <= 0)); then
	error_exit "Timeout waiting for HANA DB freeze status!"
fi

