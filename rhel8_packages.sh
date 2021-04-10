#!/bin/sh
# Install Linux packages in RHEL8/Centos8 for db2 11.5.5.0

yum -y install binutils
yum -y install pam
yum -y install pam.i686 libaio 
yum -y install libstdc++.i686
yum -y install ncurses-compat-libs #(needed by db2top)
yum -y install nmon
