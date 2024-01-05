#!/bin/bash
# usage => first argument is the target database
#       => secnd argument is the target schema

. /home/db2bnlp1/sqllib/db2profile

db2 connect to $1;
if [[ $? -ge 4 ]]; then
  echo "Failed to connect to $1"
  exit 8
fi

qy1_out=`db2 -x "SELECT STRIP(STRIP(TABSCHEMA) || '.' || STRIP(TABNAME)) from SYSCAT.TABLES where type = 'T' and STATUS='C' and tabschema not like 'SYS%' and tabname not like '_EXC' order by TABSCHEMA, TABNAME"`

if [[ $? -ge 4 ]]; then
  echo "Failed to execute query"
  echo "$qy1_out";
  exit 8
fi

cnt=0
while read -r line
 do
    ((cnt++))
    echo ""
    echo "----> working with table: $line"
    echo "--- >" "drop table "$line"_EXC"
    db2 -x "drop table "$line"_EXC"
    db2 -x "create table "$line"_EXC like $line"
    echo "---->"  "SET INTEGRITY FOR $line IMMEDIATE CHECKED NOT INCREMENTAL FOR EXCEPTION IN $line USE "$line"_EXC"
    db2 -x "SET INTEGRITY FOR $line IMMEDIATE CHECKED NOT INCREMENTAL FOR EXCEPTION IN $line USE "$line"_EXC"
    db2 -x "CALL SYSPROC.ADMIN_CMD( 'EXPORT TO "/tmp/$1_EXC_DATA_$1" OF DEL MESSAGES ON SERVER SELECT * FROM "$line"_EXC' )"
 done <<< "$qy1_out"
