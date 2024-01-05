#!/bin/ksh
#
# Script     : db2_move_stats.sh
# Description: Move statistical information from Db2 via Logstash to Kibana
#
#<header>
#
# Remarks   : Parameters:
#
#   * Optional
#       -s | --remotehostname  : Execute the script on another server (SSH)
#                                 When this option is used, --remoteuser
#                                 needs a value as well.
#       -u | --remoteuser      : Impose as which user on the other server
#                                 When this option is used, --remotehostname
#                                 needs a value as well.
#       -C | --config          : Configuration file from which the commands get
#                                 executed. The file is searched in the directory
#                                 registered in ##cLogStashCfgDir_PlaceHolder##
#       -a | --alias           : Alias with which the database (in an instance and
#                                 on a server) is uniquely identifiable
#       -j | --job             : Job name executing this script
#       -m | --mailto          : (List of) Email address(es) whom should get notified
#                                 when something went wrong
#       -c | --mailcc          : (List of) Email address(es) whom should get notified
#                                  in cc when something went wrong
#       -q | --quiet           : Quiet - show no messages
#       -h | -H | --help       : Help
#
#</header>

#
# Constants
#
typeset    cCmdSwitchesShort="s:u:C:a:j:m:c:qhH"
typeset -l cCmdSwitchesLong="remotehostname:,remoteuser:,config:,alias:,job:,mailto:,mailcc:,quiet,help"
typeset    cHostName=$( hostname )
typeset    cScriptName="${0}"
typeset    cBaseNameScript=$( basename ${cScriptName} )
typeset    cScriptDir="${cScriptName%/*}"
typeset    cCurrentDir=$( pwd )
typeset    cLogsDirBase="/shared/db2/logs/${cBaseNameScript%.*}/${cHostName}"
typeset    cMailFrom="OCCTEam@allianz.be"

typeset    cLogStashCmd="/usr/share/logstash-7.8.1/bin/logstash"
typeset    cLogStashCfgDir="/etc/logstash-7.8.1/db2"
typeset    cSshOptions="-o BatchMode=yes -o StrictHostKeychecking=no"

[[ "${cScriptDir}" == "." ]] && cScriptDir="${cCurrentDir}"

#
# Functions
#
  function scriptUsage {

    typeset -u lExitScript="${1}"

    typeset    lMessage="${gMessage}"
    typeset    lHeader=""
    typeset    lHeaderPos=""

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
               | sed 's/^#//g; s/^[ ]*Remarks[ ]*://g' \
               | sed "s:##cLogStashCfgDir_PlaceHolder##:${cLogStashCfgDir}:g" )

    gMessage="${lHeader}"
    [[ "${lExitScript}" == "YES" ]] && gMessage=$( printf "${lHeader}\n\nExiting.\n" )
    showMessage

    if [ "${lMailTo}" != "" ] ; then
      lVerbose="NO"	# We do not need any additional info anymore, just a mail
      lMessage="Usage of the script ${cScriptName}:

${lMessage}

${lHeader}"
      sendMail  "${cHostName}" "${lInstance}" "${lDatabase}" "${gErrorNo}" "${lMessage}" "NO"
    fi

    set +x
    [[ "${lExitScript}" == "YES" ]] && exit ${gErrorNo}
    return ${gErrorNo}

  }

  function sendMail {

    typeset    lHostName="${1}"
    typeset    lErrorNo="${2}"
    typeset    lErrorMsg="${3}"
    typeset -u lExitScript="${4}"

    typeset    lDatabaseId=""
    typeset    lSubject=""

    [[ "${lExitScript}" != "NO" ]] && lExitScript="YES"

    [[ "${lJobName}" == "" ]] && lJobName="Statistics move-to-Kibana"
    lSubject="${lJobName} (${llAllias}) - ${cBaseNameScript} failed"
    [[ "${lAlias}" == "" ]] && lSubject="${lJobName} - ${cBaseNameScript} failed"

    if [ "${lMailTo}" != "" ] ; then
      if [ "${lVerbose}" == "YES" ] ; then
        echo "--> Sending email report on failure to ${lMailTo}"
      fi
      lErrorMsg="${lSubject}

${lErrorMsg}
  Return code: ${lErrorNo}"

      if [ "${lLogOutput}" != "" ] ; then
        if [ -f ${lLogOutput} ] ; then
          echo "--> Sending email report on failure to ${lMailTo}

${lErrorMsg}" >> ${lLogOutput}
        fi
      fi

      if [ "${lMailCc}" != "" ] ; then
        echo "${lErrorMsg}" \
          | mailx \
              -r "${cMailFrom}" \
              -s "${lSubject}" \
              -c "${lMailCc}" \
                 "${lMailTo}"
      else
        echo "${lErrorMsg}" \
          | mailx \
              -r "${cMailFrom}" \
              -s "${lSubject}" \
                 "${lMailTo}"
      fi
    fi

    set +x
    [[ "${lExitScript}" == "YES" ]] && exit ${lErrorNo}
    return ${lErrorNo}
  }

  function move_db2_kibana {

    typeset lHostName="${1}"
    typeset lConfigFile="${2}"

    typeset lTimestamp=""
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    
    typeset lFileList=$( ls ${cLogStashCfgDir}/${lConfigFile} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    if [ ${lNumberOfFiles} -eq 0 ] ; then
      lFileList=$( ls ${cLogStashCfgDir}/${lConfigFile}.conf 2>&1 | grep -v 'No such' )
      lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    fi
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching ${lConfigFile}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      sendMail "${lHostName}" "8" "${gMessage}" "No"
      lReturnCode=$?
      set +x
      return ${lReturnCode}
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( date "+%Y-%m-%d-%H.%M.%S" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lInputFile}"
      fi
      echo "${lTimestamp} - ${lInputFile}" >> ${lLogOutput}

      echo "*** - Start" >> ${lLogOutput}

      lReturnedText=$( ${cLogStashCmd} -f ${lInputFile} 2>&1 )
      lReturnCode=$?
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -ne 0 ] ; then
        sendMail "${lHostName}" "8" "${lReturnedText}" "No"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=""
        if [ $( grep '"dots"' ${lInputFile} | wc -l ) -gt 0 -o \
             $( grep "'dots'" ${lInputFile} | wc -l ) -gt 0 ] ; then
          typeset lTheDots=$(   echo "${lReturnedText}" \
                              | grep '^\.' \
                              | sed 's/\(\[INFO[ ]*\]\)/\n\1/g' \
                              | grep -v '\[INFO' )
          lNumberImported=$( echo ${lTheDots} | wc -c )
          lNumberImported=$(( lNumberImported - 1 ))
          if [ ${lNumberImported} -ne 0 ] ; then
            lNumberImported="Number of rows moved: ${lNumberImported}"
          else
            lNumberImported="Number of rows moved: 0"
          fi
        fi
        if [ "${lNumberImported}" != "" ] ; then
          echo "${lNumberImported}" | tr '^' '\t'
          echo "${lNumberImported}" | tr '^' '\t' >> ${lLogOutput}
        fi
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
      lTimestamp=$( date "+%Y-%m-%d-%H.%M.%S" )
      echo "
*** - End
${lTimestamp} - ${lInputFile}

" >> ${lLogOutput}

    done

    set +x
    return ${lReturnCode}

  }

#
# Primary initialization of commonly used variables
#
typeset    lTimestampToday=$( date "+%Y-%m-%d-%H.%M.%S" )

typeset    lRemoteHostName=""
typeset    lRemoteUser=""
typeset    lConfigFile=""
typeset    lAlias=""
typeset    lJobName=""
typeset    lMailTo=""
typeset    lMailCc=""
typeset -u lVerbose="YES"
typeset    lTimestamp=""
typeset -i lReturnCode=0
typeset -i lOverallReturnCode=0

#
# Loading libraries
#
[[ ! -f ${cScriptDir}/common_functions.include ]] && gErrorNo=2 && gMessage="Cannot load ${cScriptDir}/common_functions.include" && scriptUsage
. ${cScriptDir}/common_functions.include

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
  typeset _lCmdOptions="$@"

    # Process the options
  while [ "$#" ] ; do

    _lCmdOption="${1}"
    _lCmdValue="${2}"
    [[ "${_lCmdOption}" == "" && "${_lCmdValue}" == "" ]] && _lCmdOption="--"

    case ${_lCmdOption} in
      -s | --remotehostname )
        lRemoteHostName="${_lCmdValue}"
        shift 2
        ;;
      -u | --remoteuser )
        lRemoteUser="${_lCmdValue}"
        shift 2
        ;;
      -C | --config )
        lConfigFile="${_lCmdValue}"
        shift 2
        ;;
      -a | --alias )
        lAlias="${_lCmdValue}"
        shift 2
        ;;
      -j | --job )
        lJobName="${_lCmdValue}"
        shift 2
        ;;
      -m | --mailto )
        lMailTo="${_lCmdValue}"
        shift 2
        ;;
      -c | --mailcc )
        lMailCc="${_lCmdValue}"
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
if [ "${lRemoteHostName}" != "" -a "${lRemoteUser}" == "" ] ; then
  gErrorNo=10
  gMessage="When defining a remote host (${lRemoteHostName}) there is a need to have a remote user as well"
  scriptUsage
fi
if [ "${lRemoteHostName}" == "" -a "${lRemoteUser}" != "" ] ; then
  gErrorNo=11
  gMessage="When defining a remote user (${lRemoteUser}) there is a need to have a remote hostname as well"
  scriptUsage
fi
if [ "${lRemoteHostName}" != "" -a "${lRemoteUser}" != "" ] ; then
  _lCmdOptions=$(   echo "${_lCmdOptions}" \
                  | sed 's: \(\-\-\):\n\1:g' \
                  | egrep -v '^--remote|^--[ ]*$|^$' \
                  | tr '\n' ' ' )
  ssh ${cSshOptions} ${lRemoteUser}@${lRemoteHostName} "${cScriptDir}/${cBaseNameScript} ${_lCmdOptions}; exit \$?"
  lReturnCode=$?
  set +x
  exit ${lReturnCode}
fi

#
# Force variable(s) to values within boundaries and set a default when needed
#
[[ "${lVerbose}" != "NO" ]] && lVerbose="YES"

#
# Make sure logging can be done properly
#
typeset lLogOutputDir="${cLogsDirBase}"
typeset lLogOutput="${lLogOutputDir}/${lTimestampToday}_${cBaseNameScript}.log"
mkdir -p ${lLogOutputDir} >/dev/null 2>&1
chgrp -R db2admx ${lLogOutputDir} >/dev/null 2>&1
rm -f ${lLogOutput} >/dev/null 2>&1
touch ${lLogOutput} >/dev/null 2>&1
chgrp db2admx ${lLogOutput} >/dev/null 2>&1
lReturnCode=$?
if [ ${lReturnCode} -ne 0 ] ; then
  gErrorNo=4
  gMessage="Cannot create an outputfile ${lLogOutput}"
  scriptUsage
elif [ "${lVerbose}" == "YES" ] ; then
  echo "Execution log is written to :  ${lLogOutput}"
fi

#
# Validate the input data
#
[[ "${lMailTo}" == "" && "${lMailCc}" != "" ]] && lMailTo="${lMailCc}"
[[ "${lMailTo}" == "${lMailCc}" ]] && lMailCc=""

#
# Main - Get to work
#
lTimestamp=$( date "+%Y-%m-%d-%H.%M.%S" )
lTimestamp=$( echo "${lTimestamp}" | sed 's/^[ ]*//g; s/[ ]*$//g' )

#
# Even though the export functions will send back a return code,
#   no additional error handling is to be taken up. Each function
#   takes proper care of that
#
if [ "${lConfigFile}" == "" ] ; then
  move_db2_kibana    "${cHostName}" "db2_get_bp"
  lOverallReturnCode=$(( lOverallReturnCode + $? ))
  move_db2_kibana    "${cHostName}" "db2_get_db"
  lOverallReturnCode=$(( lOverallReturnCode + $? ))
  move_db2_kibana    "${cHostName}" "db2_get_dbsize_info"
  lOverallReturnCode=$(( lOverallReturnCode + $? ))
  move_db2_kibana    "${cHostName}" "db2_get_table"
  lOverallReturnCode=$(( lOverallReturnCode + $? ))
  move_db2_kibana    "${cHostName}" "db2_get_throughput"
  lOverallReturnCode=$(( lOverallReturnCode + $? ))
else
  move_db2_kibana    "${cHostName}" "${lConfigFile}"
  lOverallReturnCode=$(( lOverallReturnCode + $? ))
fi

#
# Finish up
#
set +x
return ${lOverallReturnCode}
