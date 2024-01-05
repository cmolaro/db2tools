#!/bin/bash

function check_db
{

      h=`db2 -x "SELECT trim(timestampdiff(8, CAST(CURRENT_TIMESTAMP - TIMESTAMP(START_TIME) as CHAR(22))))  FROM SYSIBMADM.DB_HISTORY WHERE OPERATION = 'B' order by START_TIME DESC FETCH FIRST 1 ROW ONLY"`
      h=`echo $h`
 
      if [ $h -lt 100 ]
      then
          status=0
          statustxt=OK
      elif [ $h -lt 200 ]
      then
          status=1
          statustxt=WARNING
      else
          status=2
          statustxt=CRITICAL
      fi
      echo "$status Age_last_backup_$db age_hours=$h;48;120;0; $statustxt - $h hours since last $db full backup"

      db2 connect reset > /dev/null ;
}

dbs="DPBNL01"

for db in $dbs
do

    db2 connect to $db > /dev/null ;

    if [ $? -lt 1 ] 
    then
      check_db $db
    else
      h=0
      statustxt=CRITICAL
      status=2
      echo "$status Age_last_backup_$db age_hours=$h;48;120;0; $statustxt - $h hours since last $db full backup - error connect db"
    fi

done
