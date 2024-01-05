#!/bin/ksh
#
# Script     : db2_full_bind.sh
# Description: Bind all packages to a database
#
#<header>
#
# Remarks   : Parameters:
#   * Mandatory
#       -S | --hostname   : Hostname; when omitted, the current
#                             hostname (#HOSTNAME_PLACEHOLDER#) is used
#       -I | --instance   : Instance name
#       -D | --database   : Database name
#       -E | --environment: Environment, e.g. dev, a1fit1, ...
#
#   * Optional
#       -V | --version    : (Only applicable for DEV). If binding needs to
#                             be done against another version than defined
#                             in ${cBindVersion} (= #BINDVERSION_PLACEHOLDER#)
#       -p | --package    : Name of one single package (e.g. DAAJKAB)
#       -C | --contoken   : Check the consistency token between the Bindfile,
#                             Load Module and Object file
#       -U | --user       : User name to connect to the database
#       -P | --password   : The password matching the user name to connect
#                             to the database
#       -s | --schema     : (List of comma separated) schema(s) to bind against
#                             When empty, binds are done against ABS and BABS
#       -q | --quiet      : Quiet - show no messages
#       -h | -H | --help  : Help
#
#</header>

#
# Constants
#
typeset    cBindVersion="v197"

typeset    cCmdSwitchesShort="S:I:D:E:V:U:P:s:p:CqhH"
typeset -l cCmdSwitchesLong="hostname:,instance:,database:,environment:,version:,user:,password:,schema:,package:,contoken,quiet,help"
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
    [[ "${cHostName}" == "" ]] && cHostName=$( hostname )
    lHeader=$( echo "${lHeader}" \
             | sed "s/#HOSTNAME_PLACEHOLDER#/${cHostName}/g" \
             | sed "s/#BINDVERSION_PLACEHOLDER#/${cBindVersion}/g" )

    gMessage="${lHeader}"
    [[ "${lExitScript}" == "YES" ]] && gMessage=$( printf "${lHeader}\n\nExiting.\n" )
    showMessage

    set +x
    [[ "${lExitScript}" == "YES" ]] && exit ${gErrorNo}
    return ${gErrorNo}

  }

  function checkConToken {
    #
    # Return code
    #   - 0: The consistency token matches
    #   - 1: The consistency token does not match
    #   - 3: a. The file name given is empty
    #        b. The file name given does not exist
    #        c. The file type is not supported
    #
    #

    typeset    lConToken="${1}"
    typeset -u lFileType="${2}"
    typeset    lFileToCheck="${3}"

    typeset    lFileConTokenInfo=""

    [[ "${lFileToCheck}" == "" ]] && set +x && return 3
    [[ ! -f ${lFileToCheck} ]] && set +x && return 3

    case ${lFileType} in
      LOAD )
          lFileConTokenInfo=$(   strings ${lFileToCheck} \
                             | grep -A2 "^[A-Z]*${lConToken}01111 2" \
                             | grep -v '^$'
                             )
          if [ "${lFileConTokenInfo}" != "" ]  ; then
            lFileConTokenInfo=$(   strings ${lFileToCheck} \
                               | grep -A2 "^[A-Z]*${lConToken}[0-9][0-9]* [0-9]" \
                               | grep -v '^$'
                               )
          fi
        ;;
      * )
          set +x
          return 3
        ;;
    esac

    set +x
    [[ "${lFileConTokenInfo}" == "" ]] && return 1
    return 0

  }

#
# Primary initialization of commonly used variables
#
typeset    lTimestampToday=$( date "+%Y-%m-%d-%H.%M.%S" )
  ## typeset    lDb2Profile=""
typeset -l lHostName=""
typeset -l lInstance=""
typeset -u lDatabase=""
typeset -l lEnvironment=""
typeset    lBindVersion="${cBindVersion}"
typeset -u lConTokenCheck="NO"
typeset    lUsername=""
typeset    lPassword=""
typeset -u lSchema="ABS,BABS"
typeset -u lPackage=""
typeset -u lVerbose="YES"
typeset    aWorkingDir
typeset -i lReturnCode=0
typeset -i lOverallReturnCode=0

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
      -S | --hostname )
        lHostName="${_lCmdValue}"
        shift 2
        ;;
      -I | --instance )
        lInstance="${_lCmdValue}"
        shift 2
        ;;
      -D | --database )
        lDatabase="${_lCmdValue}"
        shift 2
        ;;
      -E | --environment )
        lEnvironment="${_lCmdValue}"
        shift 2
        ;;
      -V | --version )
        lBindVersion="${_lCmdValue}"
        shift 2
        ;;
      -p | --package )
        lPackage="${_lCmdValue}"
        shift 2
        ;;
      -C | --contoken )
        lConTokenCheck="YES"
        shift 1
        ;;
      -U | --user )
        lUsername="${_lCmdValue}"
        shift 2
        ;;
      -P | --password )
        lPassword="${_lCmdValue}"
        shift 2
        ;;
      -s | --schema )
        lSchema="${_lCmdValue}"
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
[[ "${lHostName}" == "" ]] && lHostName="${cHostName}"
[[ "${lHostName}" == "" ]] && gErrorNo=1 && gMessage="Please provide a hostname to do the work for" && scriptUsage
[[ "${lInstance}" == "" ]] && gErrorNo=1 && gMessage="Please provide an instance to do the work for" && scriptUsage
[[ "${lDatabase}" == "" ]] && gErrorNo=1 && gMessage="Please provide a database to do the work for" && scriptUsage
[[ "${lEnvironment}" == "" ]] && gErrorNo=1 && gMessage="Please provide an environment to do the work for" && scriptUsage

#
# Force variable(s) to values within boundaries and set a default when needed
#
[[ "${lVerbose}" != "NO" ]] && lVerbose="YES"
[[ "${lBindVersion}" == "" ]] && lBindVersion="${cBindVersion}"
[[ "${lConTokenCheck}" != "YES" ]] && lConTokenCheck="NO"

#
# Validate the input data
#
if [ "${lHostName}" !=  "${cHostName}" ] ; then
  echo "Sorry, this script must be launched on ${cHostName}"
  exit 8
fi

case ${lInstance} in
  db2bnld1 )
      lUsername="svnbnld1"
      lPassword="1dlnbnvs"
    ;;
  db2bnlt1 | db2bnln1 )
      lUsername="svnbnlt1"
      lPassword="1tlnbnvs"
    ;;
  db2bnlu1 )
      lUsername="svnbnlu1"
      lPassword="1ulnbnvs"
    ;;
  db2bnlr1 )
      lUsername="svnbnlr1"
      lPassword="1rlnbnvs"
    ;;
  db2bnlp1 )
      lUsername="svnbnlp1"
      lPassword="1plnbnvs"
    ;;
  * )
      gMessage="Supported instances: db2bnld1, db2bnlt1, db2bnln1, db2bnlu1, db2bnlr1, db2bnlp1"
      gError=10
      scriptUsage
    ;;
esac

case ${lEnvironment} in
  dev | development )
      lEnvironment="dev"
      aWorkingDir=(
/var/opt/asc/xxxxx/${lBindVersion}/ccc/inttest
#/var/opt/asc/xxxxx/${lBindVersion}/ccc/fachtest
#/var/opt/asc/xxxxx/${lBindVersion}/ccc/inttest
#...
)
    ;;
  a1sit1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  b1sit1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  c1sit1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  d1sit1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  a1nft1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  b1nft1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  c1nft1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  a1fit1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  b1fit1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  c1fit1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  d1fit1 )
      aWorkingDir=( /shared/av/test/bnl/${lEnvironment} )
    ;;
  brprod )
      aWorkingDir=( /shared/av/prod/bnl/${lEnvironment} )
    ;;
  b0prod )
      aWorkingDir=( /shared/av/prod/bnl/${lEnvironment} )
    ;;
  * )
      gMessage="Supported environments: dev[elopment], [a,b,c,d]1sit1, [a,b,c]1nft1, [a,b,c,d]1fit1, brprod, b0prod"
      gError=11
      scriptUsage
    ;;
esac

#
# Load Db2 library
#
loadDb2Profile "${lInstance}"
lReturnCode=$?
[[ ! -f ${gDb2Profile} ]] && gErrorNo=2 && gMessage="Cannot load ${gDb2Profile}" && scriptUsage

#
# Set umask
#
umask ${cMasking}

#
# Main - Get to work
#
typeset -i lExists

echo "Full bind on ${lHostName} for database ${lDatabase}
Target database       = ${lDatabase}"
if [ "${lEnvironment}" == "dev" ] ; then
  echo "Binding for version   = ${lBindVersion}"
fi
echo "Target root folder(s) = "
echo "${aWorkingDir[@]}" | sed 's: :\n:g' | sed 's:^:\t* :g'
echo "Target schema(s)      = ${lSchema}
Bind process logs     = ${cLogsDirBase}/${lInstance}/${lDatabase}/${lTimestampToday}_*.log

Bind dbm files will be searched in the sub-directory dbrm of the above
  described target root folder(s).

Started at         = $( date )

Connecting to ${lDatabase}
"

gDatabase="${lDatabase}"
[[ "${lUsername}" != "" ]] && gDb2User=${lUsername}
[[ "${lPassword}" != "" ]] && gDb2Passwd=${lPassword}
handleDb2DbConnect
lReturnCode=$?
[[ ${lReturnCode} -ne 0 ]] && gErrorNo=5 && gMessage="Cannot connect to ${gDatabase}" && scriptUsage

typeset lBindInfo=""
typeset lFileInfo=""
for lWorkingDir in "${aWorkingDir[@]}"
do
  typeset lTmpBindInfo=""
  for lFqBindFile in $( ls ${lWorkingDir}/dbrm/*.bnd 2>&1 \
                      | grep -v 'cannot access' \
                      | grep -v '^$' \
                      | grep "${lPackage}" \
                      )
  do
    gMessage=$( printf "\tProcessing ${lFqBindFile}" )
    [[ "${lVerbose}" == "YES" ]] && showIndicator
  
    lFileInfo=$(   db2bfd -b ${lFqBindFile} \
                 | egrep '^Creator |^App Name |^Timestamp |^Version ' \
                 | sed 's/^[A-Za-z ]*"//g; s/[ "]*$//g; s/$/:/g' \
                 | cut -d':' -f1 \
                 | sed 's/[ ]*$/:/g'
               )
    lTmpBindInfo="${lTmpBindInfo};${lFileInfo}:${lFqBindFile}:${lWorkingDir}"
  done
  lTmpBindInfo=$(   echo ${lTmpBindInfo}";" \
               | sed 's/;/\n/g; s/[ :]*:[ ]*/:/g' \
               | grep -v '^$' \
               | sort -t':' -k 1 -k2 )
  lBindInfo="${lBindInfo};${lTmpBindInfo}"
done
[[ "${lVerbose}" == "YES" ]] && printfRepeatChar " " 80
lBindInfo=$(   echo ${lBindInfo}";" \
             | sed 's/;/\n/g; s/[ :]*:[ ]*/:/g' \
             | grep -v '^$' )

for lCurrentSchema in $( echo "${lSchema}" | sed 's/,/ /g; s/ [ ]*/ /g' )
do
  lExists=$( db2 -x "SELECT 1
                       FROM SYSCAT.SCHEMATA
                      WHERE SCHEMANAME = '${lCurrentSchema}'
                       WITH UR
                        FOR READ ONLY" 2>&1 )
  if [ ${lExists} -eq 1 ] ; then
      #
      # Make sure logging can be done properly
      #
    typeset lLogOutputDir="${cLogsDirBase}/${lInstance}/${lDatabase}"
    typeset lLogOutputError="${lLogOutputDir}/${lTimestampToday}_${lCurrentSchema}_Errors.log"
    typeset lLogOutputWarning="${lLogOutputDir}/${lTimestampToday}_${lCurrentSchema}_Warnings.log"

    mkdir -p ${lLogOutputDir} >/dev/null 2>&1
    chgrp -R ${cDb2CommonSecurityGroup} ${lLogOutputDir} >/dev/null 2>&1
    rm -f ${lLogOutputError} >/dev/null 2>&1
    touch ${lLogOutputError} >/dev/null 2>&1
    lReturnCode=$?
    if [ ${lReturnCode} -ne 0 ] ; then
      gErrorNo=4
      gMessage="Cannot create an outputfile ${lLogOutputError}"
      scriptUsage
    fi
    rm -f ${lLogOutputError} >/dev/null 2>&1

    for lBindInfoLine in $( echo "${lBindInfo}" | grep "^${lCurrentSchema}:" )
    do
      typeset lSchema=$( echo "${lBindInfoLine}"     | cut -d ':' -f 1 )
      typeset lName=$( echo "${lBindInfoLine}"       | cut -d ':' -f 2 )
      typeset lConToken=$( echo "${lBindInfoLine}"   | cut -d ':' -f 3 )
      typeset lVersion=$( echo "${lBindInfoLine}"    | cut -d ':' -f 4 )
      typeset lFqBindFile=$( echo "${lBindInfoLine}" | cut -d ':' -f 5 )
      typeset lWorkingDir=$( echo "${lBindInfoLine}" | cut -d ':' -f 6 )
      typeset lFqLoadModule=$( echo "${lWorkingDir}/load/$( basename ${lFqBindFile%.*} ).so" )
      typeset lFqObjectFile=$( echo "${lWorkingDir}/obj/$( basename ${lFqBindFile%.*} ).o" )

      typeset lFile=$( basename ${lFqBindFile} )
      typeset lPkgInfoDb=""
      typeset lPathInDb=""
      typeset lConTokenInDb=""

      if [ "${lEnvironment}" == "dev" ] ; then
        lFile=${lFqBindFile}
      fi

        #
        # Only attempt a bind if the schema to which the file was bound
        #   matches the current schema against binding will be done
        #
      if [ "${lCurrentSchema}" == "${lSchema}" ] ; then
          #
          # Perform the bind
          #
        [[ "${lVerbose}" == "YES" ]] && echo "
Binding ${lCurrentSchema} ${lFile}

"
        lReturnedText=$( db2 "bind ${lFqBindFile} action replace collection ${lCurrentSchema} qualifier ${lCurrentSchema} funcpath SYSFUN,${lCurrentSchema} validate bind isolation cs datetime iso sqlerror nopackage dynamicrules run explain no" )
        lReturnCode=$?

          #
          # Get info of the last bound package
          #
        lPkgInfoDb=$( db2 -x "SELECT TRIM(r.IMPLEMENTATION)
                                  || ','
                                  || TRIM(CAST(COALESCE(p.UNIQUE_ID,'NULL') AS VARCHAR(10) FOR SBCS DATA))
                                FROM SYSCAT.ROUTINES r
                                LEFT JOIN SYSCAT.PACKAGES p
                                       ON (     p.PKGSCHEMA = r.ROUTINESCHEMA 
                                            AND p.PKGNAME   = r.ROUTINENAME
                                            AND p.VALID     = 'Y' )
                               WHERE r.ROUTINESCHEMA = '${lSchema}'
                                 AND r.ROUTINENAME   = '${lName}'
                                 AND r.ORIGIN        = 'E'    -- External routine
                               ORDER BY p.LAST_BIND_TIME desc, p.LASTUSED DESC
                               FETCH FIRST 1 ROWS ONLY
                                WITH UR
                                 FOR READ ONLY" 2>&1 )
        lPathInDb=$( echo "${lPkgInfoDb}" | cut -d ',' -f 1 | tr -d ' ' )
        lConTokenInDb=$( echo "${lPkgInfoDb}" | cut -d ',' -f 2 | tr -d ' ' )
        [[ "${lConTokenInDb}" == "" ]] && lConTokenInDb="NULL"

          #
          # How did the binding perform?
          #
        [[ "${lVerbose}" == "YES" ]] && echo "${lReturnedText}"
        if [ ${lReturnCode} -ne 0 ]; then
          if [ $( echo "${lReturnedText}" | grep ' errors ' | grep -v '"0" errors' | wc -l ) -gt 0 ] ; then
            [[ "${lVerbose}" == "YES" ]] && echo "
Error occurred during binding ${lCurrentSchema} ${lFile}"
            echo "===
${lCurrentSchema} ${lFile}" >> ${lLogOutputError}
            echo "${lReturnedText}" | sed 's:^:\t:g' >> ${lLogOutputError}
          else
            [[ "${lVerbose}" == "YES" ]] && echo "
Warning occurred during binding ${lCurrentSchema} ${lFile}"
            echo "===
${lCurrentSchema} ${lFile}" >> ${lLogOutputWarning}
            echo "${lReturnedText}" | sed 's:^:\t:g' >> ${lLogOutputWarning}
          fi
        else
          [[ "${lVerbose}" == "YES" ]] && echo "Binding ${lCurrentSchema} OK on ${lFile}"
        fi

          #
          # Does the path in the database correspond with what is found on disk?
          #   Do this test only for those environments <> "dev"
          #
        if [ "${lEnvironment}" != "dev" ] ; then
          lExists=1
          if [ $( echo ${lPathInDb} | grep -v '^$' | wc -l ) -gt 0 ] ; then
            lExists=$( echo "${lPathInDb}" | grep "^${lWorkingDir}/stpload/${lName}\." | wc -l )
            if [ ${lExists} -eq 0 ] ; then
              lExists=$( echo "${lPathInDb}" | grep "^${lWorkingDir}/load/${lName}\." | wc -l )
              [[ ${lExists} -ne 0 ]] && lFqLoadModule=$( echo "${lWorkingDir}/load/$( basename ${lFqBindFile%.*} ).so" )
            fi
          fi
          if [ ${lExists} -eq 0 ] ; then
            [[ "${lVerbose}" == "YES" ]] && echo "
  Error matching path in the database for ${lCurrentSchema} ${lFile}"
            echo "${lFile}: Error matching path (${lWorkingDir}) in the database" >> ${lLogOutputError}
          fi
        fi

          #
          # Is the Consistency Token ... consistent?
          #
        if [ "${lConTokenCheck}" == "YES" -a "${lConTokenInDb}" != "NULL" ] ; then
          if [ "${lConTokenInDb}" != "${lConToken}" ] ; then
            [[ "${lVerbose}" == "YES" ]] && echo "
  The con-token ${lConToken} does not match with ${lConTokenInDb} in the database ${lCurrentSchema} ${lFile}"
            echo "${lFile}: The con-token ${lConToken} does not match with ${lConTokenInDb} in the database" >> ${lLogOutputError}
          else
            if [ -f ${lFqLoadModule} ] ; then
              checkConToken "${lConToken}" "LOAD" "${lFqLoadModule}"
              lReturnCode=$?
              case ${lReturnCode} in
                1)
                    [[ "${lVerbose}" == "YES" ]] && echo "
    The con-token ${lConToken} does not match with the load module for ${lCurrentSchema} ${lFile}"
                    echo "${lFile}: The con-token ${lConToken} does not match with the load module" >> ${lLogOutputError}
                  ;;
                3)
                    [[ "${lVerbose}" == "YES" ]] && echo "
    Could not find corresponding load file for ${lCurrentSchema} ${lFile}"
                    echo "${lFile}: Could not find corresponding load file" >> ${lLogOutputError}
                  ;;
              esac
            fi
          fi 
        fi # ${lConTokenCheck} == "YES"

      fi
    done
  fi
done
if [ -f ${lLogOutputDir}/${lTimestampToday}_* ] ; then
  echo ""
  printfRepeatChar "-" 80
  echo "Please check out these error(s) and/or warning(s):

"
  chgrp ${cDb2CommonSecurityGroup} ${lLogOutputDir}/${lTimestampToday}_* >/dev/null 2>&1
  ls -1 ${lLogOutputDir}/${lTimestampToday}_* | sed 's/^/ - /g'
  if [ $( ls -1 ${lLogOutputDir}/${lTimestampToday}_* | grep -i 'error' | wc -l ) -gt 0 ] ; then
    lOverallReturnCode=8
  elif [ $( ls -1 ${lLogOutputDir}/${lTimestampToday}_* | grep -i 'warning' | wc -l ) -gt 0 ] ; then
    lOverallReturnCode=5
  fi
  printfRepeatChar "-" 80
fi

#
# Finish up
#
handleDb2DbDisconnect

echo "
Done at            = $( date )
"

set +x
return ${lOverallReturnCode}
