#!/bin/ksh
#
# Script     : db2_create_db_user.sh
# Description: Create a local user and add the user to
#                the RO/RW-group of the database
#
#<header>
#
# Remarks   : Parameters:
#   * Optional
#       -H | --hostname   : Host name
#       -I | --instance   : Instance name
#       -D | --database   : Database name
#       -N | --dbnickname : Nick name of the database (e.g. SIT1-P, UAT-A, ...)
#       -p | --port       : Port number
#       -E | --environment: Environment indication (e.g. DEV, TST, ...)
#       -e | --env_short  : One character environment indication (e.g. d, t, ...)
#       -G | --group      : Privilege group (RO or RW)
#       -U | --user       : User name to connect to the database
#       -P | --password   : The password matching the user name to connect
#                             to the database
#       -u | --fullname   : Full name of the user
#       -m | --mailto     : (List of) Email address(es) whom should get notified
#       -t | --test       : Run through the script without actually executing
#                             any of the persisting commands
#       -q | --quiet      : Quiet - show no messages
#       -h | -H | --help  : Help
#
#</header>

#
# Constants
#
typeset    cCmdSwitchesShort="H:I:D:N:p:E:e:G:U:P:u:m:tqhH"
typeset -l cCmdSwitchesLong="hostname:,instance:,database:,dbnickname:,port:,environment:,env_short:,group:,user:,password:,fullname:,description:,mailto:,test,quiet,help"
typeset -l cHostName=$( hostname )
typeset -l cHostNamePostfix="srv.allianz"
typeset    cScriptName="${0}"
typeset    cBaseNameScript=$( basename ${cScriptName} )
typeset    cScriptDir="${cScriptName%/*}"
typeset    cCurrentDir=$( pwd )
typeset    cLogsDirBase="/shared/db2/logs/${cBaseNameScript%.*}/${cHostName}"
typeset    cMasking="0002"
typeset -i lPasswordMaximumAge=365
typeset -i lPasswordMinimumSize=8

typeset    cMailFrom="OCCTEam@allianz.be"

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

  function sendMail {

    typeset lSubject="${1}"
    typeset lBody="${2}"
    typeset lMailTo="${3}"

    if [ "${lMailTo}" != "" ] ; then
      if [ "${lVerbose}" == "YES" ] ; then
        echo "--> Sending email with password information to ${lMailTo}"
      fi
      
      if [ "${lTestRun}" != "YES" ] ; then
        echo "${lBody}" \
          | mailx \
              -r "${cMailFrom}" \
              -s "${lSubject}" \
                 "${lMailTo}"
      else
        echo "INFO - A mail with subject '${lSubject}' would be send out"
      fi
    fi

    set +x
    return 0
  }

#
# Primary initialization of commonly used variables
#
typeset -l lHostname="${cHostName}"
typeset -l lInstance=""
typeset -u lDatabase=""
typeset -u lDbNickname=""
typeset    lDb2Profile=""
typeset    lPort=""
typeset -l lUser=""
typeset    lPassword=""
typeset    lFullname=""
typeset    lDescription=""
typeset    lEnvironment=""
typeset -l lEnvironmentChar=""
typeset -l lGroup=""
typeset    lRWgroup=""
typeset    lROgroup=""
typeset -u lTestRun="NO"
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
    # Read all switch options, store in $@
    #   * perform a lowercase on all '--long' switch options
    #   * keep space separated data together with its' switch
    #
  eval set -- $(   echo "$@" \
                 | tr ' ' '\n' \
                 | sed 's/^\(\-\-.*\)/\L\1/' \
                 | tr '\n' ' ' \
                 | sed 's/^[ ]*//g; s/[ ]*$/\n/g; s/|/\\|/g' \
                 | sed 's:\(\-\-[a-z_]*\)\( \):\1[_]:g; s:\( \)\(\-\-\):[_]\2:g; s: :[blank]:g; s:\[_\]: :g' \
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

    _lCmdOption=$( echo "${1}" | sed 's:\[blank\]: :g' )
    _lCmdValue=$( echo "${2}" | sed 's:\[blank\]: :g' )
    [[ "${_lCmdOption}" == "" && "${_lCmdValue}" == "" ]] && _lCmdOption="--"

    case ${_lCmdOption} in
      -H | --hostname )
        lHostname="${_lCmdValue}"
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
      -N | --dbnickname )
        lDbNickname="${_lCmdValue}"
        shift 2
        ;;
      -p | --port )
        lPort="${_lCmdValue}"
        shift 2
        ;;
      -E | --environment )
        lEnvironment="${_lCmdValue}"
        shift 2
        ;;
      -e | --env_short )
        lEnvironmentChar="${_lCmdValue:0:1}"
        shift 2
        ;;
      -G | --group )
        lGroup="${_lCmdValue}"
        shift 2
        ;;
      -U | --user )
        lUser="${_lCmdValue}"
        shift 2
        ;;
      -P | --password )
        lPassword="${_lCmdValue}"
        shift 2
        ;;
      -u | --fullname )
        lFullname="${_lCmdValue}"
        shift 2
        ;;
      -m | --mailto )
        lMailTo="${_lCmdValue}"
        shift 2
        ;;
      -t | --test )
        lTestRun="YES"
        shift 1
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
if [ "${lInstance}" != "" -o "${lDatabase}" ] ; then
  [[ "${lHostname}" == "" ]] && gErrorNo=1 && gMessage="Please provide a hostname to do the work for" && scriptUsage
  [[ "${lInstance}" == "" ]] && gErrorNo=1 && gMessage="Please provide an instance to do the work for" && scriptUsage
  [[ "${lDatabase}" == "" ]] && gErrorNo=1 && gMessage="Please provide a database to do the work for" && scriptUsage
fi

#
# Force variable(s) to values within boundaries and set a default when needed
#
[[ "${lVerbose}" != "NO" ]] && lVerbose="YES"

#
# Set default umask
#
umask ${cMasking}

#
# Load Db2 library
#
  # Only load when not yet done
loadDb2Profile "${lInstance}"
lReturnCode=$?
[[ ! -f ${gDb2Profile} ]] && gErrorNo=2 && gMessage="Cannot load ${gDb2Profile}" && scriptUsage

#
# Define known values
#
if [ "${lEnvironment}" == "" -o "${lEnvironmentChar}" == "" -o \
     "${lDbNickname}"  == "" -o "${lPort}"            == "" -o \
     "${lGroup}"       == "" ] ; then
  #
  # None or not enough information is given when starting the script
  #   so the values need to be chosen from
  #
  case ${cHostName} in
    sla70190 )
      lEnvironment="Development"
      lEnvironmentChar="d"
      lDbNickname="SIT0-M,SIT0-P"
      lDatabase="DDBNA00,DDBNB00"
      lPort="51000"
      ;;
    sla70191 )
      lEnvironment="Test"
      lEnvironmentChar="t"
      lDbNickname="SIT1-M,SIT1-P"
      lDatabase="DTBNA01,DTBNB01"
      lPort="51002"
      ;;
    sla70192 )
      lEnvironment="User Acceptance"
      lEnvironmentChar="u"
      lDbNickname="UAT-A,UAT-B"
      lDatabase="DUBNB01,DUBNA01"
      lPort="51004"
      ;;
    sla71168 )
      lEnvironment="Pre-production,Production"
      lEnvironmentChar="r,p"
      lDbNickname="PREPRD,PRD"
      lDatabase="DRBNL01,DPBNL01"
      lPort="51005,51000"
      ;;
    sla70193 )
      lEnvironment="Pre-production,Production"
      lEnvironmentChar="r,p"
      lDbNickname="PREPRD,PRD"
      lDatabase="DRBNL01,DPBNL01"
      lPort="51005,51000"
      ;;
    * )
      gMessage="Server '${cHostName}' is not known."
      scriptUsage
      ;;
  esac
  #
  # The username carries the lEnvironmentChar as first character
  #   so to avoid errors, make this one empty as well
  # The group is also derived following some choses
  #
  lUser=""
  lGroup=""
fi
  #
  # The privileg groups are a (nearly) constant thing
  #
case ${cHostName} in
  sla70190 )
    lRWgroup="dbdevrwg"
    lROgroup="dbdevrog"
    ;;
  sla70191 )
    lRWgroup="dbtstrwg"
    lROgroup="dbtstrog"
    ;;
  sla70192 )
    lRWgroup="dbuatrwg"
    lROgroup="dbuatrog"
    ;;
  sla71168 )
    lRWgroup="dbprdrwg"
    lROgroup="dbprdrog"
    ;;
  sla70193 )
    lRWgroup="dbprerwg,dbprdrwg"
    lROgroup="dbprerog,dbprdrog"
      # Do we know already for which environment we're working?
    [[ "${lEnvironmentChar}" == "r" ]] && lRWgroup="dbprerwg" && lROgroup="dbprerog"
    [[ "${lEnvironmentChar}" == "p" ]] && lRWgroup="dbprdrwg" && lROgroup="dbprdrog"
    ;;
  * )
    gMessage="Server '${cHostName}' is not known."
    scriptUsage
    ;;
esac

#
# Validate the input data
#
if [ "${lHostname}" != "${cHostName}" -a "${lHostname}" != "${cHostName}.${cHostNamePostfix}" ] ; then
  gErrorNo=5
  gMessage="This script should be executed on ${lHostname} instead of ${cHostName}"
  scriptUsage
fi
if [ $( echo "${lDatabase}" | grep ',' | wc -l) -eq 0 ] ; then
  if [ "${lDatabase}" != "" ] ; then
    gDatabase="${lDatabase}"
    isDb2DbLocal
    lReturnCode=$?
    if [ ${lReturnCode} -ne 0 ] ; then
      gErrorNo=6
      gMessage="The database ${lDatabase} isn't defined local within instance ${lInstance}"
      scriptUsage
    fi
  fi
fi
if [ "${lGroup}" != "" ] ; then
  if [ "${lGroup}" != "ro" -a "${lGroup}" != "rw" ] ; then
    gErrorNo=7
    gMessage="The group should be RO (read-only) or RW (read + write) instead of '${lGroup}'"
    scriptUsage
  fi
fi

#
# Main - Get to work
#
echo "====================================================================================="
echo "-- User creation"
echo "====================================================================================="

if [ $( echo "${lDbNickname}" | grep ',' | wc -l) -gt 0 ] ; then
  readValue "Please enter the environment: " "MANDATORY" "${lDbNickname}"
  gValue=$( echo ${gValue} | tr '[a-z]' '[A-Z]' )
  echo "You entered: ${gValue}"

  lPosition=$(   echo ",${lDbNickname}," \
               | tr ',' '\n' \
               | grep -v '^$' \
               | grep -n "^${gValue}$" \
               | cut -d ':' -f1 )
  lDbNickname="${gValue}"
  lEnvironment=$(   echo ${lEnvironment} \
                  | cut -d ',' -f${lPosition} || ${lEnvironment} )
  lEnvironmentChar=$(   echo ${lEnvironmentChar} \
                      | cut -d ',' -f${lPosition} || ${lEnvironmentChar} )
  lDatabase=$(   echo ${lDatabase} \
               | cut -d ',' -f${lPosition} || ${lDatabase} )
  lPort=$(   echo ${lPort} \
           | cut -d ',' -f${lPosition} || ${lPort} )
  lRWgroup=$(   echo ${lRWgroup} \
              | cut -d ',' -f${lPosition} || ${lRWgroup} )
  lROgroup=$(   echo ${lROgroup} \
              | cut -d ',' -f${lPosition} || ${lROgroup} )
fi
if [ "${lGroup}" == "" ] ; then
  readValue "Please enter the privilege group: " "MANDATORY" "ro,rw" "ro"
  gValue=$( echo ${gValue} | tr '[A-Z]' '[a-z]' )
  lGroup="${gValue}"
fi
[[ "${lGroup}" == "rw" ]] && lGroup=${lRWgroup} || lGroup=${lROgroup}
echo "Effective privilege group will be: ${lGroup}"

if [ "${lUser}" == "" ] ; then
  readValue "Please enter the userid: " "MANDATORY"
  gValue=$( echo ${gValue} | tr '[A-Z]' '[a-z]' )
  lUser="${lEnvironmentChar}${gValue}"
else
  lUser="${lEnvironmentChar}${lUser}"
fi
echo "Effective user will be: ${lUser}"
if [ "${lFullname}" == "" ] ; then
  readValue "Please enter the username: " "MANDATORY"
  lFullname="${gValue}"
fi
echo "Effective username will be: ${lFullname}"

lDescription="RO ${lEnvironment} user ${lFullname}"
if [ "${lGroup}" == "${lRWgroup}" ] ; then
  lDescription="RW ${lEnvironment} user ${lFullname}"
fi

clear
echo "Creating ${lDescription}"
echo ""

if [ "${lTestRun}" != "YES" ] ; then
  echo "Creating group ${lGroup} if it is not already there"
  getent group ${lGroup} &>/dev/null || groupadd ${lGroup}
else
  echo "INFO - If the group ${lGroup} doesn't exist already, it would have been created"
  getent group ${lGroup} 2>&1 | sed 's/^/\tINFO - /g'
fi
echo ""

if [ "${lTestRun}" != "YES" ] ; then
  userdel ${lUser}
  useradd -g ${lGroup} -c "${lUser}" -s /sbin/nologin -m -d /home/${lUser} ${lUser}
else
  echo "INFO - The user ${lUser} would have been removed"
  echo "INFO - The user ${lUser} would have been created"
  echo "	INFO - Group: ${lGroup}"
  echo "	INFO - Home : /home/${lUser}"
  echo "        INFO - Shell: /sbin/nologin"
fi

if [ "${lTestRun}" != "YES" ] ; then
  chage -M ${lPasswordMaximumAge} ${lUser}
else
  echo "INFO - An expiration on the password of ${lPasswordMaximumAge} days would be set for the user"
fi
lExpirationDate=$( date +"%Y-%m-%d" -d "+${lPasswordMaximumAge} days" )
echo "Expiration date of the password : ${lExpirationDate}"

if [ "${lTestRun}" != "YES" ] ; then
  chage -E ${lExpirationDate} ${lUser}
else
  echo "INFO - The accessibility of the account would be fixed at ${lExpirationDate} for the user"
fi

if [ "${lPassword}" == "" ] ; then
  lPassword=$( tr -cd '[:alnum:]' < /dev/urandom | fold -w${lPasswordMinimumSize} | head -n1 )
fi
if [ "${lTestRun}" != "YES" ] ; then
  echo "${lPassword}" | passwd ${lUser} --stdin
  cat /etc/passwd | grep -i "^${lUser}:"
else
  echo "INFO - The password '${lPassword}' would be set for the user"
fi

typeset lOutput=$(
echo "

====================================== Summary ======================================
Environment      : ${lDbNickname}
User             : ${lUser}
Comment          : ${lDescription}
Password         : ${lPassword}"
if [ "${lTestRun}" != "YES" ] ; then
  chage -l ${lUser} | grep  "Password expires" | sed 's/[ \t]*:/ :/g'
  chage -l ${lUser} | grep  "Account expires"  | sed 's/[ \t]*:/  :/g'
else
  echo "Password expires : $( date +"%b %d, %Y" -d "+${lPasswordMaximumAge} days" )
Account expires  : $( date +"%b %d, %Y" -d "+${lPasswordMaximumAge} days" )
"
fi
echo "
Connection details:
   - Server      : ${cHostName}.${cHostNamePostfix}
   - Port        : ${lPort}
   - Database    : ${lDatabase}
=====================================================================================" )

echo "${lOutput}"
sendMail "${lDescription}" "${lOutput}" "${lMailTo}"

#
# Finish up
#
set +x
exit 0

