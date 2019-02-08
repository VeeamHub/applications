#!/bin/sh
# Example script to recover an Oracle Database from another server to the current server.
#
# Version History
#
# 0.3 - Feb. 02, 2019 - This is more an example file rather then a script...needs to be finetuned for customer environments
#
# 
#
####################################################################
#
# MIT License
#
# Copyright (c) 2018 Andreas Neufert (andreas.neufert@veeam.com) and Tom Sightler (tom.sightler@veeam.com)
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

#INPUT - Please fill out
varsrcdbid="<source_database_id>"
varsourceserver="<source_server>"  # at clusters use source clustername
varrepoid="<repo_uuid>" # Can be found in /opt/veeam/VeeamPluginforOracleRMAN/veeam_config.xml
vartargetdbname="orcl" # Target database instance name
varconnectstring="/" # Connect string if local doesn't work. Minimum input is "/"

varspfiletmp="$ORACLE_HOME/dbs/spfile${vartargetdbname}restore.ora"
varspfileoriginal="$ORACLE_HOME/dbs/spfile${vartargetdbname}.ora"


# Output some of the inputs
echo "DBID="$vardbid
echo "SourceServer="$varsourceserver
echo "RepoID="$varrepoid

#Change the Veeam Plugin for Oracle RMAN configuration to temporary access the original (source) server backup files and output it.
sed -i  "s/<PluginParameters \/>/<PluginParameters customServerName=\"$varsourceserver\" \/>/g" /opt/veeam/VeeamPluginforOracleRMAN/veeam_config.xml
echo "Temporary alter the Veeam configuration"
echo "==============================================================="
cat /opt/veeam/VeeamPluginforOracleRMAN/veeam_config.xml
echo "==============================================================="

# Restore SPFile and Controlfiles
rman TARGET $varconnectstring <<EOF
RUN {
SHUTDOWN IMMEDIATE;
set DBID=$vardbid;
startup force nomount;
SET CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE 'SBT_TAPE' TO '$varrepoid/%F_RMAN_AUTOBACKUP.vab';
ALLOCATE CHANNEL VeeamAgentChannel1 DEVICE TYPE sbt_tape PARMS 'SBT_LIBRARY=/opt/veeam/VeeamPluginforOracleRMAN/libOracleRMANPlugin.so';
restore spfile TO '$varspfiletmp' from autobackup;
shutdown immediate;
}
HOST 'cp -rf $varspfiletmp $varspfileoriginal';
HOST 'rm -rf $varspfiletmp';
RUN {
set DBID=$vardbid;
startup nomount;
SET CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE 'SBT_TAPE' TO '$varrepoid/%F_RMAN_AUTOBACKUP.vab';
ALLOCATE CHANNEL VeeamAgentChannel1 DEVICE TYPE sbt_tape PARMS 'SBT_LIBRARY=/opt/veeam/VeeamPluginforOracleRMAN/libOracleRMANPlugin.so';
restore controlfile from autobackup;
alter database mount;
}
EOF

# Get the last SCN in the backup
lastscn=$(($(echo "restore controlfile preview;" | rman target $varconnectstring | grep "no backup of archived log for thread" | cut -d ' ' -f 16)-1))

# Restore and recover database files to most recent
rman TARGET $varconnectstring <<EOF
RUN {
ALLOCATE CHANNEL VeeamAgentChannel1 DEVICE TYPE sbt_tape PARMS 'SBT_LIBRARY=/opt/veeam/VeeamPluginforOracleRMAN/libOracleRMANPlugin.so';
restore database;
crosscheck backup of archivelog all;
recover database until scn $lastscn;
}
alter database open resetlogs;
EOF

#Restore the Veeam configuration xml file to original values and output it.
sed -i  "s/<PluginParameters customServerName=\"$varsourceserver\" \/>/<PluginParameters \/>/g" /opt/veeam/VeeamPluginforOracleRMAN/veeam_config.xml
echo "Restore Veeam Plugin configuration"
echo "==============================================================="
cat /opt/veeam/VeeamPluginforOracleRMAN/veeam_config.xml
echo "==============================================================="