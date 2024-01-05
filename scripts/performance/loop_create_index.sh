#!/bin/bash
db_list=`db2 list database directory  | grep -B6 -i indirect | grep "Database name" | awk '{print $4}'`
#db_list=`db2 list db directory | grep -v indirect | grep -i alias | awk '{print $4}'`
if [[ $? -ge 4 ]]; then
  echo "Failed to execute db2 command"
  echo "$db_list";
  exit 8
fi

cnt=0
while read -r dbase
 do
    ((cnt++))
    echo ""
    echo "----> working with database: $dbase"

    db2 connect to $dbase >/dev/null 2>&1
    #db2 connect to $dbase;
    if [[ $? -ge 4 ]]; then
      echo "Failed to connect to $dbase"
    fi

    #-------------------------------------------------
    # actions to be executed in the current database
    #-------------------------------------------------

    db2 "CREATE UNIQUE INDEX ABS.XBN1_WOHNUNG_2 ON ABS.TBN1_WOHNUNG (WOHNUNG# ASC)" ;      

    #-------------------------------------------------
    #-------------------------------------------------

 
    db2 terminate;
    if [[ $? -ge 4 ]]; then
      echo "Failed to disconnect from $dbase"
      exit 8
    fi

 done <<< "$db_list"

echo "----> processed $cnt databases."

