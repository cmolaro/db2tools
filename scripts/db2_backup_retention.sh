#/bin/bash

# usage => first argument is the target database
#       => secnd argument is the # of backups to keep

# . $HOME/.bash_profile

# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

echo "##> DB: $1";
echo "##> Nbr of backups: $2"         ;
echo "##> Current user: $USER"         ;
now=$(date --rfc-3339=seconds)
echo "##> Time: $now"          ;
echo "";
db2 connect to $1;
db2 update db cfg for $1 using REC_HIS_RETENTN 366;
db2 update db cfg for $1 using NUM_DB_BACKUPS $2;
db2 update db cfg for $1 using AUTO_DEL_REC_OBJ on;

echo "##> -------------------------------------------------------";

db2 get db cfg for $1 | grep -i REC_HIS_RETENTN;
db2 get db cfg for $1 | grep -i NUM_DB_BACKUPS;
db2 get db cfg for $1 | grep -i AUTO_DEL_REC_OBJ;

echo "##> -------------------------------------------------------";
db2 connect reset;
