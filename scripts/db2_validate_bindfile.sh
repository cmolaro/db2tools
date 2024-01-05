#!/bin/ksh
#
# Script     : db2_validate_bindfile.sh
# Description: Extract the tables/view/aliases from the content of a bindfile
#                and check whether the components do exist in the database
#
#<header>
#
# Remarks   : Parameters:
#   * Mandatory
#       -I <instance> : Instance name
#       -D <database> : Database name
#       -b <bindfile> : Bind file
#
#   * Optional
#       -U <username> : User name to connect to the database
#       -P <password> : The password matching the user name to connect to the database
#       -s <schema(s)>: Comma separated list of schemas in which the objects do need
#                         to exist
#       -v            : Verbose
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

typeset    cSchemaList="ABS, BABS"
typeset -u cStartStmtPattern="^[ ]*[0-9][0-9]* [ ]*[0-9][0-9]* [ ]*[0-9][0-9]* [ ]*[0-9][0-9]* [ ]*[0-9][0-9]* "
typeset -u cStopStmt="0 0 0 0 0 STOP"

typeset    cCheckObjectExistenceSQL="
  SELECT      TRIM(TABSCHEMA)
           || ','
           || TRIM(TYPE)
    FROM   SYSCAT.TABLES
   WHERE   TABSCHEMA IN ( #PLACEHOLDER_TABSCHEMA# )
     AND   TABNAME = '#PLACEHOLDER_TABNAME#'
    WITH   UR
     FOR   READ ONLY "

#
# Functions
#
  function scriptUsage {

    # Show the options as described above
    printf "\nUsage of the script ${cScriptName}: \n"

    [[ "${gMessage}" != "" ]] && showError
    [[ ${gErrorNo} -eq 0 ]] && gErrorNo=1

    lHeader=$( grep -n '<[/]*header>' ${cScriptName} | awk -F: '{print $1}' | sed -e s'/$/,/g' )
    lHeaderPos=$( echo ${lHeader} | sed -e 's/,$//g' -e 's/ //g' )
    lHeader=$( sed -n ${lHeaderPos}p ${cScriptName} | egrep -v '<[/]*header>|ksh|Description' | uniq | sed -e 's/^#//g' -e 's/^[ ]*Remarks[ ]*://g' )

    gMessage=$( printf "${lHeader}\n\nExiting.\n" )
    showMessage

    set +x
    exit ${gErrorNo}
  }

  function gatherTableList {

    typeset    lBindFileMem="${1}"
    typeset    lStartStmtPattern="${2}"
    typeset    lStopStmt="${3}"

    typeset -u lSkipLine="FALSE"
    typeset -u lPrevLineSkipped="FALSE"
    typeset -u lStartLine=""
    typeset -u lStopLine=""
    typeset -u lGluedStmt=""
    typeset -u lGrepResult=""
    typeset -i lTotalOfTables=""
    typeset -i lTotalOfStmts=$(   echo "${lBindFileMem}" \
                                | grep "${lStartStmtPattern}" \
                                | egrep -v "${lStopStmt}|^$" \
                                | wc -l
                              )
    typeset -i lCurrentStmt=1

    echo "${lBindFileMem}" | while read lCurrentLine
    do
      if [ ${lCurrentStmt} -le ${lTotalOfStmts} ] ; then
        gMessage="Gathering list of tables. Checking statement ${lCurrentStmt}/${lTotalOfStmts}"
      fi
      showIndicator

      lSkipLine="FALSE"
      lStartLine=$(   echo "${lCurrentLine}" \
                    | grep "${lStartStmtPattern}" )
      lStopLine=$(   echo "${lCurrentLine}" \
                   | grep "^${lStopStmt}" )

      if [ "${lStartLine}" != "" -a "${lStopLine}" == "" ] ; then
        for lMatchWord in OPEN CLOSE WHENEVER FETCH STOP ; do
          lGrepResult=$(   echo ${lCurrentLine} \
                         | grep "${lStartStmtPattern}${lMatchWord} " )
          [[ "${lGrepResult}" != "" ]] && lSkipLine="TRUE" && break 1
        done
      elif [ "${lStopLine}" != "" ] ; then
        lSkipLine="TRUE"
      fi
    
      if [ "${lSkipLine}" == "FALSE" -a "${lPrevLineSkipped}" == "TRUE" ] ; then
        lGrepResult=$( echo ${lCurrentLine} | grep "${lStartStmtPattern}" )
        [[ "${lGrepResult}" == "" ]] && lSkipLine="TRUE"
      fi
    
      if [ "${lStartLine}" != "" -a "${lSkipLine}" == "FALSE" ] ; then
        if [ "${lGluedStmt}" != "" ] ; then
          lGluedStmt=$(   echo "${lGluedStmt}" \
                        | sed "s/${lStartStmtPattern}//g; s/)JOIN /) JOIN /g"
                      )
          for lJoinKeyword in INNER OUTER LEFT RIGHT
          do
            lGluedStmt=$(   echo "${lGluedStmt}" \
                          | sed "s/ [ )]*${lJoinKeyword} / /g"
                        )
          done
        fi
        if [ "${lGluedStmt}" != "" ] ; then
          for lSQLKeyword in SELECT FROM WHERE ORDER GROUP JOIN
          do
            lGluedStmt=$(   echo "${lGluedStmt}" \
                          | sed "s/ \(${lSQLKeyword}\) /\n\1 /g"
                        )
          done

          for lSQLKeyword in FROM JOIN
          do
            lCurrentList=$(   echo "${lGluedStmt}" \
                            | grep "^${lSQLKeyword} " \
                            | sed "s/^${lSQLKeyword} //g" \
                            | tr ',' '\n' \
                            | sed 's/^[ ]*//g; s/[ ]*$//g' \
                            | awk -F' ' '{print $1}' \
                            | sort -u
                          )
            lTableList=$(   echo "${lTableList}" \
                          | grep -v '^[ \t]*$' ;
                            echo "${lCurrentList}" \
                          | grep -v '^[ \t]*$'
                        )
          done
        fi
        lGluedStmt=""
      fi
      if [ "${lSkipLine}" == "FALSE" ] ; then
        for lSQLKeyword in SELECT FROM WHERE ORDER GROUP JOIN
        do
          lGluedStmt=$(   echo "${lGluedStmt}" \
                        | sed "s/ \(${lSQLKeyword}\)$/ \1 /"
                      )
        done
        lGluedStmt="${lGluedStmt}${lCurrentLine}"
      fi
    
      [[ "${lStartLine}" != "" ]] && lCurrentStmt=$(( lCurrentStmt + 1 ))

      lPrevLineSkipped="${lSkipLine}"
      set +x
    done
    lTableList=$(   echo "${lTableList}" \
                  | sort -u
                )
    lTotalOfTables=$(   echo "${lTableList}" \
                      | wc -l
                    )
    printf "%80s\r" $( printfRepeatChar " " 80 )
    if [ "${lVerbose}" == "YES" ] ; then
      gMessage="Found ${lTotalOfTables} unique entries in ${lTotalOfStmts} statements"
      showMessage
      echo ""
    fi

    set +x
    return 0
  }

  function checkObjectExistence {

    typeset    lBindFile="${1}"
    typeset -u lDatabase="${2}"
    typeset    lSchemaList="${3}"
    typeset    lTableList="${4}"
    typeset    lLogOutput="${5}"

    typeset    lFQTableList=$(   echo "${lTableList}" \
                               | grep '\.' \
                               | grep -v '^$'
                             )

    typeset -i lReturnCode=0
    typeset    lCheckSQL=""
    typeset    lReturnText=""
    typeset -i lItemsReturned=0
    typeset -i lNumberOfSchemas=0
    typeset    lSchema=""
    typeset    lTable=""

    gDatabase="${lDatabase}"
    handleDb2DbConnect
    lReturnCode=$?
    [[ ${lReturnCode} -ne 0 ]] && set +x && return ${lReturnCode}

    echo "List of missing objects: ${lBindFile}
-----------------------
" >> ${lLogOutput}

    if [ "${lFQTableList}" != "" ] ; then
      for lCurrentTable in ${lTableList} ; do
        lSchema=$( echo "${lCurrentTable}" | cut -d '.' -f1 )
        lTable=$( echo "${lCurrentTable}" | cut -d '.' -f2 )
        gMessage="Checking '${lSchema}'.'${lTable}'"
        showIndicator

        lCheckSQL=$( echo "${cCheckObjectExistenceSQL}" \
                     | sed "s/IN ( #PLACEHOLDER_TABSCHEMA# )/ = '${lSchema}'/" \
                     | sed "s/#PLACEHOLDER_TABNAME#/${lTable}/"
                   )
        lReturnText=$( db2 -x "${lCheckSQL}" 2>&1 )
        lReturnText=$(   echo "${lReturnText}" \
                       | grep -v '^$' \
                       | sed 's/[ ]*//g; s/[ ]*$//g; s/[ ]*,[ ]*/,/g'
                     )
        lItemsReturned=$( echo "${lReturnText}" | wc -l )
        if [ ${lItemsReturned} -eq 1 ] ; then
          gMessage="Checking '${lSchema}'.'${lTable}' --> Found"
          showIndicator
        else
          gMessage="Checking '${lSchema}'.'${lTable}' --> Not found"
          [[ "${lVerbose}" == "YES" ]] && showError || showIndicator
          printf "\t- '${lSchema}'.'${lTable}'\n" >> ${lLogOutput}
        fi
      done
      lTableList=$(   echo "${lTableList}" \
                    | grep -v '\.' \
                    | grep -v '^$'
                  )
    fi

    if [ "${lTableList}" != "" ] ; then
      lSchemaList=$( echo "${lSchemaList}" \
                     | tr -d ' ' \
                     | sed "s/^/'/; s/$/'/; s/,/','/g"
                   )
      lNumberOfSchemas=$(   echo "${lSchemaList}" \
                          | tr ',' '\n' \
                          | wc -l
                        )
      for lCurrentTable in ${lTableList} ; do
        lCheckSQL=$( echo "${cCheckObjectExistenceSQL}" \
                     | sed "s/#PLACEHOLDER_TABSCHEMA#/${lSchemaList}/" \
                     | sed "s/#PLACEHOLDER_TABNAME#/${lCurrentTable}/"
                   )
        lReturnText=$( db2 -x "${lCheckSQL}" 2>&1 )
        lReturnText=$(   echo "${lReturnText}" \
                       | grep -v '^$' \
                       | sed 's/[ ]*//g; s/[ ]*$//g; s/[ ]*,[ ]*/,/g'
                     )
        lItemsReturned=$( echo "${lReturnText}" | wc -l )
        if [ ${lItemsReturned} -eq ${lNumberOfSchemas} ] ; then
          lSchema=$(   echo "${lSchemaList}" \
                     | tr -d "'" \
                     | tr ',' '|' \
                   )
          gMessage="Checking '${lSchema}'.'${lCurrentTable}' --> Found"
        else
          for lSchema in $( echo ${lSchemaList} | tr -d "'" | tr ',' ' ' )
          do
            if [ $( echo "${lReturnText}" | grep "^${lSchema}," | wc -l ) -eq 0 ]
            then
              gMessage="Checking '${lSchema}'.'${lCurrentTable}' --> Not found"
              [[ "${lVerbose}" == "YES" ]] && showError || showIndicator
              printf "\t- '${lSchema}'.'${lCurrentTable}'\n" >> ${lLogOutput}
            fi
          done
        fi
        showIndicator
      done
    fi
    db2 -x "CONNECT RESET" >/dev/null 2>&1

    set +x
    return 0
  }

#
# Primary initialization of commonly used variables
#
typeset    lTimestampToday=$( date "+%Y-%m-%d-%H.%M.%S" )
typeset -l lInstance=""
typeset -u lDatabase=""
typeset    lBindFile=""
typeset    lUsername=""
typeset    lPassword=""
typeset    lSchemaList=""
typeset -i lReturnCode=0
typeset    lDb2Profile=~${lInstance}/sqllib/db2profile

#
# Loading libraries
#

[[ ! -f ${lDb2Profile} ]] && gErrorNo=2 && gMessage="Cannot load ${lDb2Profile}" && scriptUsage
. ${lDb2Profile}

[[ ! -f ${cScriptDir}/common_functions.include ]] && gErrorNo=2 && gMessage="Cannot load ${cScriptDir}/common_functions.include" && scriptUsage
. ${cScriptDir}/common_functions.include

[[ ! -f ${cScriptDir}/db2_common_functions.include ]] && gErrorNo=2 && gMessage="Cannot load ${cScriptDir}/db2_common_functions.include" && scriptUsage
. ${cScriptDir}/db2_common_functions.include

#
# Check for the input parameters
#
  PARS=$*  # Parameters disappear after getopts, so record here for logging later
  OPTIND=1 # Set the index pointer equal to the first parameter
  while getopts "I:D:b:U:P:s:hH" lOption; do
    case ${lOption} in
      I)
        lInstance="${OPTARG}"
        ;;
      D)
        lDatabase="${OPTARG}"
        ;;
      b)
        lBindFile="${OPTARG}"
        ;;
      U)
        lUsername="${OPTARG}"
        ;;
      P)
        lPassword="${OPTARG}"
        ;;
      s)
        lSchemaList="${OPTARG}"
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
[[ "${lInstance}" == "" ]] && gErrorNo=1 && gMessage="Please provide an instance to do the work for" && scriptUsage
[[ "${lDatabase}" == "" ]] && gErrorNo=1 && gMessage="Please provide a database to do the work for" && scriptUsage
[[ "${lBindFile}" == "" ]] && gErrorNo=1 && gMessage="Please provide a bindfile to do the work for" && scriptUsage

#
# Make sure logging can be done properly
#
typeset lLogOutDir="${cLogsDirBase}/${lInstance}/${lDatabase}"
typeset lLogOutput="${lLogOutDir}/${lTimestampToday}_exception_list"
if [ "${lBindFile}" != "" ] ; then
  lLogOutput="${lLogOutput}_$( basename ${lBindFile} ).txt"
fi

mkdir -p ${lLogOutDir} >/dev/null 2>&1
chgrp -R db2admx ${lLogOutDir} >/dev/null 2>&1

rm -f ${lLogOutput} >/dev/null 2>&1
touch ${lLogOutput} >/dev/null 2>&1
lReturnCode=$?
[[ ${lReturnCode} -ne 0 ]] && gErrorNo=4 && gMessage="Cannot create an outputfile" && scriptUsage

#
# Validate the input data
#
[[ ! -f ${lBindFile} ]] && gErrorNo=10 && gMessage="Please provide a bindfile to do the work for" && scriptUsage
[[ "${lSchemaList}" == "" ]] && lSchemaList="${cSchemaList}"

#
# Main - Variable preparation
#
typeset    lBindFileMem=$(   db2bfd -s ${lBindFile} \
                           | grep -v '^$' \
                           | awk "/${cStartStmtPattern}/,/^$/" ;
                             echo "${cStopStmt}"
                         )
typeset    lTableList=""

#
# Main - Get to work
#
if [ $( echo "${lBindFileMem}" | egrep -v "^$|^${cStopStmt}" | wc -l ) -gt 0 ]
then
  gatherTableList "${lBindFileMem}" "${cStartStmtPattern}" "${cStopStmt}"
else
  gErrorNo=11
  gMessage="Nothing useful found in bindfile ${lBindFile}"
  scriptUsage
fi

if [ "${lTableList}" != "" ] ; then
  checkObjectExistence "${lBindFile}" "${lDatabase}" "${lSchemaList}" "${lTableList}" "${lLogOutput}"
else
  gErrorNo=12
  gMessage="Couldn't extract tables, views, aliases or ... from ${lBindFile}"
  scriptUsage
fi
echo ""
ls -l ${lLogOutput}
echo ""

#
# Finish up
#
set +x
return 0
