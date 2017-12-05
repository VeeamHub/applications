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
# 1.0 - Aug 20, 2017 - ** Major changes for 1.0 Release **
#                      Added suppport for SAP HANA 2.0 SPS1 and greater
#                      Fixed bugs with log purging
#                      Added debug mode that can be run from the command line
#                      Optionally use config in separate file
# 1.1 - Dec 5, 2017 - Minor bugfixes for key auth and config file support

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

# Starting with version 1.0 this script supports the use of an external config file.
# While it's still possible to manually set the username, password, keyprefix,
# purgelogs and purgedays options directly in this script, using a config file has
# the advantagei that future updates to this script can be implmeneted without any
# changes to the file and the same exact script can be run on many different servers
# with the config options stored locally on each HANA server.
#
# By default the script checks for the config file in the path /etc/veeam/hana.conf
# but this can be overridden with the -c parameter.
#
# If the config file is found, any values set there override values set explicitly below

# Log purge options
# If "purgelogs" is set to "true" the script will purge backup entries from the catalog.
# The query finds the newest successful snapshot older than "purgdays" and removes all
# older entries from the backup catalog as well deleting log backups from the filesystem
purgelogs="false" # Purge backup catalog and log file backups from filesystems
purgedays=3       # Purge log backups and catalog data for backups older than this

# This script can use standard username/password or Secure User Store Authentication
# Secure User Store requires a key for each instance which must be configured outside
# of this script using hdbuserstore executable (part of hdbclient install).
# See more details in the Secure User Store section below.

# To use standard Username and Password set these, otherwise leave them empty
username=""
password=""

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
keyprefix="HDB"

# Additional configurable options
usrsap=/usr/sap  # Set to HANA install path

# The options below should normally not be changed
sapservices_file=${usrsap}/sapservices
date=`date`
comment="Veeam Backup Post-Thaw - ${date}"

# SQL command strings
remsnapsql1="BACKUP DATA"
remsnapsql2="FOR FULL SYSTEM"
remsnapsql3="CLOSE SNAPSHOT BACKUP_ID" 
remsnapsql4="SUCCESSFUL '${comment}'"

statussql1="SELECT BACKUP_ID from M_BACKUP_CATALOG WHERE"
statussql2="STATE_NAME = 'prepared' and ENTRY_TYPE_NAME = 'data snapshot'"

purgeidsql1="SELECT TOP 1 to_bigint(BACKUP_ID) FROM M_BACKUP_CATALOG"
purgeidsql2="WHERE SYS_START_TIME <= ADD_DAYS(CURRENT_TIMESTAMP, -${purgedays}) and"
purgeidsql3="ENTRY_TYPE_NAME = 'data snapshot' and STATE_NAME = 'successful' ORDER BY 1 DESC"
purgesql1="BACKUP CATALOG DELETE ALL BEFORE BACKUP_ID"
purgesql2="WITH FILE"

versionsql="SELECT VERSION from M_DATABASE;"

sysidsql="SELECT SYSTEM_ID from M_DATABASE;"

#
# Functions
#

# This function makes it easy to retrieve options from a file
# It borrows heavily from an example on Stack Overflow
config_get() {
    val="$(grep -E "^${1}=" -m 1 "${config}" 2>/dev/null | head -n 1 | cut -d '=' -f 2)"
    tmp="${val%\"}"
    val="${tmp#\"}"
    printf -- "%s" "${val}"
}

#
# This function is copied from "sapinit" script provided by SAP HANA install
# It performs some simple regex matching to grab  the strings specific to HANA
# instance information
#
read_sapservices() {	
    if [ ! -r "${sapservices_file}" ]; then
        echo  "File ${sapservices_file} not found."
        exit_code=1
    fi

    subexp="pf\=.*|-u *[[:alnum:]]{6}|-D"
    expression="/usr/sap/[[:alnum:]]{3}/.*sapstartsrv *${subexp} *${subexp} *${subexp}"

    lines=`cat ${sapservices_file} | wc -l`

    ((l=0));((i=1))
    while ((i <= ${lines}))
    do
        pre_l=`head -${i} ${sapservices_file} | tail -1 | grep -E "${expression}"`
        if [ -n "${pre_l}" ]; then
            sapservices[${l}]=${pre_l}
            (( l++ ))
        fi
        (( i++ ))
    done

    unset subexp
    unset expression
    unset pre_l
    unset lines
    unset i
}

debug=0
testmode=0

# Get command line options
config="/etc/veeam/hana.conf"
while getopts dtc: option
do
    case "${option}"
    in
    d) debug=1;;
    t) testmode=1;;
    c) config=${OPTARG};;
    esac
done

#
# Main Script
#

# Call the function to load up sapservices data
read_sapservices

# If config file is found grab the options from there
if [ -r ${config} ]; then
    username="$(config_get username)"
    password="$(config_get password)"
    keyprefix="$(config_get keyprefix)"
    purgelogs="$(config_get purgelogs)"
    purgedays="$(config_get purgedays)"
fi

# Setup the authentication options for hdbsql
if [ -z ${username} ]; then
    if [ $debug -ne 0 ]; then
        echo "Using keystore based authentication"
        echo "Keyprefix: ${keyprefix}"
    fi
    hdbsqlopts="-a -x -j -U ${keyprefix}"
else
    if [ $debug -ne 0 ]; then
        echo "Using user/password based authentication"
        echo "Username: ${username}"
        echo "Password: ${password}"
    fi
    hdbsqlopts="-a -x -j -u ${username} -p ${password} -i "
fi

if [ $debug -ne 0 ] && [ ${purgelogs} = "true" ]; then
    echo
    echo "Backups prior to the newest successful snapshot > ${purgedays} day(s) old"
    echo "will be purged from the catalog and filesystem"
    echo
fi

# This regex grabs the exe path and profile path for each HANA instances
sapservices_regex="LD_LIBRARY_PATH=(.+):.*pf=(\S+)"

# This regex is used to match the SAPSYSTEM envrionment for the instance ID
hdbinst_regex="SAPSYSTEM.*=.*([0-9]{2})"

hdbpath=()
hdbpf=()
hdbinst=()
hdbsqlcmd=()
hdbverstr=()
hdbrel=()
hdbrev=()
backupid=()
systemid=()
i=0

# Loop through every instance found in SAP services
for line in "${sapservices[@]}"
do
    [[ $line =~ $sapservices_regex ]]
    hdbpath[$i]="${BASH_REMATCH[1]}"
    hdbpf[$i]="${BASH_REMATCH[2]}"
    hdbpflines=`cat ${hdbpf[$i]} | grep "SAPSYSTEM"`
    for hdbpfline in "${hdbpflines}"
    do
	[[ $hdbpfline =~ $hdbinst_regex ]] && hdbinst[$i]="${BASH_REMATCH[1]}"
    done

    hdbsqlcmd[$i]="${hdbpath[$i]}/hdbsql ${hdbsqlopts}${hdbinst[$i]}"

    # Query and parse HANA major version and SPS/Revision
    hdbverstr[$i]=$(LD_LIBRARY_PATH=${hdbpath[$i]} ${hdbsqlcmd[$i]} "${versionsql}")
    hdbverstr[$i]=${hdbverstr[$i]//\"/}
    hdbver=(${hdbverstr[$i]//./ })
    # Make sure bash sees these values as decimal
    hdbrel[$i]=$((10#${hdbver[0]}))
    hdbrev[$i]=$((10#${hdbver[2]}))

    # If HANA version greater than 2.0 SP1 set some extra options
    if [ ${hdbrel[$i]} -ge 2 ] && [ ${hdbrev[$i]} -ge 10 ]; then
        hdbsqlcmd[$i]="${hdbsqlcmd[$i]} -d SYSTEMDB"
        remsnapsql="${remsnapsql1} ${remsnapsql2} ${remsnapsql3}"
    else
        remsnapsql="${remsnapsql1} ${remsnapsql3}"
    fi

    statussql="${statussql1} ${statussql2}"
    backupid[$i]=$(LD_LIBRARY_PATH=${hdbpath[$i]} ${hdbsqlcmd[$i]} "${statussql}")
    systemid[$i]=$(LD_LIBRARY_PATH=${hdbpath[$i]} ${hdbsqlcmd[$i]} "${sysidsql}")
    systemid[$i]=${systemid[$i]//\"/}

    if [[ -z ${backupid[$i]} ]]; then
	echo "No active snapshot found for instance ${systemid[$i]}"
    else
	remsnapsql="${remsnapsql} ${backupid[$i]} ${remsnapsql4}"
	if [ $debug -ne 0 ] || [ $testmode -ne 0 ]; then
	    echo "LD_LIBRARY_PATH=${hdbpath[$i]}" "${hdbsqlcmd[$i]}" "${remsnapsql}"
	fi
	[ $testmode -eq 0 ] && LD_LIBRARY_PATH=${hdbpath[$i]} ${hdbsqlcmd[$i]} "${remsnapsql}"
	if [ ${purgelogs} = "true" ]; then
	    purgeidsql="${purgeidsql1} ${purgeidsql2} ${purgeidsql3}"
	    purgeid=$(LD_LIBRARY_PATH=${hdbpath[$i]} ${hdbsqlcmd[$i]} "${purgeidsql}")
	    if [ ! -z ${purgeid} ]; then
		purgesql="${purgesql1} ${purgeid} ${purgesql2}"
		if [ $debug -ne 0 ] || [ $testmode -ne 0 ]; then
		    echo "Purge backups with ID < $purgeid for instance ${systemid[$i]}"
		    echo "LD_LIBRARY_PATH=${hdbpath[$i]}" "${hdbsqlcmd[$i]}" "${purgesql}"
		fi
		[ $testmode -eq 0 ] && LD_LIBRARY_PATH=${hdbpath[$i]} ${hdbsqlcmd[$i]} "${purgesql}"
	    fi
	fi 	 
    fi
    (( i++ ))
done

