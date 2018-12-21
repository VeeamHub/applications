#!/bin/sh

# backup-gw-oes-prep.sh
#
# Version History
#
# 0.1 - 20161116 - Initial release
#
####################################################################
#
# MIT License
#
# Copyright (c) 2016 Joe Marton (joe.marton@veeam.com)
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

# Stop all GroupWise services

/etc/init.d/grpwise stop > /dev/null

# Backup eDirectory to a file
# More info on ndsbackup is in TID 7007592
# https://www.novell.com/support/kb/doc.php?id=7007592

ndsbackup cf /root/datreebackup -a admin.da -p password > /dev/null

# Backup all trustee assignments for each volume into its own file
# More info on metamig is in the OES documentation
# https://www.novell.com/documentation/oes2015/stor_nss_lx/data/metamig.html

metamig save VOL1 > /root/trustees.vol1
metamig save VOL2 > /root/trustees.vol2

