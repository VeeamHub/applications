#!/bin/sh
# Script for Oracle RMAN to list database informations like the database ID
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
# Copyright (c) 2018 Andreas Neufert (andreas.neufert@veeam.com)
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
echo "SELECT * from v\$version;
var oracle_home clob;
exec dbms_system.get_env('ORACLE_HOME', :oracle_home);
print oracle_home;
SELECT DBID FROM v\$database;
" | sqlplus / as SYSDBA #>> /tmp/dbid.txt

