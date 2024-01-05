#!/bin/ksh
#
# Script     : db2_create_client_instance.sh
# Description: Create a client instance
#
#<header>
#
# Remarks   : Parameters:
#   * Mandatory
#       -U <username> : User name (e.g. w0cppe, w0knng, ...)
#
#   * Optional
#       -b <db2 base> : Base directory of Db2; when omitted the latest and greatest is chosen
#                       (e.g. #DB2INSTALL_PLACEHOLDER#)
#       -h|-H         : Help
#
#</header>


#
# Constants
#
typeset    cHostName=$( hostname )
typeset    cScriptName="${0}"
typeset    cBaseNameScript=$( basename ${cScriptName} )
typeset    cScriptDir="${cScriptName%/*}"
typeset    cCurrentDir=$( pwd )
typeset    cLogsDirBase="/shared/db2/logs/${cBaseNameScript%.*}"

[[ "${cScriptDir}" == "." ]] && cScriptDir="${cCurrentDir}"

typeset    cPassWdMem=$( cat /etc/passwd )

#
# Functions
#
  function scriptUsage {

    # Show the options as described above
    printf "\nUsage of the script ${cScriptName}: \n"

    [[ "${gMessage}" != "" ]] && showError
    [[ ${gErrorNo} -eq 0 ]] && gErrorNo=1

    lHeader=$( grep -n '<[/]*header>' ${cScriptName} | awk -F: '{print $1}' | sed 's/$/,/g' )
    lHeaderPos=$( echo ${lHeader} | sed 's/,$//g; s/ //g' )
    lHeader=$( sed -n ${lHeaderPos}p ${cScriptName} | egrep -v '<[/]*header>|ksh|Description' | uniq | sed 's/^#//g; s/^[ ]*Remarks[ ]*://g' )

    if [ "${gDb2InstallationList}" != "" ] ; then
      typeset lFormattedVersionList=$( echo ${gDb2InstallationList} | sed 's/^[ ]*//g; s/[ ]*$//g; s/ [ ]*/, /g; s/\//\\\//g' )
      lHeader=$( echo "${lHeader}" | sed "s/#DB2INSTALL_PLACEHOLDER#/${lFormattedVersionList}/g" )
    else
      lHeader=$( echo "${lHeader}" | grep -v '#DB2INSTALL_PLACEHOLDER#' )
    fi

    gMessage=$( printf "${lHeader}\n\nExiting.\n" )
    showMessage

    set +x
    exit ${gErrorNo}
  }

#
# Primary initialization of commonly used variables
#
typeset    lTimestampToday=$( date "+%Y-%m-%d-%H.%M.%S" )
typeset -l lUsername=""
typeset    lDb2Base=""
typeset    lDb2CreateProgram=""
gMessage=""
gErrorNo=0

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
  PARS=$*  # Parameters disappear after getopts, so record here for logging later
  OPTIND=1 # Set the index pointer equal to the first parameter
  while getopts "U:b:hH" lOption; do
    case ${lOption} in
      U)
        lUsername="${OPTARG}"
        ;;
      b)
        lDb2Base="${OPTARG}"
        ;;
      *)
        gMessage=""
        scriptUsage
        ;;
    esac
  done

#
# Check input which is mandatory
#
[[ "${lUsername}" == "" ]] && gErrorNo=1 && gMessage="Please provide a username to do the work for" && scriptUsage

#
# Main - Get to work
#
if [ $( echo "${cPassWdMem}" | grep "^${lUsername}:" | wc -l ) -eq 0 ] ; then
  gErrorNo=2
  gMessage="The user ${lUsername} does not exist on this server (${cHostName})"
  scriptUsage
fi
fetchAllDb2Installations

if [ "${lDb2Base}" != "" ] ; then
  if [ $( echo "${gDb2InstallationList}" | grep "^${lDb2Base}$" | wc -l ) -eq 0 ] ; then
    gErrorNo=3
    gMessage="Installation directory ${lDb2Base} not found on this server (${cHostName})"
    scriptUsage
  fi
else
  #
  # The one with the largest release number, has a high likelyhood of being the most recent one
  #
  lDb2Base=$( echo "${gDb2InstallationList}" | tail -1 )
fi

lDb2CreateProgram=$( find ${lDb2Base} -type f -name 'db2icrt' 2>&1 | egrep -v 'Permission denied|^$' )

if [ "${lDb2CreateProgram}" == "" ] ; then
  gErrorNo=4
  gMessage="Could not locate the binary db2icrt in the installation directory ${lDb2Base} on this server (${cHostName})"
  scriptUsage
fi

gMessage=$( ${lDb2CreateProgram} -s client ${lUsername} 2>&1 )
gErrorNo=$?
if [ ${gErrorNo} -ne 0 -a "${gMessage}" != "" ] ; then
  gMessage=$( echo "${gMessage}" | sed 's/ \(line [0-9][0-9]*:\) /#/g' | tr '#' '\n' | tail -1 )
  scriptUsage
fi

#
# Finish up
#
set +x
return 0
