#!/bin/bash	
#
# DB2  Diag log handling on instance level
#
#  Archive active db2diag.log
#  Makes a db2diag log report in /home/<instance>/sqllib/db2dump directory
#  Clean up db2 diag log archive & reports in /home/<instance>/sqllib/db2dump directory
#  Clean up bin files in /home/<instance>/sqllib/db2dump directory
#
#  Execution : db2_diaglog_handling.sh <instance> 
#

# Preparing DB2 env

us=$(whoami)

echo $us
echo "Running in instance "$1

#if [[ $us =~ "db2bnl"[.]"1" ]];then
#  echo "User $us no instance owner"
#  exit 5
#else
#  echo "User $us is instance owner"
#  if [[ -x "/home/$us/sqllib/db2profile" ]];then
#    echo "db2profile existing"
#    source /home/$us/sqllib/db2profile
#    else echo "db2profile not existing"
#  fi
#fi

if [[ -x "/home/$1/sqllib/db2profile" ]];then
  echo "db2profile existing"
  source /home/$1/sqllib/db2profile
  else echo "/home/$1/sqllib/db2profile not existing"
  exit 5 
fi
 
set -x
tmpdir="/tmp"
tmp1="$tmpdir/$$.tmp1"
tmp2="$tmpdir/$$.tmp2"

maxdays="14d"
retain="30"

tmp=$(db2 get dbm cfg | grep "(DIAGPATH)" | cut -f 2 -d '=')

diagdir=$(echo $tmp) 
echo 'tmp='$tmp
echo 'diagdir='$diagdir

if [[ ! -r $diagdir'db2diag.log' ]] ; then
  echo $diagdir"db2diag.log not found"
  exit 5
fi

# Archive current file
db2diag -archive $diagdir'db2diag.log'  > $tmp1

# Get path and file name
  archivelog=$(cat $tmp1 | grep "  to  " | cut -f2 -d'"')
  if [[ ! -r $archivelog ]] ; then
    echo "Archive log not found"
    echo "Check $tmp1"
#    rm $tmp1
    exit 5 
  fi
set +x

  ts1=""
  filename=$archivelog
  ts3=""
  logpath=""
  while [[ $ts1 != $filename ]] ; do
    ts1=$filename
    filename=$(echo $ts1 | cut -f2- -d'/')
    ts3=$(echo $ts1 | cut -f1 -d'/') 
    if [[ $ts3 != "" && $filename != $ts3 ]] ; then
      logpath="$logpath/$ts3"
    fi
  done
  ext=$(echo $filename | cut -f2 -d'_')

  log="$logpath/diaglog_report_$ext.out"
  echo $log

  echo ""                              > $log
  echo "  DB2 Diagnostics Log Report" >> $log
  echo "  ==========================" >> $log
  echo "" >> $log
  echo "    Current db2diag.log archived to $filename" >> $log
  echo "" >> $log

  db2diag $archivelog -H $maxdays  -fmt "%{ts}" > $tmp1
  ts=$(head -1 $tmp1)
  echo "    First message :- ${ts}" >> $log
  ts=$(tail -1 $tmp1)
  echo "    Last message  :- ${ts}"  >> $log

# Check error levels included

  db2diag $archivelog -H $maxdays  -fmt "%level" > $tmp1
  sort -u -o $tmp2 $tmp1
  while read level; do
    if [[ $level != "" ]] ; then
      if [[ $level != "Info"    && $level != "Event"  && 
            $level != "Warning" && $level != "Error"  && 
            $level != "Severe"  && $level != "Critical" ]] ; then
        echo "" >> $log
        echo "Unknown error level of $level found" >> $log
      fi
    fi
  done < $tmp2

# Message count by severity level

  echo "" >> $log
  echo "  Total messages by severity level" >> $log
  echo "  --------------------------------" >> $log
  echo "" >> $log
  
  errors=0
  db2diag $archivelog -H $maxdays -l Critical -c > $tmp1
  errors=`cat $tmp1 | grep "matches" | cut -f2 -d' '`
  echo "       Critical: $errors" >> $log
  sevcount=$errors
 
  errors=0
  db2diag $archivelog -H $maxdays -l Severe -c > $tmp1
  errors=`cat $tmp1 | grep "matches" | cut -f2 -d' '`
  echo "       Severe: $errors" >> $log
  sevcount=$errors

  errors=0
  db2diag $archivelog -H $maxdays -l Error -c > $tmp1
  errors=`cat $tmp1 | grep "matches" | cut -f2 -d' '`
  echo "        Error: $errors" >> $log
  sevcount=$errors

  errors=0
  db2diag $archivelog -H $maxdays -l Warning -c > $tmp1
  errors=`cat $tmp1 | grep "matches" | cut -f2 -d' '`
  echo "      Warning: $errors" >> $log
  sevcount=$errors

# All severe errors
#  TIP: look at ## to navigate through report
 
  if [[ $sevcount -gt 0 ]] ; then

    echo "" >> $log
    echo "  Severe Errors " >> $log
    echo "  --------------" >> $log
    echo "" >> $log

    db2diag $archivelog -H $maxdays -l "Severe" -fmt "%inst $ %db" > $tmp1
    sort -u -o $tmp2 $tmp1 
    while read line ; do
      if [[ $line != "" ]] ; then
        instance=`echo "$line" | cut -f1 -d'$'`
        db=`echo "$line" | cut -f2 -d'$' | sed 's/ //g'`
        if [[ $instance != "" && $db != "" ]] ; then
          echo "  ##"  >> $log
          echo "  ##  Instance: $instance Database: $db " >> $log
          echo "  ##" >> $log
          echo "" >> $log
          filter="level=severe, inst=$instance, db=$db"
#          format="%tsday/%tsmonth %tshour:%tsmin \n    Message: %msg \n    RC: %rc \n"
#          db2diag $archivelog -H $maxdays -g "$filter" -fmt "$format" >> $log
          db2diag $archivelog -H $maxdays -gi "$filter" >> $log
        fi
        if [[ $instance != "" && $db = "" ]] ; then
          echo "  ##"  >> $log
          echo "  ##  Instance: $instance " >> $log
          echo "  ##" >> $log
          echo "" >> $log
          filter="level=severe, inst=$instance"
          db2diag $archivelog -H $maxdays -gi "$filter" >> $log
        fi
      fi
    done < $tmp2

    echo "" >> $log
    echo "  Common Errors " >> $log
    echo "  --------------" >> $log
    echo "" >> $log

    db2diag $archivelog -H $maxdays -l "Error" -fmt "%inst $ %db" > $tmp1
    sort -u -o $tmp2 $tmp1 
    while read line ; do
      if [[ $line != "" ]] ; then
        instance=`echo "$line" | cut -f1 -d'$'`
        db=`echo "$line" | cut -f2 -d'$' | sed 's/ //g'`
        if [[ $instance != "" && $db != "" ]] ; then
          echo "  ##"  >> $log
          echo "  ##  Instance: $instance Database: $db " >> $log
          echo "  ##" >> $log
          echo "" >> $log
          filter="level=error, inst=$instance, db=$db"
#          format="%tsday/%tsmonth %tshour:%tsmin \n    Message: %msg \n    RC: %rc \n"
#          db2diag $archivelog -H $maxdays -g "$filter" -fmt "$format" >> $log
          db2diag $archivelog -H $maxdays -gi "$filter" >> $log
        fi
        if [[ $instance != "" && $db = "" ]] ; then
          echo "  ##"  >> $log
          echo "  ##  Instance: $instance " >> $log
          echo "  ##" >> $log
          echo "" >> $log
          filter="level=error, inst=$instance"
          db2diag $archivelog -H $maxdays -gi "$filter" >> $log
        fi
      fi
    done < $tmp2
  fi

  echo ""  >> $log
  echo "End of Report" >> $log

# Delete old archives

  find $logpath -name 'db2diag.log_*' -mtime +$retain -exec rm {} \;
  find $logpath -name 'diaglog_report_*' -mtime +$retain -exec rm {} \;
  find $logpath -name '*.bin' -mtime +$retain -exec rm {} \;

# cat $log
#  rm $tmp1
#  rm $tmp2




