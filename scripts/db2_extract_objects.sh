#!/bin/ksh
#
# Script     : db2_extract_objects.sh
# Description: Generate the DDL of a database and split into separate files
#
#<header>
#
# Remarks   : Parameters:
#   * Mandatory
#       -I | --instance   : Instance name
#
#   * Optional
#       -D | --database   : Database name; when omitted all databases within
#                             the instance are taken into consideration
#       -x | --exclude    : Database name (or grep pattern); database(s) to
#                             exclude from the backup process. Not applicable
#                             when a backup is initiated for a single database
#       -q | --quiet      : Don't show any messaging
#       -h | -H | --help  : Help
#
#</header>

#
# Constants
#
typeset    cCmdSwitchesShort="I:D:qhH"
typeset -l cCmdSwitchesLong="instance:,database:,quiet,help"
typeset    cHostName=$( hostname )
typeset    cScriptName="${0}"
typeset    cBaseNameScript=$( basename ${cScriptName} )
typeset    cScriptDir="${cScriptName%/*}"
typeset    cCurrentDir=$( pwd )
typeset    cLogsDirBase="/shared/db2/ddl/${cHostName}"
typeset    cDb2CommonSecurityGroup="db2admx"
typeset    cMasking="0002"

[[ "${cScriptDir}" == "." ]] && cScriptDir="${cCurrentDir}"

typeset -i cRetentionPeriodInDays=90

#
# Functions
#
  function scriptUsage {

    typeset    lHeader=""
    typeset    lHeaderPos=""
    typeset -u lExitScript="${1}"

    [[ "${lExitScript}" != "NO" ]] && lExitScript="YES"

    # Show the options as described above
    printf "\nUsage of the script ${cScriptName}: \n"

    [[ "${gMessage}" != "" ]] && showError
    [[ ${gErrorNo} -eq 0 ]] && gErrorNo=1

    lHeaderPos=$(   grep -n '<[/]*header>' ${cScriptName} \
                 | awk -F: '{print $1}' \
                 | sed 's/$/,/g' )
    lHeaderPos=$(   echo ${lHeaderPos} \
                  | sed 's/,$//g; s/ //g' )
    lHeader=$(   sed -n ${lHeaderPos}p ${cScriptName} \
               | egrep -v '<[/]*header>|ksh|Description' \
               | uniq \
               | sed 's/^#//g; s/^[ ]*Remarks[ ]*://g' )

    gMessage=$( printf "${lHeader}\n\nExiting.\n" )
    showMessage

    set +x
    [[ "${lExitScript}" == "YES" ]] && exit ${gErrorNo}
    return ${gErrorNo}

  }

  function cleanUpVersions {

    typeset lWorkingDir="${1}"

    if [ "${lVerbose}" == "YES" ] ; then
      echo "Cleaning up all DDL versions older than "${cRetentionPeriodInDays}" days for database ${lDbToHandle}"
      echo $( printfRepeatChar "=" 78 )
      echo "$( find ${lWorkingDir} -maxdepth 1 -mtime +${cRetentionPeriodInDays} -print \
               | sed 's/^/ - /g' )"
    fi
    find ${lWorkingDir} -maxdepth 1 -mtime +${cRetentionPeriodInDays} -exec rm -fR {} \;
    return 0

  }

  function GET_COMPLETE_DDL {
    #
    # Extraction Table definitions from DB2 catalog
    #
    #  Input: For each table db2look -e command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    for schema in $(db2 -x "select schemaname from syscat.schemata where owner like 'DB2%'")
    do
      if [ $? -gt 0 ]; then
        echo "Error selecting schema "$schema
        exit 8
      fi
      mkdir -p ${lLogOutputDir}'/COMPLETE/'$schema
      if [ $? -gt 0 ]; then
        echo "Error "$?" Making directory "${lLogOutputDir}"/COMPLETE/"$schema
        exit 8
      fi
      for table in $(db2 -x "select tabname from syscat.tables where type='T' and tabschema='"$schema"'")
      do
        if [ $? -gt 0 ]; then
          echo "Error selecting table "$table
          exit 8
        fi
        mkdir -p ${lLogOutputDir}'/COMPLETE/'$schema
        filenam=${lLogOutputDir}'/COMPLETE/'$schema'/'$table'.ddl'
        if [ "${lVerbose}" == "YES" ] ; then
          echo "Extracting DDL for "$schema"."$table" on database "${lDbToHandle}
        fi
        db2look -d ${lDbToHandle} -e -z $schema -x -t $table -o $filenam >/dev/null 2>&1
        if [ $? -gt 0 ]; then
          echo "Error extracting DDL for "$schema"."$table" on database "${lDbToHandle}
          rm -R ${lLogOutputDir}'/COMPLETE/'$schema
          break
        fi
        ( exit 0 )  # Reset $? to ZERO
      done  # for table
      ( exit 0 )  # Reset $? to ZERO
    done # for schema
  }

  function GET_TABLE_DDL {
    #
    # Extraction table info from db2 look file
    #
    #  Input: Output from db2look -cor command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    #  Script checks on following messages, to cut db2look file in pieces
    #
    #   -- DDL Statements for Foreign Keys on Table
    #   CREATE TABLE
    #
    begin=0
    cnt=0

    # Splitting file in parts

    cmd1=$(cat $inputf)

    if [[ $? -ge 4 ]]; then
      echo "Failed to execute cat"
      echo "$cmd1";
      exit 8
    fi

    mkdir -p ${lLogOutputDir}'/'TABLE

    while read -r line
     do
       ((cnt++))
       if [ "${lVerbose}" == "YES" ] ; then
         if (($cnt%10000 == 0));then
           echo "Processing "$cnt" db2look lines, extracting Table info"
         fi
       fi
       if [[ $line =~ "-- DDL Statements for Foreign Keys on Table" ]];then     # End of Table block
        begin=0
       fi
       if  [[ $line =~ [cC][rR][eE][aA][tT][eE]" "[tT][aA][bB][lL][eE] ]];then  # Begin Table definition
        tbl=`echo "$line" | sed -e 's/[tT][aA][bB][lL][eE] /./' -e 's/"//g' -e 's/ //g' -e 's/(/./g' | cut -d '.' -f 3`
        sch=`echo "$line" | sed -e 's/[tT][aA][bB][lL][eE] /./' -e 's/"//g' -e 's/ //g' -e 's/(/./g' | cut -d '.' -f 2`
        dir_out=${lLogOutputDir}'/TABLE/'$sch
        mkdir -p $dir_out
        filenam=$dir_out'/'$tbl'.ddl'
        touch $filenam
        echo "$line" >> $filenam
        begin=1
        continue
       fi
       if [[ $line =~ "--" ]];then  # Filtering
        continue
       fi
       if [[ -z "$line" ]];then     # Filtering empty lines
        continue
       fi
       if [[ $begin == 1 ]];then    # Continuation Table definition
        echo "$line" >> $filenam
       fi
     done <<< "$cmd1"
  }

  function EXEC_DB_DB2LOOK {
    #
    # Prepare inputfile to extract DB2 object definitions
    #

    if [ "${lVerbose}" == "YES" ] ; then
      echo "Starting preparing inputfile for db "$@
    fi
    lReturnedText=$( db2look -d $@  -e -cor -o ${lLogOutput} 2>&1 )
    if [ "${lVerbose}" == "YES" ] ; then
      echo "${lReturnedText}"
      echo "Inputfile prepared for db "$@
    fi
    inputf=${lLogOutput}
  }

  function GET_UDF_DDL {
    #
    # Extraction User Defined function definitions from DB2 catalog
    #
    #  Input: output from db2look -cor command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    #  Script checks on following messages, to cut db2look file in pieces
    #
    #   -- DDL Statements for
    #   -- DDL Statements for User Defined Functions
    #   CREATE OR REPLACE FUNCTION
    #   NLS_STRING_UNITS = 'SYSTEM';
    #
    startfun=0
    begin=0
    cnt=0

    # Splitting file in parts

    cmd1=$(cat $inputf)

    if [[ $? -ge 4 ]]; then
      echo "Failed to execute cat"
      echo "$cmd1";
      exit 8
    fi

    mkdir -p ${lLogOutputDir}'/'UDF

    while read -r line
     do
       ((cnt++))
       if [ "${lVerbose}" == "YES" ] ; then
         if (($cnt%10000 == 0));then
           echo "Processing "$cnt" db2look lines, extracting UDF defs"
         fi
       fi
       if [[ $line =~ "-- DDL Statements for " ]];then  # End of UDF block
        startfun=0
        begin=0
       fi
       # Begin of UDF block
       if [[ $line =~ "-- DDL Statements for User Defined Functions" ]];then
        startfun=1
       fi
       if  [[ $line =~ [cC][rR][eE][aA][tT][eE]" "[oO][rR]" "[rR][eE][pP][lL][aA][cC][eE]" "[fF][uU][nN][cC][tT][iI][oO][nN] ]];then  # Begin UDF definition
        fun=`echo "$line" | sed -e 's/[fF][uU][nN][cC][tT][iI][oO][nN] /./' -e 's/"//g' -e 's/ //g' -e 's/(/./g' | cut -d '.' -f 3`
        sch=`echo "$line" | sed -e 's/[fF][uU][nN][cC][tT][iI][oO][nN] /./' -e 's/"//g' -e 's/ //g' -e 's/(/./g' | cut -d '.' -f 2`
        if [[ $sch =~ [aA][bB][sS] ]];then
         dir_out=${lLogOutputDir}'/UDF/'$sch
         mkdir -p $dir_out
         filenam=$dir_out'/'$fun'.ddl'
         touch $filenam
         echo "$line" >> $filenam
         begin=1
         continue
        else
         echo "Unqualified UDF founded :"$sch
         dir_out=${lLogOutputDir}'/UDF/UNQUAL'
         mkdir -p $dir_out
         filenam=$dir_out'/'$sch'.ddl'
         touch $filenam
         echo "$line" >> $filenam
         begin=1
         continue
        fi
       fi
       if [[ $line =~ "NLS_STRING_UNITS = 'SYSTEM';" ]]  &&  # End UDF definition
          (( $startfun==1 ));then
        begin=0
        continue
       fi
       if [[ $line =~ "--" ]];then    # Filtering
        continue
       fi
       if [ -z "$line" ];then         # Filtering empty lines
        continue
       fi
       if (( $begin == 1 ));then      # Continuation UDF definition
        echo "$line" >> $filenam
       fi
     done <<< "$cmd1"
  }

  function GET_ROLE_DDL {
    #
    # Extraction Role definitions from DB2 catalog
    #
    #  Input: output from db2look -cor command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    #  Script checks on following messages, to cut db2look file in pieces
    #
    #   -- DDL Statements for
    #   -- DDL Statements for Roles
    #   CREATE ROLE
    #
    startblk=0
    cnt=0

    # Splitting file in parts

    cmd1=$(cat $inputf)

    if [[ $? -ge 4 ]]; then
      echo "Failed to execute cat"
      echo "$cmd1";
      exit 8
    fi

    while read -r line
     do
       ((cnt++))
       if [ "${lVerbose}" == "YES" ] ; then
         if (($cnt%10000 == 0));then
           echo "Processing "$cnt" db2look lines, extracting Role defs"
         fi
       fi
       if [[ $line =~ "-- DDL Statements for " ]] &&               # End of Role block
           [ $startblk -eq 1 ];then
        startblk=0
        if [ "${lVerbose}" == "YES" ] ; then
          echo "Roles, defined in "$@" are written into "$filenam
        fi
        break
       fi
       if [[ $line =~ "-- DDL Statements for Roles" ]];then        # Begin of Role block
        filenam=${lLogOutputDir}'/'$@'_Roles.ddl'
        touch $filenam
        echo "$line" >> $filenam
        startblk=1
        continue
       fi
       if [[ $line =~ "--" ]];then  # Filtering
        continue
       fi
       if [ -z "$line" ];then         # Filtering empty lines
        continue
       fi
       if [ $startblk -eq 1 ];then    # Continuation Role block
        echo "$line" >> $filenam
       fi
     done <<< "$cmd1"
  }

  function GET_SEQUENCE_DDL {
    #
    # Extraction sequence definitions from DB2 catalog
    #
    #  Input: output from db2look -cor command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    #  Script checks on following messages, to cut db2look file in pieces
    #
    #   -- DDL Statements for
    #   -- DDL Statements for Sequences
    #   CREATE OR REPLACE SEQUENCE
    #
    startblk=0
    cnt=0

    # Splitting file in parts

    cmd1=$(cat $inputf)

    if [[ $? -ge 4 ]]; then
      echo "Failed to execute cat"
      echo "$cmd1";
      exit 8
    fi

    while read -r line
     do
       ((cnt++))
       if [ "${lVerbose}" == "YES" ] ; then
         if (($cnt%10000 == 0));then
           echo "Processing "$cnt" db2look lines, extracting sequence defs"
         fi
       fi
       if [[ $line =~ "-- DDL Statements for " ]] &&               # End of Sequence block
           [ $startblk -eq 1 ];then
        startblk=0
        if [ "${lVerbose}" == "YES" ] ; then
          echo "Sequence, defined in "$@" are written into "$filenam
        fi
        break
       fi
       if [[ $line =~ "-- DDL Statements for Sequences" ]];then    # Begin of Sequence block
        filenam=${lLogOutputDir}'/'$@'_Sequence.ddl'
        touch $filenam
        echo "$line" >> $filenam
        startblk=1
        continue
       fi
       if [[ $line =~ "--" ]];then  # Filtering
        continue
       fi
       if [ -z "$line" ];then         # Filtering empty lines
        continue
       fi
       if [ $startblk -eq 1 ];then    # Continuation Sequence block
        echo "$line" >> $filenam
       fi
     done <<< "$cmd1"
  }

  function GET_ALIAS_DDL {
    #
    # Extraction alias definitions from DB2 catalog
    #
    #  Input: output from db2look -cor command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    #  Script checks on following messages, to cut db2look file in pieces
    #
    #   -- DDL Statements for
    #   -- DDL Statements for Aliases
    #   CREATE OR REPLACE ALIAS
    #
    startblk=0
    cnt=0

    # Splitting file in parts

    cmd1=$(cat $inputf)

    if [[ $? -ge 4 ]]; then
      echo "Failed to execute cat"
      echo "$cmd1";
      exit 8
    fi

    while read -r line
     do
       ((cnt++))
       if [ "${lVerbose}" == "YES" ] ; then
         if (($cnt%10000 == 0));then
           echo "Processing "$cnt" db2look lines, extracting alias defs"
         fi
       fi
       if [[ $line =~ "-- DDL Statements for " ]] &&               # End of Alias block
           [ $startblk -eq 1 ];then
        startblk=0
        if [ "${lVerbose}" == "YES" ] ; then
          echo "Alias, defined in "$@" are written into "$filenam
        fi
        break
       fi
       if [[ $line =~ "-- DDL Statements for Aliases" ]];then    # Begin of Alias block
        filenam=${lLogOutputDir}'/'$@'_Alias.ddl'
        touch $filenam
        echo "$line" >> $filenam
        startblk=1
        continue
       fi
       if [[ $line =~ "--" ]];then  # Filtering
        continue
       fi
       if [ -z "$line" ];then         # Filtering empty lines
        continue
       fi
       if [ $startblk -eq 1 ];then    # Continuation Alias block
        echo "$line" >> $filenam
       fi
     done <<< "$cmd1"
  }

  function GET_AUDIT_DDL {
    #
    # Extraction audit definitions from DB2 catalog
    #
    #  Input: output from db2look -cor command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    #  Script checks on following messages, to cut db2look file in pieces
    #
    #   -- DDL Statements for
    #   -- DDL Statements for Audits
    #   CREATE AUDIT POLICY
    #
    startblk=0
    cnt=0

    # Splitting file in parts

    cmd1=$(cat $inputf)

    if [[ $? -ge 4 ]]; then
      echo "Failed to execute cat"
      echo "$cmd1";
      exit 8
    fi

    while read -r line
     do
       ((cnt++))
       if [ "${lVerbose}" == "YES" ] ; then
         if (($cnt%10000 == 0));then
           echo "Processing "$cnt" db2look lines, extracting audit policy defs"
         fi
       fi
       if [[ $line =~ [cC][oO][nN][nN][eE][cC][tT]" "[rR][eE][sS][eE][tT]";" ]] &&             # End of Audit Policy block
           [ $startblk -eq 1 ];then
        startblk=0
        if [ "${lVerbose}" == "YES" ] ; then
          echo "Audit policies, defined in "$@" are written into "$filenam
        fi
        break
       fi
       if [[ $line =~ "-- DDL Statements for " ]] &&             # End of Audit Policy block
           [ $startblk -eq 1 ];then
        startblk=0
        if [ "${lVerbose}" == "YES" ] ; then
          echo "Audit policies, defined in "$@" are written into "$filenam
        fi
        break
       fi
       if [[ $line =~ "-- DDL Statements for Audits" ]];then    # Begin of Audit Policy block
        filenam=${lLogOutputDir}'/'$@'_Audit.ddl'
        touch $filenam
        echo "$line" >> $filenam
        startblk=1
        continue
       fi
       if [[ $line =~ "--" ]];then  # Filtering
        continue
       fi
       if [ -z "$line" ];then         # Filtering empty lines
        continue
       fi
       if [ $startblk -eq 1 ];then    # Continuation Audit Policy block
        echo "$line" >> $filenam
       fi
     done <<< "$cmd1"
  }

  function GET_VIEW_DDL {
    #
    # Extraction View definitions from DB2 catalog
    #
    #  Input: output from db2look -cor command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    #  Script checks on following messages, to cut db2look file in pieces
    #
    #   -- DDL Statements for
    #   -- DDL Statements for Views
    #   CREATE OR REPLACE VIEW
    #   SET CURRENT
    #
    startblk=0
    begin=0
    cnt=0

    # Splitting file in parts

    cmd1=$(cat $inputf)

    if [[ $? -ge 4 ]]; then
      echo "Failed to execute cat"
      echo "$cmd1";
      exit 8
    fi

    mkdir -p ${lLogOutputDir}'/'VIEW

    while read -r line
     do
       ((cnt++))
       if [ "${lVerbose}" == "YES" ] ; then
         if (($cnt%10000 == 0));then
           echo "Processing "$cnt" db2look lines, extracting VIEW defs"
         fi
       fi
       if [[ $line =~ "-- DDL Statements for " ]];then             # End of VIEW block
        startblk=0
        begin=0
       fi
       if [[ $line =~ "-- DDL Statements for Views" ]];then        # Begin of VIEW block
        startblk=1
       fi
       if  [[ $line =~ [cC][rR][eE][aA][tT][eE]" "[oO][rR]" "[rR][eE][pP][lL][aA][cC][eE]" "[vV][iI][eE][wW] ]];then  # Begin VIEW definition
        viw=`echo "$line" | sed -e 's/[vV][iI][eE][wW] /./;s/[aA][sS] /./;s/"//g;s/ //g;s/(/./g' | cut - d '.' -f 3`
        sch=`echo "$line" | sed -e 's/[vV][iI][eE][wW] /./;s/"//g;s/ //g;s/(/./g' | cut -d '.' -f 2 | tr 'a-z' 'A-Z'`
        [[ "${lVerbose}" == "YES" ]] && echo "schema view="$sch
        if [[ $sch =~ [Aa][Bb][Ss] ]];then
         dir_out=${lLogOutputDir}'/VIEW/'$sch
         mkdir -p $dir_out
         filenam=$dir_out'/'$viw'.ddl'
         touch $filenam
         echo "$line" >> $filenam
         begin=1
         continue
        else
         [[ "${lVerbose}" == "YES" ]] && echo "Unqualified VIEW founded :"$sch
         dir_out=${lLogOutputDir}'/VIEW/UNQUAL'
         mkdir -p $dir_out
         filenam=$dir_out'/'$sch'.ddl'
         touch $filenam
         echo "$line" >> $filenam
         begin=1
         continue
        fi
       fi
       if [[ $line =~ [sS][eE][tT]" "[cC][uU][rR][rR][eE][nN][tT] ]]  &&                            # End VIEW definition
          (( $startblk==1 ));then
        begin=0
        continue
       fi
       if [[ $line =~ "--" ]];then  # Filtering
        continue
       fi
       if [ -z "$line" ];then         # Filtering empty lines
        continue
       fi
       if (( $begin == 1 ));then      # Continuation VIEW definition
        echo "$line" >> $filenam
       fi
     done <<< "$cmd1"
  }

  function GET_SP_DDL {
    #
    # Extraction Stored Procedure definitions from DB2 catalog
    #
    #  Input: output from db2look -cor command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    #  Script checks on following messages, to cut db2look file in pieces
    #
    #   -- DDL Statements for
    #   -- DDL Statements for Stored Procedures
    #   CREATE OR REPLACE PROCEDURE
    #   NLS_STRING_UNITS = 'SYSTEM';
    #
    startblk=0
    begin=0
    cnt=0

    # Splitting file in parts

    cmd1=$(cat $inputf)

    if [[ $? -ge 4 ]]; then
      echo "Failed to execute cat"
      echo "$cmd1";
      exit 8
    fi

    mkdir -p ${lLogOutputDir}'/'SP

    while read -r line
     do
       ((cnt++))
       if [ "${lVerbose}" == "YES" ] ; then
         if (($cnt%10000 == 0 ));then
           echo "Processing "$cnt" db2look lines, extracting SP defs"
         fi
       fi
       if [[ $line =~ "-- DDL Statements for " ]];then             # End of SP block
        startblk=0
        begin=0
       fi
       if [[ $line =~ "-- DDL Statements for Stored Procedures" ]];then        # Begin of SP block
        startblk=1
       fi
       if  [[ $line =~ [cC][rR][eE][aA][tT][eE]" "[oO][rR]" "[rR][eE][pP][lL][aA][cC][eE]" "[pP][rR][oO][cC][eE][dD][uU][rR][eE] ]];then              # Begin SP definition
        spr=`echo "$line" | sed -e 's/[pP][rR][oO][cC][eE][dD][uU][rR][eE] /./;s/"//g;s/ //g;s/(/./g' | cut -d '.' -f 3`
        sch=`echo "$line" | sed -e 's/[pP][rR][oO][cC][eE][dD][uU][rR][eE] /./;s/"//g;s/ //g;s/(/./g' | cut -d '.' -f 2 | tr 'a-z' 'A-Z'`
        dir_out=${lLogOutputDir}'/SP/'$sch
        mkdir -p $dir_out
        filenam=$dir_out'/'$spr'.ddl'
        touch $filenam
        echo "$line" >> $filenam
        begin=1
        continue
       fi
       if [[ $line =~ "NLS_STRING_UNITS = 'SYSTEM';" ]]  &&  # End SP definition
          [ $startblk == 1 ];then
        begin=0
        continue
       fi
       if [[ $line =~ "--" ]];then  # Filtering
        continue
       fi
       if [ -z "$line" ];then         # Filtering empty lines
        continue
       fi
       if [ $begin == 1 ];then        # Continuation SP definition
        echo "$line" >> $filenam
       fi
     done <<< "$cmd1"
  }

  function GET_TRIGGER_DDL {
    #
    # Extraction Trigger definitions from DB2 catalog
    #
    #  Input: output from db2look -cor command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    #  Script checks on following messages, to cut db2look file in pieces
    #
    #   -- DDL Statements for
    #   -- DDL Statements for Triggers
    #   CREATE OR REPLACE TRIGGER
    #   NLS_STRING_UNITS = 'SYSTEM';
    #
    startblk=0
    begin=0
    cnt=0

    # Splitting file in parts

    cmd1=$(cat $inputf)

    if [[ $? -ge 4 ]]; then
      echo "Failed to execute cat"
      echo "$cmd1";
      exit 8
    fi

    mkdir -p ${lLogOutputDir}'/'TRIGGER

    while read -r line
     do
       ((cnt++))
       if [ "${lVerbose}" == "YES" ] ; then
         if (($cnt%10000 == 0 ));then
           echo "Processing "$cnt" db2look lines, extracting TRIGGER defs"
         fi
       fi
       if [[ $line =~ "-- DDL Statements for " ]];then             # End of Trigger block
        startblk=0
        begin=0
       fi
       if [[ $line =~ "-- DDL Statements for Triggers" ]];then        # Begin of Trigger block
        startblk=1
       fi
       if  [[ $line =~ [cC][rR][eE][aA][tT][eE]" "[oO][rR]" "[rR][eE][pP][lL][aA][cC][eE]" "[tT][rR][iI][gG][gG][eE][rR] ]];then    # Begin Trigger definition
    tri=`echo "$line" | sed -e 's/[tT][rR][iI][gG][gG][eE][rR] /./;s/[aA][fF][tT][eE][rR]/./;s/[bB][eE][fF][oO][rR][eE]/./;s/[nN][oO]/./;s/"//g;s/ //g;s/(/./g;s/\r//' | cut -d '.' -f 3`
        sch=`echo "$line" | sed -e 's/[tT][rR][iI][gG][gG][eE][rR] /./;s/"//g;s/ //g;s/(/./g' | cut -d '.' -f 2 | tr 'a-z' 'A-Z'`
        dir_out=${lLogOutputDir}'/TRIGGER/'$sch
        mkdir -p $dir_out
        filenam=$dir_out'/'$tri'.ddl'
        touch $filenam
        echo "$line" >> $filenam
        begin=1
        continue
       fi
       if [[ $line =~ "NLS_STRING_UNITS = 'SYSTEM';" ]]  &&  # End Trigger definition
          [ $startblk == 1 ];then
        begin=0
        continue
       fi
       if [[ $line =~ "--" ]];then  # Filtering
        continue
       fi
       if [ -z "$line" ];then         # Filtering empty lines
        continue
       fi
       if [ $begin == 1 ];then        # Continuation Trigger definition
        echo "$line" >> $filenam
       fi
     done <<< "$cmd1"
  }

function GET_INDX_INFO {
    #
    # Extraction index info from db2 look file
    #
    #  Input: Output from db2look -cor command
    #
    #  Output: Directory structure, starting from lLogOutputDir variable
    #
    #  Script checks on following messages, to cut db2look file in pieces
    #
    #   -- DDL Statements for
    #   -- DDL Statements for Indexes
    #   CREATE INDEX ... ON
    #
    begin=0
    cnt=0

    # Splitting file in parts

#    cmd1=$(cat $inputf)
    cmd1=$(awk '/CREATE INDEX|CREATE UNIQUE INDEX/,/;/' $inputf)

    if [[ $? -ge 4 ]]; then
      echo "Failed to execute cat"
      echo "$cmd1";
      exit 8
    fi

    mkdir -p ${lLogOutputDir}'/'INDEX

    while read -r line
     do
       ((cnt++))
       if [ "${lVerbose}" == "YES" ] ; then
         if (($cnt%10000 == 0));then
           echo "Processing "$cnt" db2look lines, extracting Index info"
         fi
       fi
       if [[ $line =~ "-- DDL Statements for " ]];then             # End of Index block
        begin=0
       fi
       if [ "$( echo $line | grep -i 'CREATE ' )" != "" ];then  # Begin Index block
        idx=`echo $line | sed -e 's/[iI][nN][dD][eE][xX] /./;s/[oO][nN] /./g;s/"//g;s/ //g;s/(/./g' | cut -d '.' -f 3`
        isc=`echo $line | sed -e 's/[iI][nN][dD][eE][xX] /./;s/"//g;s/ //g;s/(/./g' | cut -d '.' -f 2`
        dir_out=${lLogOutputDir}'/INDEX/'$isc
        mkdir -p $dir_out
        filenam=$dir_out'/'$idx'.ddl'
        touch $filenam
        echo "$line" >> $filenam
        begin=1
        continue
       fi

       if [[ $line =~ "--" ]];then  # Filtering
        continue
       fi
       if [ -z "$line" ];then         # Filtering empty lines
        continue
       fi
       if [ $begin == 1 ];then        # Continuation Index definition
        echo "$line" >> $filenam
       fi
     done <<< "$cmd1"
  }

#
# Primary initialization of commonly used variables
#
typeset    lTimestampToday=$( date "+%Y-%m-%d-%H.%M.%S" )
typeset    lDateToday=$( date "+%Y%m%d" )
typeset    lDb2Profile=""
typeset -l lInstance=""
typeset -u lDatabase=""
typeset    lDatabaseList=""
typeset    lExcludedDatabase="^$"
typeset -u lVerbose="YES"
typeset -i lReturnCode=0

#
# Loading libraries
#
[[ ! -f ${cScriptDir}/common_functions.include ]] && gErrorNo=2 && gMessage="Cannot load ${cScriptDir}/common_functions.include" && scriptUsage
. ${cScriptDir}/common_functions.include

[[ ! -f ${cScriptDir}/db2_common_functions.include ]] && gErrorNo=2 && gMessage="Cannot load ${cScriptDir}/db2_common_functions.include" && scriptUsage
. ${cScriptDir}/db2_common_functions.include

#
# Check for the input parameters
#
    # Read and perform a lowercase on all '--long' switch options, store in $@
  eval set -- $(   echo "$@" \
                 | tr ' ' '\n' \
                 | sed -e 's/^\(\-\-.*\)/\L\1/' \
                 | tr '\n' ' ' \
                 | sed 's/^[ ]*//g; s/[ ]*$/\n/g; s/|/\\|/g' )
    # Check the command line options for their correctness,
    #   throw out what is not OK and store the rest in $@
  eval set -- $( getopt --options "${cCmdSwitchesShort}" \
                        --long "${cCmdSwitchesLong}" \
                        --name "${0}" \
                        --quiet \
                        -- "$@" )
    # Initialize the option-processing variables
  typeset _lCmdOption=""
  typeset _lCmdValue=""

    # Process the options
  while [ "$#" ] ; do

    _lCmdOption="${1}"
    _lCmdValue="${2}"
    [[ "${_lCmdOption}" == "" && "${lCmdValue}" == "" ]] && _lCmdOption="--"

    case ${_lCmdOption} in
      -I | --instance )
        lInstance="${_lCmdValue}"
        shift 2
        ;;
      -D | --database )
        lDatabase="${_lCmdValue}"
        shift 2
        ;;
      -x | --exclude )
        lExcludedDatabase="${_lCmdValue}"
        shift 2
        ;;
      -q | --quiet )
        lVerbose="NO"
        shift 1
        ;;
      -- )
          # Make $@ completely empty and break the while loop
        [[ $# -gt 0 ]] && shift $#
        break
        ;;
      *)
        gMessage=""
        scriptUsage
        ;;
    esac
  done
  unset _lCmdValue
  unset _lCmdOption

#
# Check input which is mandatory
#
[[ "${lInstance}" == "" ]] && gErrorNo=1 && gMessage="Please provide an instance to do the work for" && scriptUsage

#
# Validate the input data
#
[[ "${lVerbose}" != "NO" ]] && lVerbose="YES"

#
# Set default umask
#
umask ${cMasking}

#
# Load Db2 library
#
loadDb2Profile "${lInstance}"
lReturnCode=$?
[[ ! -f ${gDb2Profile} ]] && gErrorNo=2 && gMessage="Cannot load ${gDb2Profile}" && scriptUsage

#
# Determine the database scope
#
if [ "${lDatabase}" != "" ] ; then
  gDatabase="${lDatabase}"
  isDb2DbLocal
  lReturnCode=$?
  if [ ${lReturnCode} -ne 0 ] ; then
    gErrorNo=5
    gMessage="The database ${lDatabase} isn't defined local"
    scriptUsage
  fi
  lDatabaseList=${lDatabase}
  lExcludedDatabase="^$"
else
  fetchAllDb2Databases
  lDatabaseList=$(   echo "${gDb2DatabaseList}" \
                   | egrep -v "${lExcludedDatabase}" )
fi

#
# Main - Get to work
#
for lDbToHandle in ${lDatabaseList}
do
  gDatabase="${lDbToHandle}"
  isDb2DbLocal
  lReturnCode=$?

  #
  # * Is the database is the catalog not a local one? Next!
  # * Is this a Shadow database? Next!
  #
  [[ ${lReturnCode} -ne      0 ]] && continue
  [[ ${lDbToHandle}  =~ "DSBN" ]] && continue

  #
  # Remove the copies which are too out-dated
  #
  cleanUpVersions "${cLogsDirBase}/${lInstance}/${lDbToHandle}"

  #
  # Figure out in which directory the DDL is to be kept
  #
  typeset lLogOutputDir="${cLogsDirBase}/${lInstance}/${lDbToHandle}"
  typeset lNextInLine=$(   cd ${lLogOutputDir} ;
                           ls -d -1 * \
                         | grep "^${lDateToday}_" \
                         | sort -rn \
                         | head -1 )
  if [ "${lNextInLine}" != "" ] ; then
    lNextInLine=$(( $( echo ${lNextInLine} \
                       | sed 's/\([0-9]*\)_\([0-9][0-9]*\)/\2/g' ) + 1 ))
  else
    lNextInLine=0
  fi
  lLogOutputDir=$( printf "%s_%02d" "${lLogOutputDir}/${lDateToday}" "${lNextInLine}" )

  mkdir -p ${lLogOutputDir} >/dev/null 2>&1
  lReturnCode=$?
  if [ ${lReturnCode} -gt 0 ] ; then
    gErrorNo=5
    gMessage="Error (${lReturnCode}) creating directory ${lLogOutputDir}. Exiting"
    showError
    exit ${gErrorNo}
  fi
  [[ ${USER} =~ db2 ]] & chgrp -R ${cDb2CommonSecurityGroup} ${lLogOutputDir} >/dev/null 2>&1

  #
  # Can files get dumped in this new directory?
  #
  typeset lLogOutput="${lLogOutputDir}/${lDateToday}_${lDbToHandle}_db2look.ddl"
  rm -f ${lLogOutput} >/dev/null 2>&1
  touch ${lLogOutput} >/dev/null 2>&1
  lReturnCode=$?
  if [ ${lReturnCode} -ne 0 ] ; then
    gErrorNo=4
    gMessage="Cannot create an outputfile ${lLogOutput}"
    showError
    continue  # Stop processing for this database and skip to the next
  else
    rm -f ${lLogOutput} >/dev/null 2>&1
  fi

  #
  # Still on track - connect to the database
  #
  handleDb2DbConnect
  lReturnCode=$?
  if [ ${lReturnCode} -ne 0 ] ; then
    gErrorNo=5
    gMessage="Cannot connect to ${lDbToHandle}"
    showError
    continue  # Stop processing for this database and skip to the next
  fi

  # Get DDL DB2 Objecten
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_COMPLETE_DDL"
  GET_COMPLETE_DDL
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - EXEC_DB_DB2LOOK"
  EXEC_DB_DB2LOOK ${lDbToHandle}
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_TABLE_DDL"
  GET_TABLE_DDL
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_UDF_DDL"
  GET_UDF_DDL ${lDbToHandle}
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_ROLE_DDL"
  GET_ROLE_DDL ${lDbToHandle}
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_SEQUENCE_DDL"
  GET_SEQUENCE_DDL ${lDbToHandle}
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_ALIAS_DDL"
  GET_ALIAS_DDL ${lDbToHandle}
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_AUDIT_DDL"
  GET_AUDIT_DDL ${lDbToHandle}
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_VIEW_DDL"
  GET_VIEW_DDL
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_SP_DDL"
  GET_SP_DDL
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_TRIGGER_DDL"
  GET_TRIGGER_DDL
  [[ "${lVerbose}" == "YES" ]] && echo $(date +[%T]) "${lDbToHandle} - GET_INDX_INFO"
  GET_INDX_INFO

  handleDb2DbDisconnect
  [[ ${USER} =~ db2 ]] & chgrp -R ${cDb2CommonSecurityGroup} ${lLogOutputDir} >/dev/null 2>&1
done

#
# Finish up
#
set +x
return 0
