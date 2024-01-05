#!/bin/bash
#
# Backup management script - force offline backup
# Cristian Molaro
#
# Usage: db2_force_offline_backup.sh <dbname> 
#
# -----------------------------------------------------------------------
# -----------------------------------------------------------------------
# Features:
# --------
#  -> Wait and retry up to 10 times 
#  -> Sleeptime decreases geometrically from 20 to 1 second 
# -----------------------------------------------------------------------
#  05082020 ! CMO ! First version
## -----------------------------------------------------------------------

backup=""
loop=10
msleep=20
# =======================================================
echo "Forcing applications for database $1";
# =======================================================
db2_app_list=`db2 list applications show detail | grep -i $1 | sed -e 's/ [a-zA-Z0-9*]/;&/g;s/ //g' | cut -d ';' -f 3`
#echo "list= $db2_app_list"
if [ -z "$db2_app_list" ]; then
  echo "No connections found"
else
  while read -r db2_app
    do
      ((cnt++))
      #echo "----> working with app: $db2_app"
      db2 +o -x "force applications ($db2_app) ";
    done <<< "$db2_app_list"
  echo "Processed $cnt applications on database $1."
  cnt=0
fi
# =======================================================
echo "Prepare database $1 for backup";
# =======================================================
db2 +o connect to $1
db2 quiesce database immediate force connections
db2 terminate
db2 deactivate database $1
# =======================================================
echo "Check:"
# =======================================================
db2pd -db $1 -app | tail -n +2 | head -n1
# =======================================================
echo "Backup for database $1";
# =======================================================
db2 backup database $1 to /shared/db2/backups/$HOSTNAME compress without prompting;
if [[ $? -gt 0 ]]; then
  backup="KO"
  echo "Entering retry loop"
fi
 
 while [ "$backup" == "KO" ]; do 
   let cnt=cnt+1
   echo "The retry counter is $cnt";
   if [ "$cnt" -gt "$loop" ]; then
      echo "==> Giving up"
      backup="ABORT" 
   fi
   nsleep=$((msleep/cnt ))
   echo "Sleeping $nsleep seconds"; sleep $nsleep; echo "Trying again";

   # =======================================================
   db2_app_list=`db2 list applications show detail | grep -i $1 | sed -e 's/ [a-zA-Z0-9*]/;&/g;s/ //g' | cut -d ';' -f 3`
   #echo "list= $db2_app_list"
   if [ -z "$db2_app_list" ]; then
     echo "No connections found"
   else
     while read -r db2_app
       do
         ((cnt++))
         #echo "----> working with app: $db2_app"
         db2 +o -x "force applications ($db2_app) ";
       done <<< "$db2_app_list"
     echo "Processed $cnt applications on database $1."
     cnt=0
   fi
   db2 backup database $1 to /shared/db2/backups/$HOSTNAME compress without prompting;
   if [[ $? -eq 0 ]]; then
  # if [[ $? -eq 1 ]]; then
     backup=""
     echo "Backup = OK!"
   fi
 done
# =======================================================
echo "Aftercare for database $1";
# =======================================================
db2 activate database $1
db2 +o connect to $1
db2 unquiesce database
db2 terminate
# =======================================================
echo "Check:"
# =======================================================
db2pd -db $1 -app | tail -n +2 | head -n1
 
if [ "$backup" != "" ]; then
  echo " === ERROR === "
  exit 1
else
  echo " === ALL FINE === "
  exit 0
fi
exit 0
