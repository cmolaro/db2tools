#!/bin/ksh
#
# Script     : db2_availibility.sh
# Description: Return the overall state of the database(s)
#
#<header>
#
# Remarks   : Parameters:
#   * Mandatory
#       -I | --instance   : Instance name
#
#   * Optional
#       -D | --database   : (List of space separated) Database name(s); when
#                             omitted all databases within the instance are
#                             handled, e.g. "DB01 DB02"
#       -U | --user       : User name to connect to the database
#       -P | --password   : The password matching the user name to connect
#                             to the database
#       -X | --exclude    : Database name (or grep pattern); database(s) to
#                             exclude from this script. Not applicable
#                             when the script is initiated for a single database
#       -q | --quiet      : Quiet - show no messages
#       -h | -H | --help  : Help
#
#</header>

#
# Constants
#
typeset    cCmdSwitchesShort="I:D:U:P:X:qhH"
typeset -l cCmdSwitchesLong="instance:,database:,user:,password:,exclude:,quiet,help"
typeset    cHostName=$( hostname )
typeset    cScriptName="${0}"
typeset    cBaseNameScript=$( basename ${cScriptName} )
typeset    cScriptDir="${cScriptName%/*}"
typeset    cBaseNameConfig="${cBaseNameScript%.*}.cfg"
typeset    cConfigName="${cScriptDir}/${cBaseNameConfig}"
typeset    cCurrentDir=$( pwd )
typeset    cLogsDirBase="/shared/db2/logs/${cBaseNameScript%.*}/${cHostName}"
typeset    cMasking="0002"

typeset    cSshOptions="-o BatchMode=yes -o StrictHostKeychecking=no"

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

  function getMaintenanceGroups {

    typeset lHostName="${1}"
    typeset lInstance="${2}"

    typeset lReturnedText=""
    typeset lReturnedStatus=0

    lReturnedText=$( db2 get dbm cfg 2>&1 )
    lReturnedStatus=$?
    if [ ${lReturnedStatus} -eq 0 ] ; then
      lReturnedText=$(   echo "${lReturnedText}" \
                       | grep -i '_GROUP' \
                       | awk -F'=' '{print $2}' \
                       | tr -d ' ' \
                       | sort -u \
                       | grep -v '^$' )
    else
      lReturnedText=""
    fi
    set +x
    echo ${lReturnedText}
    return lReturnedStatus

  }

  function getActivationStatus {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"
    typeset lSuNeeded="${4}"
    typeset lSshNeeded="${5}"

    typeset lReturnedText=""
    typeset lReturnedStatus=0

    [[ "${lSshNeeded}" != "YES" ]] && lSshNeeded="NO"

    typeset lCheckmkServiceName="Activation_status_${lHostName}_${lInstance}_${lDatabase}"
    typeset lDbCmd="db2pd -d ${lDatabase} -bufferpools | awk '1,/^$/' | grep -v '^$' | head -1"
    typeset lStatusInfo=""
    typeset lStatusText="UNKNOWN"

    if [ "${lSuNeeded}" == "NO" -a "${lSshNeeded}" == "NO" ] ; then
     lStatusInfo=$( eval ${lDbCmd} )
    elif [ "${lSuNeeded}" == "YES" ] ; then
      lStatusInfo=$( su -c "${lDbCmd}" ${lInstance} )
    elif [ "${lSshNeeded}" == "YES" ] ; then
      lStatusInfo=$( ssh ${cSshOptions} ${lInstance}@localhost "${lDbCmd}" )
    fi

    lReturnedStatus=3
    lReturnedText="is in an UNKNOWN state."
    if [ $( echo ${lStatusInfo} | grep -i ' not activated ' | wc -l ) -gt 0 ] ; then
      lReturnedStatus=2
      lStatusText="CRITICAL"
      lReturnedText="is INACTIVE."
    elif [ $( echo ${lStatusInfo} | grep -i ' active ' | wc -l ) -gt 0 ] ; then
      lReturnedStatus=0
      lStatusText="OK"
      lReturnedText="is active"
    fi
    echo "${lReturnedStatus} ${lCheckmkServiceName} activation_status=${lReturnedStatus};;2 ${lStatusText} - ${lDatabase} ${lReturnedText}"

    set +x
    return ${lReturnedStatus}
  }

  function getQuiesceStatus {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"
    typeset lSuNeeded="${4}"
    typeset lSshNeeded="${5}"

    typeset lReturnedText=""
    typeset lReturnedStatus=0

    [[ "${lSshNeeded}" != "YES" ]] && lSshNeeded="NO"

    typeset lCheckmkServiceName="Quiesce_status_${lHostName}_${lInstance}_${lDatabase}"
    typeset lDbCmd="db2pd -d ${lDatabase} -bufferpools | awk '1,/^$/' | grep -v '^$' | head -1"
    typeset lStatusInfo=""
    typeset lStatusText="UNKNOWN"

    if [ "${lSuNeeded}" == "NO" -a "${lSshNeeded}" == "NO" ] ; then
     lStatusInfo=$( eval ${lDbCmd} )
    elif [ "${lSuNeeded}" == "YES" ] ; then
      lStatusInfo=$( su -c "${lDbCmd}" ${lInstance} )
    elif [ "${lSshNeeded}" == "YES" ] ; then
      lStatusInfo=$( ssh ${cSshOptions} ${lInstance}@localhost "${lDbCmd}" )
    fi

    lReturnedStatus=3
    lReturnedText="is in an UNKNOWN state."
    if [ $( echo ${lStatusInfo} | grep -i ' not activated ' | wc -l ) -eq 0 ] ; then
      lReturnedStatus=2
      lStatusText="CRITICAL"
      lReturnedText="is QUIESCEd."
      if [ $( echo ${lStatusInfo} | grep -i ' Quiesce[d]* ' | grep -v '^$' | wc -l ) -eq 0 ] ; then
        lReturnedStatus=0
        lStatusText="OK"
        lReturnedText="is not quiesced."
        if [ $( db2pd -d ${lDbToHandle} -utilities | grep -i ' BACKUP ' | grep -v '^$' | wc -l ) -gt 0 ] ; then
          lReturnedStatus=1
          lStatusText="WARNING"
          lReturnedText="is QUIESCEd as part of a backup".
        fi
      fi
    fi
    echo "${lReturnedStatus} ${lCheckmkServiceName} quiesce_status=${lReturnedStatus};1;2 ${lStatusText} - ${lDatabase} ${lReturnedText}"

    set +x
    return ${lReturnedStatus}
  }

#
# Primary initialization of commonly used variables
#
typeset    lTimestampToday=$( date "+%Y-%m-%d-%H.%M.%S" )
typeset -l lInstance=""
typeset -u lDatabase=""
typeset -u lExcludedDatabase="^$"
typeset    lUsername=""
typeset    lPassword=""
typeset -u lVerbose="YES"
typeset -i lStatus=0
typeset -i lReturnCode=0

#
# Loading libraries
#
[[ $# -gt 0 && ! -f ${cScriptDir}/common_functions.include ]] && gErrorNo=2 && gMessage="Cannot load ${cScriptDir}/common_functions.include" && scriptUsage
. ${cScriptDir}/common_functions.include
[[ ! -f ${cScriptDir}/db2_common_functions.include ]] && gErrorNo=2 && gMessage="Cannot load ${cScriptDir}/db2_common_functions.include" && scriptUsage
. ${cScriptDir}/db2_common_functions.include

#
# If the script is launched without any parameter, then cycle through all
#   server instances and run the script for each instance
#
if [ $# -eq 0 ]; then
  fetchAllDb2Instances
  #
  # Are we dealing with an instance owner? If not, sniff out all server
  #   instances and get information of each and every one of them.
  #   In the other case, just continue the normal flow of the script.
  #
  if [ $( echo "${gDb2InstancesList}" | grep "^${USER}$" | wc -l ) -eq 0 ] ; then
    for lInstanceToHandle in ${gDb2InstancesList}
    do
      # Run in the background
      (
        lReturnedText=$( ${cScriptName} --instance ${lInstanceToHandle} 2>&1 )
        lReturnCode=$?
        if [ ${lReturnCode} -eq 0 ] ; then
          echo "${lReturnedText}"
        fi
      ) 2>&1 &
    done
    # Wait for all executions-per-instance to return
    wait
    set +x
    exit 0
  else
    eval set -- $( echo "--instance ${USER}" )
  fi
fi

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
      -X | --exclude )
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
# Force variable(s) to values within boundaries and set a default when needed
#
[[ "${lVerbose}" != "NO" ]] && lVerbose="YES"

#
# Make sure logging can be done properly
#
  # Nothing to log

#
# Load Db2 library
#
  # Only load when not yet done
if [ -z "${IBM_DB_HOME}" -o "${DB2INSTANCE}" != "${lInstance}" ] ; then
  if [ $( cd ~${lInstance} 2>&1 | grep 'No such' | grep -v '^$' | wc -l ) -gt 1 ] ; then
    lDb2Profile="$( grep '^${lInstance}:'  /etc/passwd | cut -d ':' -f 6 )/sqllib/db2profile"
  else
    lDb2Profile=~${lInstance}/sqllib/db2profile
  fi
  [[ ! -f ${lDb2Profile} ]] && gErrorNo=2 && gMessage="Cannot load ${lDb2Profile}" && scriptUsage
  . ${lDb2Profile}
fi

#
# Validate the input data
#
if [ "${lDatabase}" != "" ] ; then
  for lDbToHandle in ${lDatabase}
  do
    gDatabase="${lDatabase}"
    isDb2DbLocal
    lReturnCode=$?
    if [ ${lReturnCode} -ne 0 ] ; then
      gErrorNo=5
      gMessage="The database ${lDatabase} isn't defined local"
      scriptUsage
    fi
  done
  if [ $( echo ${lDatabaseList} | grep ' ' | wc -l ) -gt 0 ] ; then
    lDatabaseList=$(   echo "${lDatabase}" \
                     | tr ' ' '\n' \
                     | egrep -v "${lExcludedDatabase}" )
  else
    lDatabaseList=${lDatabase}
    lExcludedDatabase="^$"
  fi
else
  fetchAllDb2Databases
  lDatabaseList=$(   echo "${gDb2DatabaseList}" \
                   | egrep -v "${lExcludedDatabase}" )
fi

#
# Set default umask
#
umask ${cMasking}

#
# Main - Get to work
#
typeset    lReturnedText
typeset -i lReturnedStatus
typeset -u lSshNeeded="NO"
typeset -u lSuNeeded="NO"
typeset -u lUserGroups=$( groups )
typeset -u lMaintenanceGroups

if [ "${USER}" == "root" ] ; then
  lSuNeeded="YES"
else
  lMaintenanceGroups=$( getMaintenanceGroups "${cHostName}" "${lInstance}" )
  lReturnedStatus=$?
  if [ ${lReturnedStatus} -ne 0 ] ; then
    lSshNeeded="YES"
  else
    lSshNeeded="YES"
    for lGroupToCheck in ${lMaintenanceGroups}
    do
      if [ $( echo " ${lUserGroups} " | grep " ${lGroupToCheck} " | wc -l ) -gt 0 ] ; then
        lSshNeeded="NO"
      fi
      if [ "${lSshNeeded}" == "NO" ] ; then
        break 1
      fi
    done
  fi
fi

for lDbToHandle in ${lDatabaseList}
do
  lReturnedText=$( getActivationStatus "${cHostName}" "${lInstance}" "${lDbToHandle}" "${lSuNeeded}" "${lSshNeeded}" )
  lReturnedStatus=$?
  echo "${lReturnedText}"

  lReturnedText=$( getQuiesceStatus "${cHostName}" "${lInstance}" "${lDbToHandle}" "${lSuNeeded}" "${lSshNeeded}" )
  lReturnedStatus=$?
  echo "${lReturnedText}"

done

#
# Finish up
#
set +x
return 0
