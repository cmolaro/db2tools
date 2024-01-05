#!/bin/ksh
#
# Script     : db2_delete_stats.sh
# Description: After stats get imported into Performance Warehouse, data gets deleted into operational database
#
#<header>
#
# Remarks   : Parameters:
#   * Mandatory
#       -I | --instance   : Instance name
#       -D | --database   : Database name
#
#   * Optional
#       -U | --user       : User name to connect to the database
#       -P | --password   : The password matching the user name to connect
#                             to the database
#       -q | --quiet      : Quiet - show no messages
#       -h | -H | --help  : Help
#
#</header>

#
# Constants
#
typeset    cCmdSwitchesShort="I:D:U:P:qhH"
typeset -l cCmdSwitchesLong="instance:,database:,user:,password:,quiet,help"
typeset    cHostName=$( hostname )
typeset    cScriptName="${0}"
typeset    cBaseNameScript=$( basename ${cScriptName} )
typeset    cScriptDir="${cScriptName%/*}"
typeset    cCurrentDir=$( pwd )
typeset    cLogsDirBase="/shared/db2/logs/${cBaseNameScript%.*}/${cHostName}"
typeset    cDb2CommonSecurityGroup="db2admx"
typeset    cMasking="0002"

[[ "${cScriptDir}" == "." ]] && cScriptDir="${cCurrentDir}"

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
                  | sed 's/,$//g;  s/ //g' )
    lHeader=$(   sed -n ${lHeaderPos}p ${cScriptName} \
               | egrep -v '<[/]*header>|ksh|Description' \
               | uniq \
               | sed 's/^#//g; s/^[ ]*Remarks[ ]*://g' )

    gMessage="${lHeader}"
    [[ "${lExitScript}" == "YES" ]] && gMessage=$( printf "${lHeader}\n\nExiting.\n" )
    showMessage

    set +x
    [[ "${lExitScript}" == "YES" ]] && exit ${gErrorNo}
    return ${gErrorNo}

  }

  function doDeleteIndepentTable {

    typeset    lTable="${1}"
    typeset    lTimestampField="${2}"
    typeset    lDaysAgo="${3}"
    typeset    lWhereClause=" where ${lTimestampField} < current timestamp - ${lDaysAgo} days"
    typeset    lReturnedText=""
    typeset -i lReturnedCode
    typeset -i lAmountRecords
    typeset -u lReturnedErrors=""

    lAmountRecords=$( db2 -x "select count(*) from ${lTable} ${lWhereClause} with UR" )
    lReturnedCode=$?
    if [[ ${lReturnedCode} -gt 1 ]]; then
      lReturnedErrors=$(   echo "${lReturnedText}" \
                         | grep '^SQL[0-9][0-9]*[NW]' \
                         | cut -d ' ' -f 1
                       )
      if [ "${lReturnedErrors}" != "SQL0100W" ] ; then
        echo "Failed select table ${lTable}"
        exit 8
      else
        echo "Non-blocking warning on table ${lTable}. Continuing."
      fi
    fi
 

    lReturnedText=$( db2 -v "delete from ${lTable} ${lWhereClause}" )
    lReturnedCode=$?

    if [[ ${lReturnedCode} -gt 1 ]]; then
      lReturnedErrors=$(   echo "${lReturnedText}" \
                         | grep '^SQL[0-9][0-9]*[NW]' \
                         | cut -d ' ' -f 1
                       )
      if [ "${lReturnedErrors}" != "SQL0100W" ] ; then
        echo "Failed delete table ${lTable}"
        exit 8
      else
        echo "Non-blocking warning on table ${lTable}. Continuing."
      fi
    else
        echo "${lAmountRecords} records are deleted from ${lTable}" 
    fi
    set +x
    return 0

  }


  function doDeleteDepentTable {

    typeset    lTable="${1}"
    typeset    lTimestampField="${2}"
    typeset    lDaysAgo="${3}"
    typeset    lInPredicate=" select APPL_ID,ACTIVITY_ID,UOW_ID from ABSDBA.THRESHOLDVIOLATIONS_THRESHOLD_EV where ${lTimestampField} < current timestamp - ${lDaysAgo} days"
    typeset    lWhereClause=" where (APPL_ID,ACTIVITY_ID,UOW_ID) IN ( ${lInPredicate} )"
    typeset    lReturnedText=""
    typeset -i lReturnedCode
    typeset -i lAmountRecords
    typeset -u lReturnedErrors=""

    lAmountRecords=$( db2 -x "select count(*) from ${lTable} ${lWhereClause} with UR" )
    lReturnedCode=$?    
    if [[ ${lReturnedCode} -gt 1 ]]; then
      lReturnedErrors=$(   echo "${lReturnedText}" \
                         | grep '^SQL[0-9][0-9]*[NW]' \
                         | cut -d ' ' -f 1
                       )
      if [ "${lReturnedErrors}" != "SQL0100W" ] ; then
        echo "Failed select table ${lTable}"
        exit 8
      else
        echo "Non-blocking warning on table ${lTable}. Continuing."
      fi
    fi

    lReturnedText=$( db2 -v "delete from ${lTable} ${lWhereClause}" )
    lReturnedCode=$?

    if [[ ${lReturnedCode} -gt 1 ]]; then
      lReturnedErrors=$(   echo "${lReturnedText}" \
                         | grep '^SQL[0-9][0-9]*[NW]' \
                         | cut -d ' ' -f 1
                       )
      if [ "${lReturnedErrors}" != "SQL0100W" ] ; then
        echo "Failed delete table ${lTable}"
        exit 8
      else
        echo "Non-blocking warning on table ${lTable}. Continuing."
      fi
    else
        echo "${lAmountRecords} records are deleted from ${lTable}"
    fi
    set +x
    return 0

  }

#
# Primary initialization of commonly used variables
#
typeset    lTimestampToday=$( date "+%Y-%m-%d-%H.%M.%S" )
typeset -l lInstance=""
typeset -u lDatabase=""
typeset    lUsername=""
typeset    lPassword=""
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
                 | sed 's/^\(\-\-.*\)/\L\1/' \
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
    [[ "${_lCmdOption}" == "" && "${_lCmdValue}" == "" ]] && _lCmdOption="--"

    case ${_lCmdOption} in
      -I | --instance )
        lInstance="${_lCmdValue}"
        shift 2
        ;;
      -D | --database )
        lDatabase="${_lCmdValue}"
        shift 2
        ;;
      -U | --user )
        lUsername="${_lCmdValue}"
        shift 2
        ;;
      -P | --password )
        lPassword="${_lCmdValue}"
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
[[ "${lDatabase}" == "" ]] && gErrorNo=1 && gMessage="Please provide a database to do the work for" && scriptUsage

#
# Force variable(s) to values within boundaries and set a default when needed
#
[[ "${lVerbose}" != "NO" ]] && lVerbose="YES"

#
# Set default umask
#
umask ${cMasking}

#
# Make sure logging can be done properly
#
  typeset lLogOutputDir="${cLogsDirBase}/${lInstance}/${lDatabase}"
  typeset lLogOutput="${lLogOutputDir}/${lTimestampToday}_${cBaseNameScript}.log"
  mkdir -p ${lLogOutputDir} >/dev/null 2>&1
  chgrp -R ${cDb2CommonSecurityGroup} ${lLogOutputDir} >/dev/null 2>&1
  rm -f ${lLogOutput} >/dev/null 2>&1
  touch ${lLogOutput} >/dev/null 2>&1
  lReturnCode=$?
  if [ ${lReturnCode} -ne 0 ] ; then
    gErrorNo=4
    gMessage="Cannot create an outputfile ${lLogOutput}"
    scriptUsage
  else
    chgrp ${cDb2CommonSecurityGroup} ${lLogOutput}
    if [ "${lVerbose}" == "YES" ] ; then
      echo "Execution log is written to :  ${lLogOutput}"
    fi
  fi

#
# Validate the input data
#

#
# Load Db2 library
#
# Only load when not yet done
loadDb2Profile "${lInstance}"
lReturnCode=$?
[[ ! -f ${gDb2Profile} ]] && gErrorNo=2 && gMessage="Cannot load ${gDb2Profile}" && scriptUsage

#
# Main - Get to work
#
 gDatabase="${lDatabase}"
 handleDb2DbConnect
 lReturnCode=$?
 [[ ${lReturnCode} -ne 0 ]] && gErrorNo=5 && gMessage="Cannot connect to ${gDatabase}" && scriptUsage

 doDeleteIndepentTable "ABSDBA.GET_BP_CUMUL"                        "CAPTURE_TIMESTAMP" "1"
 doDeleteIndepentTable "ABSDBA.GET_DATABASE_CUMUL"                  "CAPTURE_TIMESTAMP" "1"
 doDeleteIndepentTable "ABSDBA.GET_TABLE_CUMUL"                     "CAPTURE_TIMESTAMP" "1"
 doDeleteIndepentTable "ABSDBA.GET_PKG_CACHE_STMT"                  "CAPTURE_TIMESTAMP" "1"
 doDeleteDepentTable   "ABSDBA.ACTIVITY_THRESHOLD_ACTIVI_EV"        "TIME_OF_VIOLATION" "1"
 doDeleteDepentTable   "ABSDBA.ACTIVITYMETRICS_THRESHOLD_ACTIVI_EV" "TIME_OF_VIOLATION" "1"
 doDeleteDepentTable   "ABSDBA.ACTIVITYSTMT_THRESHOLD_ACTIVI_EV"    "TIME_OF_VIOLATION" "1"
 doDeleteDepentTable   "ABSDBA.ACTIVITYVALS_THRESHOLD_ACTIVI_EV"    "TIME_OF_VIOLATION" "1"
 doDeleteIndepentTable "ABSDBA.THRESHOLDVIOLATIONS_THRESHOLD_EV"    "TIME_OF_VIOLATION" "1"
 
#
# Finish up
#
 handleDb2DbDisconnect
set +x
return 0
