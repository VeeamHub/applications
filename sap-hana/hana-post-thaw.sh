#!/bin/bash

# hana-post-thaw.sh
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
# Copyright (c) 2016 Tom Sightler (tom.sightler@veeam.com)
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

# User configured optoins

# Log purgeoptions
# If PURGELOGS is set to "true" the script will purge backup entries from the catalog.
# The query find most recent backup older than PURGEDAYS and removes all entries
# from the backup catalog as well deleting log backups from the filesystem
PURGELOGS="true" # Purge backup catalog and log file backups from filesystems
PURGEDAYS=3      # Purge log backups and catalog data for backups older than this

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
USRSAP=/usr/sap  # Set to HANA install path

# The options below should normally not be changed
SAPSERVICE_PATH=${USRSAP}/sapservices
DATE=`date`
COMMENT="Veeam Backup Post-Thaw - ${DATE}"

# SQL command strings
REMSNAPSQL1="BACKUP DATA CLOSE SNAPSHOT BACKUP_ID "
REMSNAPSQL2="SUCCESSFUL '${COMMENT}'"
STATUSSQL="SELECT BACKUP_ID from M_BACKUP_CATALOG WHERE                           \
           STATE_NAME = 'prepared' and ENTRY_TYPE_NAME = 'data snapshot'"
PURGEIDSQL="SELECT TOP 1 min(to_bigint(BACKUP_ID)) FROM M_BACKUP_CATALOG          \
            WHERE SYS_START_TIME >= ADD_DAYS(CURRENT_TIMESTAMP, -${PURGEDAYS})    \
            and ENTRY_TYPE_NAME = 'data snapshot' and STATE_NAME = 'successful'"
PURGESQL1="BACKUP CATALOG DELETE ALL BEFORE BACKUP_ID"
PURGESQL2="WITH FILE"

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

#
# Main Script
#

read_sapservices

# Setup the output and authentication options for hdbsql
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
backupid=()
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
	hdbsqlcmd="${hdbpath[$i]}/hdbsql ${hdbsqlopts}${hdbinst[$i]}"
	backupid[$i]=`${hdbsqlcmd} "${STATUSSQL}"`
	if [[ -z ${backupid[$i]} ]]; then
		echo "No active snapshot found for this instance!"
	else
		${hdbsqlcmd} "${REMSNAPSQL1} ${backupid[$i]} ${REMSNAPSQL2}" &> /dev/null
		if [ ${PURGELOGS} = "true" ]; then
			purgeid=`${hdbsqlcmd} "${PURGEIDSQL}"`
			${hdbsqlcmd} -j ${PURGESQL1} ${purgeid} ${PURGESQL2} &> /dev/null
		fi 	 
	fi
	((i+=1))
done

