#/bin/bash
# usage => first argument is the target database
#       => secnd argument is the target schema


. $HOME/.bash_profile

# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

#. /home/db2bnld1/sqllib/db2profile

echo "##> Connect to $1";
echo "##> Runstats of schema $2";
echo "##> User: $USER"         ;
now=$(date --rfc-3339=seconds)
echo "##> Time: $now"          ;
echo "";
 
rm /tmp/housekeep_$1_reorg_$2
 
db2 connect to $1;

#Reorg Tables
db2 -x "select 'REORG TABLE ' ,substr(rtrim(tabschema)||'.'||rtrim(tabname),1,50),'inplace allow write access  ;'from syscat.tables where tabschema = '$2' and type = 'T'"  > /tmp/housekeep_$1_reorg_$2

# execute
db2 -tvf /tmp/housekeep_$1_reorg_$2
 
db2 connect reset;
