#!/bin/bash
# Mass rebind
# usage : <instance owner> <database>

us=$1

echo $us

if [[ -x "/home/$us/sqllib/db2profile" ]];then
  echo "db2profile existing"
  source /home/$us/sqllib/db2profile
  else echo "db2profile not existing"
  exit 5
fi

umask 022

    echo "----> working with database: $2"

    db2 connect to $2 >/dev/null 2>&1
    if [[ $? -ge 4 ]]; then
      echo "Failed to connect to $2"
    fi

array=( 

/shared/av/prod/bnl/brprod/dbrm/

)


for i in "${array[@]}"
do

   for b in $i*
   do

        OUT=`db2 "bind $b action replace collection XXX qualifier XXX funcpath SYSFUN,XXX validate bind isolation cs datetime iso sqlerror nopackage dynamicrules run explain no" `
    
    if [[ $? -ge 4 ]]; then
      echo ""
      echo "Bind error with $b"
      echo  "$OUT"
    else 
      echo "Bind OK with $b"
    fi
        OUT=`db2 "bind $b action replace collection XXXX qualifier XXXX funcpath SYSFUN,XXXX validate bind isolation cs datetime iso
sqlerror nopackage dynamicrules run explain no" `

    if [[ $? -ge 4 ]]; then
      echo ""
      echo "Bind error with $b"
      echo  "$OUT"
    else
      echo "Bind OK with $b"
    fi

   done
done

