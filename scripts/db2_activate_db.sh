#!/bin/ksh 
#
# Script     : db2_activate_db.sh
# Description: Activation DB2 databases
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
#       -X | --exclude    : Database name (or grep pattern); database(s) to
#                             exclude from this script. Not applicable
#                             when the script is initiated for a single database
#       -q | --quiet      : Quiet - show no messages
#       -h | -H | --help  : Help
#
#</header>
#set -x
#
# Constants
#
typeset    cCmdSwitchesShort="I:D:U:P:X:qhH"
typeset -l cCmdSwitchesLong="instance:,database:,user:,password:,exclude:,quiet,help"
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

#
# Primary initialization of commonly used variables
#
#typeset    lTimestampToday=$( date "+%Y-%m-%d-%H:%M" )
typeset    lTimestampToday=$( date "+%Y-%m-%d-%H.%M.%S" )
  ## typeset    lDb2Profile=""
  ## typeset    lDb2ProfileHome=""
typeset -l lInstance=""
typeset -u lDatabase=""
typeset    lUsername=""
typeset    lPassword=""
typeset -u lExcludedDatabase="^$"
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
                 | sed 's/^[ ]*//g; s/[ ]*$/\n/g; s/|/\\|/g' \
                 | sed 's:\(\-[\-]*[a-z_]*\)\( \):\1[_]:g' \
                 | sed 's:\( \)\(\-[\-]\)\([a-zA-Z0-9]\):[_]\2\3:g' \
                 | sed 's:\( \)\(\-\)\([a-zA-Z0-9]\):[_]\2\3:g' \
                 | sed 's: :[blank]:g; s:\[_\]: :g' \
               )

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
#set -x
     _lCmdOption=$( echo "${1}" | sed 's:\[blank\]: :g' | sed 's/^[ ]*//g; s/[ ]*$//g' )
     _lCmdValue=$( echo "${2}" | sed 's:\[blank\]: :g' | sed 's/^[ ]*//g; s/[ ]*$//g' )
 #    _lCmdOption="${1}"
 #    _lCmdValue="${2}"
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


#echo "Exlude db parm " ${lInstance}
echo "Exlude db parm " ${lExcludedDatabase}

#
# Check input which is mandatory
#
[[ "${lInstance}" == "" ]] && gErrorNo=1 && gMessage="Please provide an instance to do the work for" && scriptUsage
#[[ "${lDatabase}" == "" ]] && gErrorNo=1 && gMessage="Please provide a database to do the work for" && scriptUsage

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
    typeset lLogOutput="${lLogOutputDir}${lTimestampToday}.log"
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
  ##   # Only load when not yet done
   loadDb2Profile "${lInstance}"
   lReturnCode=$?
   [[ ! -f ${gDb2Profile} ]] && gErrorNo=2 && gMessage="Cannot load ${gDb2Profile}" && scriptUsage
    typeset lLogOutput="${lLogOutputDir}${lTimestampToday}.log"
  ##   # Only load when not yet done


#
# Main - Get to work
#

instance="current"
database="all"
usesudo="no"
error="continue"
exclude=""
maxcc=0
logfile=""
verbose=0


db_selected() {
    excluded=0
    included=0
    if [[ $lExcludedDatabase != "" ]];
    then
        for xdb in $(echo ${lExcludedDatabase} | tr "," "\n")
        do
            if [[ "$1" == $xdb ]]; then excluded=1; fi
        done
    fi
    if [[ ${database} == "all" ]];
    then
        included=1
    else
        for idb in $(echo ${database} | tr "," "\n")
        do
            if [[ "$1" == $idb ]]; then included=1; fi
        done
    fi
    [[ $included == 1 && $excluded == 0 ]]
    return
}



BASE_PROG=$(basename $0)
BASE_PROG_WITHOUT_KSH=`echo ${BASE_PROG} | awk -F\. '{print $1}'`
typeDB="indirect"


        alldb=$(db2 list db directory | grep Indirect -B 5 |grep "Database alias" |awk {'print $4'} |sort -u | uniq )
        for db in $alldb
        do
            if db_selected $db; then
             db2 -v activate db ${db}  >> ${lLogOutput}
             lReturnCode=$?
             #echo 'RC='$lReturnCode
             if [ ${lReturnCode} -ge 3 ] ; then
                 gErrorNo=8
                 gMessage="Error activating database. Look in ${lLogOutput}"
                 scriptUsage
             fi
             
            else
                printf "<<< Skipping database $db \n" >> ${lLogOutput}
            fi
        done


echo "[EOF]" >> ${lLogOutput}


cat ${lLogOutput} 



#
# Finish up
#
  ## handleDb2DbDisconnect
set +x
return 0
