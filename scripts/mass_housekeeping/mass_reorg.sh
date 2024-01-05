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
echo "##> Reorg of schema $2";
echo "##> User: $USER"         ;
now=$(date --rfc-3339=seconds)
echo "##> Time: $now"          ;
echo "";
rm /tmp/$1_reorg_$2
db2 connect to $1;
db2 -x "select 'reorg table',substr(rtrim(tabschema)||'.'||rtrim(tabname),1,50),
    ';'from syscat.tables where tabschema = '$2' and type = 'T' " > /tmp/$1_reorg_$2 
db2 -tvf /tmp/$1_reorg_$2
db2 connect reset;
