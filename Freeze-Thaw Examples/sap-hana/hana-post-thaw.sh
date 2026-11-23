#!/bin/bash

# hana-post-thaw.sh
#
# Version History
#
# 0.1 - Jan 2, 2016 -  First working version, hardcoded commands
# 0.5 - Feb 7, 2016 -  First usable version, automatic sapservices discovery
#                      Checks snapshot status prior to exit, no more temp files
# 0.6 - Feb 8, 2016 -  Added support for HANA Secure User Store for more
#                      secure login handling
# 0.7 - Feb 9, 2016 -  Added support for optional backup catalog and log purge
#                      Cleaneed up some code and variable names to (hopefully)
#                      improve readability
# 1.0 - Aug 20, 2017 - ** Major changes for 1.0 Release **
#                      Added suppport for SAP HANA 2.0 SPS1 and greater
#                      Fixed bugs with log purging
#                      Added debug mode that can be run from the command line
#                      Optionally use config in separate file
# 1.1 - Dec 6, 2017 -  Bugfixes for key authentication, exit code status,
#                      and config file support
# 1.2 - Sep 4, 2020 SZ Small changes to regex to detect HANA services
# 2.0 - Feb 4, 2026 WS ** Major changes for 2.0 Release **
#                      - Added support for the new "systemctl" format of the
#                        sapservices file used by current SAP HANA / Linux
#                        releases, while keeping support for the legacy
#                        "sapstartsrv" format. Both formats are auto-detected.
#                      - Reworked hdbsql command and option handling, including
#                        -d SYSTEMDB for multitenant (MDC) systems. For keystore
#                        auth the key must target the SYSTEMDB (port 3<inst>13).
#                      - Restored keyprefix behaviour: the configured prefix is
#                        combined with the instance number to form the
#                        hdbuserstore key (e.g. HDB + 00 = HDB00).
#                      - Fixed systemctl-format parsing so multiple HANA
#                        instances on one host are detected correctly.
#                      - Simplified the version gate (any HANA 2.0+ is treated
#                        as multitenant) and removed duplicate option definitions.
#                      - Replaced "unset" usage with proper local variable scoping.
#                      - Backup catalog / log purge now runs per database: on MDC
#                        systems it iterates every active database (SYSTEMDB and
#                        each tenant), since each keeps its own catalog and log
#                        backups. Previously only the SYSTEMDB was purged.
#                      - Additional logging / diagnostic output.

####################################################################
#
# MIT License
#
#Copyright (c) 2017 Tom Sightler (tom.sightler@veeam.com)
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

# Starting with version 1.0 this script supports the use of an external config file.
# While it's still possible to manually set the username, password, keyprefix,
# purgelogs and purgedays options directly in this script, using a config file has
# the advantage that future updates to this script can be implemented without any
# changes to the file and the same exact script can be run on many different servers
# with the config options stored locally on each HANA server.
#
# By default the script checks for the config file in the path /etc/veeam/hana.conf
# but this can be overridden with the -c parameter.
#
# If the config file is found, any values set there override values set explicitly below

# Log purge options
# If "purgelogs" is set to "true" the script will purge backup entries from the catalog.
# The query finds the newest successful snapshot older than "purgedays" and removes all
# older entries from the backup catalog as well deleting log backups from the filesystem.
# On multitenant (MDC) systems this runs separately against every active database
# (SYSTEMDB and each tenant), because each database has its own catalog and log backups.
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
# For HANA 2.0 SP1 and higher, which are always installed as multi-tenant databases
# even when a single tenant is in use, you must specify that the connection use
# the port of the SYSTEMDB as follows:
# 
# ./hdbuserstore set HDB00 hana01:30013@SYSTEMDB VEEAM Backup123
#
# The SYSTEMDB SQL port is 3<instance#>13 (e.g. 30013 for 00, 30113 for 01).
#
# For more information about keystore use please refer to the SAP HANA documentation.
#
# Note that it is completely possible for the accounts to be difference for each
# instance.  The HANA account requires BACKUP ADMIN and CATALOG READ system privileges.
#
keyprefix="HDB"

# Additional configurable options
usrsap=/usr/sap  # Set to HANA install path

# The options below should normally not be changed
sapservices_file=${usrsap}/sapservices
date=$(date)
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

# Parse old-style sapstartsrv lines of sapservices
parse_sapstartsrv_old() {
    local line=$1
    local subexp="pf\=.*|-u *[[:alnum:]]{6}|-D"
    local expression="/usr/sap/[[:alnum:]]{3}/.*sapstartsrv *${subexp} *${subexp} *${subexp}"
    local entry=$(echo "${line}" | grep -E "${expression}")
    if [ -n "${entry}" ]; then
        g_commands[${#g_commands[@]}]=${entry}
        return 0
    fi
    return 1
}

# Parse new-style systemctl lines of sapservices
parse_systemctl_new() {
    local line=$1
    local subexp="SAP[[:alnum:]]{3}_[[:digit:]]{2}"
    local expression="systemctl .*start *${subexp}"
    local entry=$(echo "${line}" | grep -oE "${expression}")
    if [ -n "${entry}" ]; then
        local service=$(echo "${entry}" | grep -oE "${subexp}")
        local comment_part=$(echo "${line}" | sed 's/.*# //')  # Everything after #
        g_servicenames[${#g_servicenames[@]}]=${service}
        g_service_comments[${#g_service_comments[@]}]=${comment_part}
        return 0
    fi
    return 1
}

# Modern read_sapservices (like sapinit)
read_sapservices() {
    if [ ! -r "${sapservices_file}" ]; then
        echo "File ${sapservices_file} not found."
        exit 1
    fi

    local parsers="parse_sapstartsrv_old parse_systemctl_new"
    while IFS= read -r line; do
        line=$(echo "$line" | grep '^[^#]')  # Skip comments/empty
        [ -z "$line" ] && continue
        for parser in $parsers; do
            $parser "$line"
            [ $? -eq 0 ] && break
        done
    done < "${sapservices_file}"
}

# Extract HANA paths for new-style sapservices - handles noisy systemctl output
# Results are returned in the globals parsed_hdbpath / parsed_hdbpf. Dedicated
# names are used (NOT hdbpath/hdbpf) so the caller's per-instance arrays are not
# clobbered when more than one systemctl-format instance is present.
extract_hana_paths() {
    local cmdline=$1
    # Clean: remove ;... or {... noise
    cmdline=$(echo "$cmdline" | sed 's/[;{].*//' | xargs)

    parsed_hdbpath=""
    parsed_hdbpf=""

    [ $debug -ne 0 ] && echo "Parsing: '$cmdline'"

    if [[ $cmdline =~ pf=([^[:space:]]+) ]]; then
        local profile="${BASH_REMATCH[1]}"
        # HANA: /usr/sap/<SID>/SYS/profile/<SID>_HDB<NN>_<host>
        # Find SID (3 chars) and INST (HDBNN)
        if [[ $profile =~ /usr/sap/([A-Z0-9]{3})/SYS/profile/([A-Z0-9]{3})_HDB([0-9]{2}) ]]; then
            local sid="${BASH_REMATCH[1]}"
            local hdbinst_local="HDB${BASH_REMATCH[3]}"
            parsed_hdbpath="/usr/sap/${sid}/${hdbinst_local}/exe"
            parsed_hdbpf="$profile"
            [ $debug -ne 0 ] && echo "  -> exe=${parsed_hdbpath}, pf=${parsed_hdbpf}"
            return 0
        fi
    fi

    echo "Warning: Failed to parse from: $cmdline" >&2
    return 1
}

# A simple error handler function
error_exit() {
    echo "$1" 1>&2
    exit 1
}

debug=0
testmode=0
config="/etc/veeam/hana.conf"

# Get command line options
while getopts dtc: option; do
    case "${option}" in
    d) debug=1 ;;
    t) testmode=1 ;;
    c) config=${OPTARG} ;;
    esac
done

#
# MAIN SCRIPT
#

# Load sapservices
declare -a g_commands g_servicenames g_service_comments
read_sapservices

#  If config file is found, grab the options from there
if [ -r "${config}" ]; then
    username="$(config_get username)"
    password="$(config_get password)"
    keyprefix="$(config_get keyprefix)"
    purgelogs="$(config_get purgelogs)"
    purgedays="$(config_get purgedays)"
fi

# Setup the authentication options for hdbsql
if [ -z "${username}" ]; then
    [ $debug -ne 0 ] && echo "Using keystore based authentication: ${keyprefix}"
    # keyprefix is combined with the instance number (appended below via
    # ${hdbsqlopts}${hdbinst}) to form the hdbuserstore key, e.g. HDB + 00 = HDB00.
    # No -i is used here because the store key already encodes host:port.
    hdbsqlopts="-a -x -j -U ${keyprefix}"
else
    [ $debug -ne 0 ] && echo "Using user/password based authentication: ${username}"
    hdbsqlopts="-a -x -j -u ${username} -p ${password} -i "
fi

if [ $debug -ne 0 ] && [ "${purgelogs}" = "true" ]; then
    echo
    echo "Backups prior to the newest successful snapshot > ${purgedays} day(s) old"
    echo "will be purged from the catalog and filesystem"
    echo
fi

# Arrays
hdbpath=() hdbpf=() hdbinst=() hdbsqlcmd=() hdbverstr=() hdbrel=() hdbrev=()
backupid=() systemid=()
i=0
errors=0

# The two regexes below are only used by the OLD (sapstartsrv) format loop.
# This one grabs the exe path (LD_LIBRARY_PATH) and profile path (pf=) per instance.
sapservices_regex="LD_LIBRARY_PATH=([^:]+):.*pf=(\S+)"

# This one matches the SAPSYSTEM entry in the instance profile to get the instance ID.
hdbinst_regex="SAPSYSTEM.*=.*([0-9]{2})"

# ---------------------------------------------------------
# Shared per-instance logic
# ---------------------------------------------------------
process_instance() {
    local idx=$1

    # Query and parse HANA major version and SPS/Revision
    # (no -d SYSTEMDB here: at this point we do not yet know whether the system
    #  is multitenant, and M_DATABASE returns the version from any connected DB)
    hdbverstr[$idx]=$(LD_LIBRARY_PATH=${hdbpath[$idx]} ${hdbsqlcmd[$idx]} "${versionsql}")
    hdbverstr[$idx]=${hdbverstr[$idx]//\"/}
    local hdbver=(${hdbverstr[$idx]//./ })
    # Make sure bash sees these values as decimal
    hdbrel[$idx]=$((10#${hdbver[0]}))
    hdbrev[$idx]=$((10#${hdbver[2]}))

    # HANA 2.0+ is always multitenant (MDC): the operation must run on the SYSTEMDB
    # and needs the "FOR FULL SYSTEM" clause. HANA 1.0 is single-container.
    #
    # NOTE for keystore (-U) auth: the key MUST connect to the SYSTEMDB -- create it
    # against the SYSTEMDB SQL port 3<inst>13 (e.g. with @SYSTEMDB). With such a key
    # the "-d SYSTEMDB" below works; if the key points at a tenant it instead fails
    # with "SYSTEMDB not connected".
    # Keep a copy of the base command WITHOUT any "-d" so the purge below can
    # target each tenant database individually (the catalog/log purge is
    # per-database, unlike the system-wide snapshot close which runs on SYSTEMDB).
    local hdbsqlbase="${hdbsqlcmd[$idx]}"
    local remsnapsql
    if [ ${hdbrel[$idx]} -ge 2 ]; then
        hdbsqlcmd[$idx]="${hdbsqlcmd[$idx]} -d SYSTEMDB"
        remsnapsql="${remsnapsql1} ${remsnapsql2} ${remsnapsql3}"
    else
        remsnapsql="${remsnapsql1} ${remsnapsql3}"
    fi

    # Post-Thaw Actions
    local statussql="${statussql1} ${statussql2}"
    backupid[$idx]=$(LD_LIBRARY_PATH=${hdbpath[$idx]} ${hdbsqlcmd[$idx]} "${statussql}")

    systemid[$idx]=$(LD_LIBRARY_PATH=${hdbpath[$idx]} ${hdbsqlcmd[$idx]} "${sysidsql}")
    systemid[$idx]=${systemid[$idx]//\"/}

    if [[ -z ${backupid[$idx]} ]]; then
        echo "No active snapshot found for instance ${systemid[$idx]}"
        ((errors++))
        return
    fi

    # Close Snapshot
    local current_remsnapsql="${remsnapsql} ${backupid[$idx]} ${remsnapsql4}"

    if [ $debug -ne 0 ] || [ $testmode -ne 0 ]; then
        echo "LD_LIBRARY_PATH=${hdbpath[$idx]}" "${hdbsqlcmd[$idx]}" "${current_remsnapsql}"
    fi

    [ $testmode -eq 0 ] && LD_LIBRARY_PATH=${hdbpath[$idx]} ${hdbsqlcmd[$idx]} "${current_remsnapsql}"

    # Purge Logic
    if [ "${purgelogs}" = "true" ]; then
        # In an MDC system every database (SYSTEMDB and each tenant) keeps its
        # OWN backup catalog and its OWN log backups, so the purge must be run
        # once per database -- running it only against the SYSTEMDB would leave
        # the tenants' catalog entries and log backup files untouched.
        #
        # We discover the databases from the SYSTEMDB via M_DATABASES (only
        # ACTIVE ones, to avoid connecting to a stopped tenant) and purge each
        # with "-d <db>". For HANA 1.0 (single container) the list stays empty
        # and we purge once against the default connection with no -d.
        local purgedbs=""
        if [ ${hdbrel[$idx]} -ge 2 ]; then
            purgedbs=$(LD_LIBRARY_PATH=${hdbpath[$idx]} ${hdbsqlcmd[$idx]} \
                "SELECT DATABASE_NAME FROM M_DATABASES WHERE ACTIVE_STATUS = 'YES'")
            purgedbs=${purgedbs//\"/}
        fi

        local purgeidsql="${purgeidsql1} ${purgeidsql2} ${purgeidsql3}"
        local db purgecmd purgeid purgesql

        # ":-__single__" gives one iteration with no -d when the list is empty
        # (HANA 1.0); otherwise one iteration per discovered database.
        for db in ${purgedbs:-__single__}; do
            if [ "${db}" = "__single__" ]; then
                purgecmd="${hdbsqlbase}"
            else
                purgecmd="${hdbsqlbase} -d ${db}"
            fi

            # Each database has its own backup IDs, so the purge ID must be
            # looked up on that same database.
            purgeid=$(LD_LIBRARY_PATH=${hdbpath[$idx]} ${purgecmd} "${purgeidsql}")

            if [ -n "${purgeid}" ]; then
                purgesql="${purgesql1} ${purgeid} ${purgesql2}"
                if [ $debug -ne 0 ] || [ $testmode -ne 0 ]; then
                    echo "Purge backups with ID < $purgeid for ${db} (instance ${systemid[$idx]})"
                    echo "LD_LIBRARY_PATH=${hdbpath[$idx]}" "${purgecmd}" "${purgesql}"
                fi
                [ $testmode -eq 0 ] && LD_LIBRARY_PATH=${hdbpath[$idx]} ${purgecmd} "${purgesql}"
            fi
        done
    fi
}

# ---------------------------------------------------------
# PROCESS OLD STYLE (sapstartsrv)
# ---------------------------------------------------------
for cmdline in "${g_commands[@]}"; do
    # Extract paths (standard regex for old format lines)
    [[ $cmdline =~ $sapservices_regex ]]
    hdbpath[$i]="${BASH_REMATCH[1]}"
    hdbpf[$i]="${BASH_REMATCH[2]}"

    hdbpflines=$(grep "SAPSYSTEM" "${hdbpf[$i]}")
    [[ $hdbpflines =~ $hdbinst_regex ]] && hdbinst[$i]="${BASH_REMATCH[1]}"

    # Setup command (instance is concatenated onto the key for keystore,
    # or onto "-i " for user/password auth; see auth setup above)
    hdbsqlcmd[$i]="${hdbpath[$i]}/hdbsql ${hdbsqlopts}${hdbinst[$i]}"

    process_instance "$i"
    ((i++))
done

# ---------------------------------------------------------
# PROCESS NEW STYLE (systemctl)
# ---------------------------------------------------------
j=0
while [ $j -lt ${#g_servicenames[@]} ]; do
    # Prefer the live ExecStart from systemctl; if that is empty (e.g. the unit is
    # not loaded) fall back to the command captured from the sapservices comment.
    service_cmd=$(systemctl show "${g_servicenames[$j]}" -p ExecStart --value 2>/dev/null | grep -o 'pf=.*$' || echo "")
    [ -z "$service_cmd" ] && service_cmd="${g_service_comments[$j]}"

    if ! extract_hana_paths "$service_cmd"; then
        echo "Warning: Skipping unparsable service ${g_servicenames[$j]}" >&2
        ((j++))
        continue
    fi

    # Assign extracted to current index
    hdbpath[$i]=${parsed_hdbpath}
    hdbpf[$i]=${parsed_hdbpf}

    # Instance Detection
    hdbinst[$i]=""
    hdbpflines=$(grep -i "SAPSYSTEM[0-9]* *=[0-9]*" "${hdbpf[$i]}" 2>/dev/null)
    if [[ $hdbpflines =~ SAPSYSTEM[0-9]*=[0-9]{2} ]]; then
        hdbinst[$i]="${BASH_REMATCH[0]#*=}"
    elif [[ ${hdbpf[$i]} =~ _HDB([0-9]{2})_ ]]; then
        hdbinst[$i]="${BASH_REMATCH[1]}"
    fi
    if [ -z "${hdbinst[$i]}" ]; then
        echo "Warning: Skip ${g_servicenames[$j]} (no instance)"
        ((j++))
        continue
    fi

    # Setup command (instance is concatenated onto the key for keystore,
    # or onto "-i " for user/password auth; see auth setup above)
    hdbsqlcmd[$i]="${hdbpath[$i]}/hdbsql ${hdbsqlopts}${hdbinst[$i]}"

    process_instance "$i"

    ((i++))
    ((j++))
done

if [ $errors -gt 0 ]; then
    error_exit "Snapshots could not be found for some instances!"
else
    exit 0
fi
