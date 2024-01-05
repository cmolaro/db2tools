#!/bin/ksh
#
# Script     : db2_quiesce_state.sh
# Description: Return the quiesce state of the database(s)
#
#<header>
#
# Remarks   : Parameters:
#   * Mandatory
#       -I | --instance   : Instance name
#
#   * Optional
#       -D | --database   : Database name; when omitted all databases within
#                             the instance are checked
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

  function  getThresholdInHours {
    typeset lThreshold
    lThreshold=$( awk -F: -v IGNORECASE=1 "/^[^#]/&&\$1~/${1}/&&\$2~/${2}/&&\$3~/${3}/&&\$4~/${4}/{print \$5}" ${cConfigName} )
    [[ ! -z "${lThreshold}" ]] && lThresholdInHours=${lThreshold}
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
# Validate the input data
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
# Load Db2 library
#
  # Only load when not yet done
loadDb2Profile "${lInstance}"
lReturnCode=$?
[[ ! -f ${gDb2Profile} ]] && gErrorNo=2 && gMessage="Cannot load ${gDb2Profile}" && scriptUsage

#
# Main - Get to work
#

for lDbToHandle in ${lDatabaseList}
do
  lCheckmkServiceName="QscDb2:${lInstance}:${lDbToHandle}:quiesce_status"
  lStatusInfo=$( db2pd -d ${lDbToHandle} -bufferpools | awk '1,/^$/' | grep -v '^$' | head -1 )
  if [ $( echo ${lStatusInfo} | grep ' not activated ' | wc -l ) -gt 0 ] ; then
    if db2 +o connect to "${lDbToHandle}"; then
      lStatusInfo=$( db2pd -d ${lDbToHandle} -bufferpools | awk '1,/^$/' | grep -v '^$' | head -1 )
        # Disconnect from database
      db2 connect reset > /dev/null
    fi
  fi
  lQuiesceStatus=$( echo ${lStatusInfo} | grep -i ' Quiesce[d]* ' | grep -v '^$' | wc -l )
  echo "${lQuiesceStatus} ${lCheckmkServiceName}; quiesce_status=${lQuiesceStatus}; Quiesce status for this database. OK: 0, Critical: 1"
done

#
# Finish up
#
set +x
return 0
