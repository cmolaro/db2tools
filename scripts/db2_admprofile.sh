#!/bin/ksh
#
# Script     : db2_admprofile.sh
# Description: Set the environment specific for Database Administrators
#
#<header>
#
# Remarks   : Parameters:
#   * Mandatory
#       (none)
#
#   * Optional
#       -q | --quiet     : Quiet - show no messages
#       -h | -H | --help : Help
#
#</header>

#
# Constants
#
typeset    cCmdSwitchesShort="qhH"
typeset -l cCmdSwitchesLong="quiet,help"
typeset    cHostName=$( hostname )
typeset -l cWhoAmI=$( whoami )
typeset    cScriptName="${0}"
typeset    cCurrentDir=$( pwd )

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
    echo "${gMessage}"

    set +x
    [[ "${lExitScript}" == "YES" ]] && exit ${gErrorNo}
    return ${gErrorNo}

  }

  function setEnvironment {
    typeset lHostName="${1}"
    typeset lUserName="${2}"
    typeset lUsedShell="${3}"

    case ${lHostName} in
      *)
        export PROMPT_COMMAND="PS1=\"\u@\h:\$(pwd -P) $ \""

        #
        # Check out: https://www.2daygeek.com/get-display-view-colored-colorized-man-pages-linux/
        # 
        export LESS=-R
        export LESS_TERMCAP_md=$'\E[1;34m'

        [[ "${LS_COLORS}" == "" ]] && eval "$( dircolors )"
        if [ "${LS_COLORS}" != "" ] ; then
          export LS_COLORS=$(   echo "${LS_COLORS}" \
                              | sed 's/:ex=[0-9;]*:/:ex=01;36:/g' )
        fi

        ;;

      sla_dunno)
        export lPROMPT_COMMAND="PS1=\"\h:$( pwd -P ) $ \""
        ;;
    esac

    case ${lUserName} in
      w0cppe | w0knng )
        umask 0007                                # files created with rw-rw----
        #alias mkdir='mkdir -p -m ug=rwx -m o=rx'  # directory created with rwxrwxr-x

        export PROMPT_COMMAND="PS1=\"\u@\h:\$(pwd -P) $ \""

        #
        # Check out: https://www.2daygeek.com/get-display-view-colored-colorized-man-pages-linux/
        # 
        export LESS=-R
        export LESS_TERMCAP_md=$'\E[1;34m'

        #
        # Display all colors
        #
        # for (( i = 30; i < 38; i++ )); do
        #   echo -e "\033[0;"$i"m Normal: (0;$i); \033[1;"$i"m Light: (1;$i)"
        # done 

        [[ "${LS_COLORS}" == "" ]] && eval "$( dircolors )"
        if [ "${LS_COLORS}" != "" ] ; then
          export LS_COLORS=$(   echo "${LS_COLORS}" \
                              | sed 's/:ex=[0-9;]*:/:ex=01;36:/g' )
        fi
        ;;
    esac

    #
    # (re-)Bind the reverse search to the CTRL-R key sequence
    #
    if [ "${lUsedShell}" == "bash" ] ; then
      bind '"\C-r": reverse-search-history'
    fi

    set +x
    return 0
  }

  function setAliases {
    typeset lHostName="${1}"
    typeset lUserName="${2}"

    alias ls='ls -a -N --color=tty -T 0'
    alias screen='screen -d -R -S'

    alias cdscript="cd /shared/db2/scripts"
    alias cdlog="cd /shared/db2/logs/"
    alias cdjcl="cd /shared/db2/scripts/jcls"
    alias cdhousekeeping="cd /shared/db2/scripts/jcls/housekeeping"
    case ${lHostName} in
      sla70190 )
        alias cdcheckmk="cd /usr/lib/check_mk_agent/local"
        ;;
    esac
  
    if [ "$( echo ${cWhoAmI} | grep -v 'w[0-9][a-z][a-z]*' )" != "" ] ; then
      alias cdbackup="cd /shared/db2/backups/${lHostName}/${lUserName}"
  
      if [ -d /shared/db2/db2dump/${lHostName}/${lUserName} ] ; then
        alias cddump="cd /shared/db2/db2dump/${cHostName}/${lUserName}"
      elif [ -d /home/${lUserName}/sqllib/db2dump ] ; then
        alias cddump="cd /home/${lUserName}/sqllib/db2dump"
      elif [ -d /shared/db2/db2dump/${lUserName} ] ; then
        alias cddump="cd /shared/db2/db2dump/${lUserName}"
      fi
    else
      alias cdbackup="cd /shared/db2/backups/${HostName}"
    fi

    set +x
    return 0
  }

#
# Primary initialization of commonly used variables
#
typeset -u lVerbose="YES"
typeset -l lUsedShell=$( echo ${SHELL} | tr '/' '\n' | grep -v '^$' | tail -1 )
typeset -i lParentId=0
typeset -i lIsViaSshConnected=0
typeset -i lIsViaScreenConnected=0

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
# Validate the input data
#
[[ "${lVerbose}" != "NO" ]] && lVerbose="YES"

#
# Main - Get to work
#
lParentId=$( ps -ef | grep -v grep | grep "^${cWhoAmI}[ ]* $$" | awk -F ' ' '{print $3}' )
[[ ${lParentId} -eq 0 ]] && lParentId=$( ps -ef | grep -v grep | grep "^${cWhoAmI:0:7}[ +]* $$" | awk -F ' ' '{print $3}' )
[[ ${lParentId} -le 1 ]] && return 0

lIsViaSshConnected=$(   ps -ef \
                      | grep "^[a-zA-Z0-9+_\-]*[ ]* ${lParentId}" \
                      | grep " sshd: [ ]*${cWhoAmI}" \
                      | grep -v '^$' \
                      | wc -l
                    )
if [ ${lIsViaSshConnected} -eq 0 ] ; then
  lIsViaScreenConnected=$(   ps -ef \
                           | grep "^[a-zA-Z0-9+_\-]*[ ]* ${lParentId}" \
                           | grep "^${cWhoAmI} " \
                           | grep " SCREEN " \
                           | grep -v '^$' \
                           | wc -l
                         )
fi

if [ ${lIsViaSshConnected} -gt 0 -o ${lIsViaScreenConnected} -gt 0 ]  ; then
  setEnvironment "${cHostName}" "${cWhoAmI}" "${lUsedShell}"
  setAliases "${cHostName}" "${cWhoAmI}"
fi

#
# Finish up
#
set +x
return 0
