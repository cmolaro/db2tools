#!/bin/sh
# Install Linux packages in RHEL8/Centos8 for db2 11.5.5.0

yum install binutils
yum install pam
yum install pam.i686 libaio 
yum install libstdc++.i686
yum install ncurses-compat-libs #(needed by db2top)
yum install nmon
