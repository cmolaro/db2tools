#!/bin/bash
# 
# Backup management script
# Cristian Molaro 
#
# -----------------------------------------------------------------------
# -----------------------------------------------------------------------
# Features:
# --------
#  -> check all the databases in the instance
#  -> Enforce these defaults:
#       - Retention = 3 days
#       - Longher retention based on database properties
#          - This is set in the database comments
#  -> Indentifies the backup type:
#       - Full online backup
#       - Full offline backup --> enforces Quiesce + Force of connections
# -----------------------------------------------------------------------
#set -x
. $HOME/.bash_profile

# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

clear;
# default backup retention, in days
back_ret=1;

# -----------------------------------------------------------------------
# Collect the database names from the instabnce: ONLY LOCAL databases
# -----------------------------------------------------------------------
echo "db2_instance=$DB2INSTANCE"
db_list=`db2 list database directory  | grep -B6 -i indirect | grep "Database name" | awk '{print $4}'`
#db_list=`db2 list db directory | grep -v indirect | grep -i alias | awk '{print $4}'`
#set +x

if [[ $? -ge 4 ]]; then
  echo "Failed to execute db2 command"
  echo "database_list=$db_list";
  exit 8
fi
 
# -----------------------------------------------------------------------
# Loop into the list of databases 
# -----------------------------------------------------------------------
cnt=0
while read -r dbase
 do
    ((cnt++))
    echo ""
    echo "====================================="
    echo "   Working with database: $dbase"
    echo "====================================="

    db2 connect to $dbase >/dev/null 2>&1
    if [[ $? -ge 4 ]]; then
      echo "Failed to connect to $dbase"
      exit 8
    fi

    # -----------------------------------------------------------------------
    # actions to be executed in the current database
    # -----------------------------------------------------------------------
     
    # --> get database comment information
    db_comment=`db2 list database directory  | grep -A5 -i $dbase | grep "Comment" | awk '{$1=$2="";print $0}'`
    db_comm[$cnt]=$db_comment
    echo "  - Database comment: "$db_comment
    back_ret=1;
    if [[ $dbase  == *DGBN* ]]; then
      back_ret=15 
    fi
    if [[ $dbase  == *DPBN* ]]; then
      back_ret=10 
    fi
    if [[ $dbase  == *DTBNB0* ]]; then
      back_ret=3 
    fi

    db2 "change database $dbase comment with 'BACKUP RET=$back_ret'" >/dev/null 2>&1;

    # --> change retention 
    echo "  - Update database backup retention to: "$back_ret
    db2 -x "update db cfg for $dbase using REC_HIS_RETENTN 366" >/dev/null 2>&1;
    db2 -x "update db cfg for $dbase using NUM_DB_BACKUPS $back_ret" >/dev/null 2>&1;
    db2 -x "update db cfg for $dbase using AUTO_DEL_REC_OBJ on" >/dev/null 2>&1;
    db2 -x "update db cfg for $dbase using STMTHEAP AUTOMATIC" >/dev/null 2>&1;

    # --> online or offline backup?
    logmeth=`db2 -x "select substr(value,1,15) from sysibmadm.dbcfg cfg where name = 'logarchmeth1'" `
    echo "  - logarchmeth1 = " $logmeth ;
    if [ $logmeth  = "LOGRETAIN" ]; then
        # -----------------------
        # ONLINE BACKUP 
        # -----------------------
        echo "  - ONLINE backup selected"
        db2_out=`db2 backup database $dbase online to /shared/db2/backups compress include logs without prompting`
        echo "    -> $db2_out"
      else
        # -----------------------
        # OFFLINE BACKUP 
        # -----------------------
        echo "  - OFFLINE backup selected"
        db2_out=`db2 quiesce database immediate force connections`
        echo "    -> $db2_out"
        db2_out=`db2 connect reset`
        echo "    -> $db2_out"
        echo "    -> Forcing applications for database $dbase";
        db2 list applications | grep $dbase | awk -F' ' '{print $3}' > /tmp/force.db2.applications.$dbase
        while read -r db2_app
          do
            echo ""
            echo "      => Working with app: $db2_app"
            db2_out=`force applications ( $db2_app )`
            echo "      => $db2_out"
          done < /tmp/force.db2.applications.$dbase
        db2_out=`db2 backup database $dbase to /shared/db2/backups compress without prompting | xargs`
        echo "    -> $db2_out" 
        db2 connect to $dbase >/dev/null 2>&1
        if [[ $? -ge 4 ]]; then
          echo "Failed to connect to $dbase"
        fi
        db2_out=`db2 unquiesce database`
        echo "    -> $db2_out"
        rm /tmp/force.db2.applications.$dbase
      fi
    # -----------------------------------------------------------------------
 
    db2 terminate >/dev/null 2>&1;
    if [[ $? -ge 4 ]]; then
      echo "Failed to disconnect from $dbase"
      exit 8
    fi

 done <<< "$db_list"

echo "----> processed $cnt databases."

