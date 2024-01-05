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
rm /tmp/mig_$1_runstats_$2
db2 connect to $1;
db2 -x "select 'RUNSTATS ON TABLE ' ,substr(rtrim(tabschema)||'.'||rtrim(tabname),1,50),'ON ALL COLUMNS WITH DISTRIBUTION ON ALL COLUMNS AND SAMPLED DETAILED INDEXES ALL  ;'from syscat.tables where tabschema = '$2' and type = 'T'"  > /tmp/mig_$1_runstats_$2
db2 -tvf /tmp/mig_$1_runstats_$2
db2 connect reset;
