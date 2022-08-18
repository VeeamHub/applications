#!/bin/bash

# veeam-post-machine-thaw.sh
##### LICENSE ##################################################################
# Copyright 2021-2022 Stefan Zimmermann <stefan.zimmermann@veeam.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy 
# of this software and associated documentation files (the "Software"), to deal 
# in the Software without restriction, including without limitation the rights 
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in 
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
# SOFTWARE.
##### VERSION HISTORY ##########################################################
# v1.0.0    18.08.2022  Initial public release version

##### VARIABLES ################################################################
# Please adjust the following variables to your needs.

# Run all scripts from this folder in order as returned by `find`
SCRIPT_FOLDER="/opt/veeam/scripts/post" 

# Run scripts as this user
SCRIPT_USER="root"  

# Start scripts asynchronous if set to `1`
# Asynchronous start will not wait for the script to finish
ASYNC_MODE=0

# Number of seconds to sleep at the end of this script. 
# This is only used in ASYNC_MODE=1 and is useful to give the async scripts some time to work before the external freeze happens
ASYNC_SLEEP=10

# Logfile for this script, will contain script output in sync mode
LOG_FILE="/var/log/veeam/scripts/post.log"

# File for the PID of this pre-script
PID_FILE="/var/run/veeam-post-machine-thaw.pid"

################################################################################
# Please do not change any code below unless you know what you're doing.

VERSION="1.0.0"

# Rotate the scripts log file if savelog is available
# keeps 7 versions of the log per default
LOG_DIR="${LOG_FILE%/*}"
mkdir -p $LOG_DIR
if [ `command -v savelog` ] 
then    
    savelog -t -l -n -C $LOG_FILE
fi

##
## Simple logging mechanism for Bash
##
## Author: Michael Wayne Goodman <goodman.m.w@gmail.com>
## Thanks: Jul for the idea to add a datestring. See:
## http://www.goodmami.org/2011/07/simple-logging-in-bash-scripts/#comment-5854
## Thanks: @gffhcks for noting that inf() and debug() should be swapped,
##         and that critical() used $2 instead of $1
##
## License: Public domain; do as you wish
##

exec 3>>$LOG_FILE # logging stream (file descriptor 3) to log file
verbosity=5 # default to show warnings
silent_lvl=0
crt_lvl=1
err_lvl=2
wrn_lvl=3
inf_lvl=4
dbg_lvl=5

notify() { log $silent_lvl "NOTE : $1"; } # Always prints
critical() { log $crt_lvl "CRIT : $1"; }
error() { log $err_lvl "ERROR: $1"; }
warn() { log $wrn_lvl "WARN : $1"; }
inf() { log $inf_lvl "INFO : $1"; } # "info" is already a command
debug() { log $dbg_lvl "DEBUG: $1"; }
log() {
    if [ $verbosity -ge $1 ]; then
        datestring=`date +'%Y-%m-%d %H:%M:%S'`
        # Expand escaped characters, wrap at 100 chars, indent wrapped lines
        echo -e "$datestring $2" | fold -w100 -s | sed '2~1s/^/  /' >&3
    fi
}

inf "Starting $0 - Version $VERSION"

# Fail if another PID file is found
if [ -f $PID_FILE ]
then
    critical "PID file $PID_FILE exists - please check and clean!"
    exit 101
else
    echo $$ > $PID_FILE    
fi
RC=0
# Check if async scripts were started (PID file exists)

inf "Scripts are started in `[ $ASYNC_MODE == 1 ] && echo 'ASYNC' || echo 'SYNC'` mode"

for script in `find $SCRIPT_FOLDER/*`
do
    if [ ! -x $script ] 
    then
        warn "$script is not executable - skipping"
        continue 2
    fi

    inf "##### $script #####"
    if [ $ASYNC_MODE == 0 ]
    then        
        su -l -c $script - $SCRIPT_USER >&3        
        scriptRC=$?
    else        
        nohup su -l -c $script - $SCRIPT_USER & >&3 
        scriptRC=$?        
    fi
    
    if [ $scriptRC == 0 ]
    then
        inf "+++++ $script - RC $scriptRC +++++"
    else
        critical "!!!!! $script RC $scriptRC !!!!!"
        RC=$scriptRC
        break 2
    fi
done

if [ $ASYNC_MODE == 1 ]
then
    inf "Sleep for $ASYNC_SLEEP seconds before returning"
    sleep $ASYNC_SLEEP
fi

rm -f $PID_FILE &> /dev/null
if [ $? != 0 ]
then    
    critical "Cannot remove PID file $PID_FILE"
    RC=102
fi

inf "Ending $0 with RC $RC"
exit $RC
