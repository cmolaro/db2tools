#!/bin/bash
echo "Forcing applications for database $1";

db2_app_list=`db2 list applications | grep -i $1 | sed -e 's/ [a-zA-Z0-9*]/;&/g;s/ //g' | cut -d ';' -f 3`

#echo "list= $db2_app_list"
if [ -z "$db2_app_list" ]; then
 echo "No connections found"
 exit
fi
 
while read -r db2_app
 do
    ((cnt++))
    # echo ""
    # echo "----> working with app: $db2_app"
    db2 -x "force applications ($db2_app) ";
 done <<< "$db2_app_list"

echo "----> processed $cnt applications on database $1."


