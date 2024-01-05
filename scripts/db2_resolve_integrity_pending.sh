#!/bin/ksh
#
# Script     : db2_resolve_integrity_pending.sh
# Description: Search for tables in 'check integrity pending' state and
#                resolve whenever possible
#
#<header>
#
# Remarks   : Parameters:
#   * Mandatory
#       -I <instance> : Instance name
#       -D <database> : Database name
#
#   * Optional
#       -U <username> : User name to connect to the database
#       -P <password> : The password matching the user name to connect to the database
#       -f            : Force IR by creating exception tables when needed
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

typeset -i cMaxNumberOfLoops=500
typeset -i cMaxNumberOfTablesPerLoop=50
typeset cCheckPendingSQL="
  SELECT COALESCE(    '       \"'
                   || TRIM(TABSCHEMA)
                   || '\".\"'
                   || TRIM(TABNAME)
                   || '\",' , ''
                 )
    FROM TABLE
           ( SELECT TABSCHEMA, TABNAME
               FROM SYSCAT.TABLES
              WHERE CONST_CHECKED LIKE '%N%'
                 OR STATUS = 'C'

             UNION

            SELECT a.REFTABSCHEMA,a.REFTABNAME
              FROM   SYSCAT.REFERENCES a
             INNER JOIN SYSCAT.TABLES b ON (
                              b.TABSCHEMA = a.REFTABSCHEMA
                          AND b.TABNAME   = a.REFTABNAME
                        )
             WHERE EXISTS (
                     SELECT 1
                       FROM SYSCAT.TABLES c
                      WHERE c.TABSCHEMA = a.TABSCHEMA
                        AND c.TABNAME   = a.TABNAME
                        AND (    c.CONST_CHECKED LIKE '%N%'
                             OR  c.STATUS = 'C')
                   )
               AND (    b.CONST_CHECKED LIKE '%N%'
                    OR  b.STATUS       = 'C')
           ) AS TAB( TABSCHEMA, TABNAME )
   ORDER BY TABSCHEMA
   FETCH FIRST ${cMaxNumberOfTablesPerLoop} ROWS ONLY
OPTIMIZE FOR 1 ROW
"

typeset cTableExistsSQL="
  SELECT 1
    FROM SYSCAT.TABLES
   WHERE TABSCHEMA = '#SCHEMA#'
     AND TABNAME = '#TABLE#'
    WITH UR
     FOR READ ONLY
"

typeset cTableFullNameSQL="
  SELECT TRIM(TABSCHEMA) || '.' || TRIM(TABNAME)
    FROM SYSCAT.TABLES
   WHERE TABSCHEMA  = '#SCHEMA#'
     AND TABNAME LIKE '#TABLE#%'
    WITH UR
     FOR READ ONLY
" 

typeset cTableSeparator=","

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

    gMessage=$( printf "${lHeader}\n\nExiting.\n" )
    showMessage

    set +x
    exit ${gErrorNo}
  }

  function removeLastSeparator {

    # In  : Comma separated list (${1})
    #       List with additional items (${2})
    #       Separator (${3})
    # Out : ${lNewList}

    typeset    lOriginalList="${1}"
    typeset    lAdditionalList="${2}"
    typeset    lSeparator="${3}"
    typeset -u lShowDebugInfo="${4}"

    [[ "${lShowDebugInfo}" == "DEBUG" ]] && set -x

    lOriginalList=$(   echo "${lOriginalList}" \
                     | grep -v "^[${lSeparator} \t]*$" )
    typeset lNumberOfItems=$(   echo "${lOriginalList}" \
                              | grep -n "[ \t]*${lSeparator}[ \t]*$" \
                              | sort -nr \
                              | awk -F\: '{print $1}' \
                              | head -1
                            )
    typeset lLineToAdapt=""
    lNewList=""
    # Maybe one single item without an separator is there?
    if [ "${lOriginalList}" != "" -a "${lNumberOfItems}" == "" ] ; then
      if [ $( echo "${lOriginalList}" | wc -l ) -eq 1 ] ; then
        lNumberOfItems=1
      fi
    fi
    if [ "${lNumberOfItems}" != "" ] ; then
      lLineToAdapt=$(   echo "${lOriginalList}" \
                      | sed -n ${lNumberOfItems},${lNumberOfItems}p \
                      | sed "s/[ \t]*${lSeparator}[ \t]*//g" )
      lNumberOfItems=$(( lNumberOfItems - 1 ))
      if [ ${lNumberOfItems} -gt 0 ] ; then
        lNewList=$( echo "${lOriginalList}" | sed -n 1,${lNumberOfItems}p )
      fi
      if [ "${lAdditionalList}" == "" ] ; then
        lLineToAdapt=$( echo "${lLineToAdapt}" | sed "s/${lSeparator}[ ]*$//g" )
      else
        lLineToAdapt=$( echo "${lLineToAdapt}" | sed "s/[ ]*$/ ${lSeparator}/g" )
      fi
      lNewList=$( printf "${lNewList}\n${lLineToAdapt}" | grep -v '^[ \t]*$' )
    else
      lNewList=$( echo "${lOriginalList}" )
    fi

    set +x
    return 0

  }

  function addExceptionTable {

    typeset    lSourceSchema="${1}"
    typeset    lSourceTable="${2}"
    typeset -u lExceptionList="${3}"

    [[ "${lExceptionList}" != "ADD" ]] && lExceptionList="UPDATE"
    if [ "${lExceptionList}" == "UPDATE" -a "${lForExceptionClause}" == "" ] ; then
      set +x
      return 0
    fi
    if [ "${lSourceSchema}" != "" -a "${lSourceTable}" == "" ] ; then
      lSourceTable=$( echo ${lSourceSchema} | cut -d '.' -f 2 )
      lSourceSchema=$( echo ${lSourceSchema} | cut -d '.' -f 1 )
    fi
    if [ "${lSourceSchema}" == "" -o "${lSourceTable}" == "" ] ; then
      set +x
      return 1
    fi

    db2 -x "CREATE TABLE \"${lSourceSchema}\".\"${lSourceTable}_EXCP\"
              LIKE \"${lSourceSchema}\".\"${lSourceTable}\" " 2>&1 >/dev/null
    db2 -x "ALTER TABLE \"${lSourceSchema}\".\"${lSourceTable}_EXCP\"
              ADD COLUMN N1_TIMESTAMP TIMESTAMP
              ADD COLUMN N2_INFO      CLOB(32K) " 2>&1 >/dev/null

    if [ "${lForExceptionClause}" != "" ] ; then
      lForExceptionClause="${lForExceptionClause}, "
    fi
    lForExceptionClause="${lForExceptionClause} IN \"${lSourceSchema}\".\"${lSourceTable}\" USE \"${lSourceSchema}\".\"${lSourceTable}_EXCP\""

    set +x
    return 0
  }

#
# Primary initialization of commonly used variables
#
typeset    lTimestampToday=$( date "+%Y-%m-%d_%H.%M.%S" )
typeset -l lInstance=""
typeset -u lDatabase=""
typeset    lUsername=""
typeset    lPassword=""
typeset -u lForceException="FALSE"
typeset -i lReturnCode=0
typeset    lSchema=""
typeset    lTable=""
typeset    lPreviousSchema=""
typeset    lPreviousTable=""
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
  while getopts "I:D:U:P:fhH" lOption; do
    case ${lOption} in
      I)
        lInstance="${OPTARG}"
        ;;
      D)
        lDatabase="${OPTARG}"
        ;;
      U)
        lUsername="${OPTARG}"
        ;;
      P)
        lPassword="${OPTARG}"
        ;;
      f)
        lForceException="TRUE"
        ;;
      *)
        gMessage=""
        scriptUsage
        ;;
    esac
  done

#
# Check input data
#
[[ "${lInstance}" == "" ]] && gErrorNo=1 && gMessage="Please provide an instance to do the work for" && scriptUsage
[[ "${lDatabase}" == "" ]] && gErrorNo=1 && gMessage="Please provide a database to do the work for" && scriptUsage
[[ "${lForceException}" != "TRUE" ]] && lForceException="FALSE"
#
# Main - Get to work
#

# Connect to the database
gInstance="${lInstance}"
gDatabase="${lDatabase}"
gDb2User="${lUsername}"
gDb2Passwd="${lPassword}"
handleDb2DbConnect
lReturnCode=$?
[[ ${lReturnCode} -ne 0 ]] && gErrorNo=2 && gMessage="Could not connect to the database '${gDatabase}'" && scriptUsage

# Loop over all check pending tables and try to set the integrity
# Due to the ordering this has to be done a few times.
typeset    lLogOutput="${cLogsDirBase}/${cHostName}/${gInstance}/${lTimestampToday}_${gDatabase}.out"
typeset -i lLoopCounter=1
typeset -i lDoneLooping=0
typeset    lQuery=""
typeset    lSqlResult=""
typeset -u lSqlCode=""
typeset    lTableList=""
typeset    lAdditionalTableList=""
typeset -i lNumberOfTables
typeset    lTable=""
typeset -u lReloadTableList="TRUE"
typeset    lForExceptionClause=""

mkdir -p ${cLogsDirBase}/${cHostName}/${gInstance} >/dev/null 2>&1
chgrp -R db2admx ${LogsDirBase}/${cHostName}/${gInstance} >/dev/null 2>&1
rm -f ${lLogOutput} >/dev/null 2>&1
touch ${lLogOutput} >/dev/null 2>&1
lReturnCode=$?
[[ ${lReturnCode} -ne 0 ]] && gErrorNo=4 && gMessage="Cannot create an outputfile (${lLogOutput})" && scriptUsage

while [ ${lDoneLooping} -eq 0 ] ;
do
  # Create the set integrity statements, only check for errors, not warnings (rc > 1)
  if [ "${lReloadTableList}" == "TRUE" ] ; then
    lTableList=$( db2 -x "${cCheckPendingSQL}" 2>&1 )
    lTableList=$( echo "${lTableList}" | sed 's/[ ]*$//g' | grep -v '^$' )
  fi

  lNumberOfTables=$( echo "${lTableList}" | wc -l | tr -d ' ' ) # How many tables?
  if [ ${lNumberOfTables} -ge 1 ] ; then # Remove the comma from the last table
    removeLastSeparator "${lTableList}" "${lAdditionalTableList}" "${cTableSeparator}"
    lTableList="${lNewList}"
  fi

  lQuery=$( echo "SET INTEGRITY FOR" ; \
            echo "${lTableList}" ; \
            echo "${lAdditionalTableList}" ;
            echo "  IMMEDIATE CHECKED"
          )
  if [ "${lForExceptionClause}" != "" ] ; then
    lQuery=$( echo "${lQuery}" ; \
              printf "  FOR EXCEPTION ${lForExceptionClause}\n" ;
            )
  fi
  lQuery=$( echo "${lQuery}" | grep -v '^$' )
  
  #
  # Check to see if any tables are still in check pending by verifying that the
  # size of the output file is equal to 2. If it is, we're done.
  #   --> 2 lines because of the always present sentences:
  #         * SET INTEGRITY FOR
  #         * IMMEDIATE CHECKED
  #
  if [ $( echo "${lQuery}" | grep -v '^$' | sort -u | wc -l ) -eq 2 ] ; then
    lDoneLooping=1
  fi

  if [ ${lDoneLooping} -eq 0 ] ; then
    # Execute the set integrity statements, but ignore errors. If it is an
    # empty file, we will figure that out afterwards so that the loop
    # can stop.
    gMessage=$( printf "\tLoop ${lLoopCounter}" )
    showIndicator

    echo "" >> ${lLogOutput}
    echo "- - - - - $(date +"%d-%m-%Y %H:%M:%S")  - - - - -" >> ${lLogOutput}
    echo "Loop : ${lLoopCounter}" >> ${lLogOutput}
    echo "  Starting the execution of: " >> ${lLogOutput}
    echo "-------------------------------------------------" >> ${lLogOutput}
    echo "${lQuery}" >> ${lLogOutput}
    echo "-------------------------------------------------" >> ${lLogOutput}
    lSqlResult=$( db2 -v "${lQuery}" 2>&1 )
    lSqlResult=$(   echo "${lSqlResult}" \
                  | awk '/IMMEDIATE CHECKED/,/^$/' \
                  | grep -v ' [ \t]*FOR [ \t]*EXCEPTION [ \t]*IN [ \t]*' \
                  | sed -n 2,\$p \
                  | grep -v '^$'
                )
    echo "- - - - - $(date +"%d-%m-%Y %H:%M:%S")  - - - - -" >> ${lLogOutput}
    echo "Loop : ${lLoopCounter}" >> ${lLogOutput}
    echo "  Result of the execution: " >> ${lLogOutput}
    echo "${lSqlResult}" >> ${lLogOutput}

    lSqlCode=$(   echo "${lSqlResult}" \
                | grep '^SQL[0-9][0-9]*N' \
                | cut -d' ' -f1
                )
    #
    # An own brewed $lTableList is at play, do not ruin it
    #
    if [ "${lSqlCode}" == "" -a "${lReloadTableList}" == "FALSE" ] ; then
      lReloadTableList="TRUE"
      lForExceptionClause=""
    fi

    case "${lSqlCode}" in
      "SQL3600N")
          lTableList=""
          lAdditionalTableList=""
          lReloadTableList="TRUE"
          lForExceptionClause=""
          ;;

      "SQL3608N")
          lTable=$(   echo ${lSqlResult} \
                    | awk -F\" '{print $4}' \
                    | tr -d ' ' \
                    | grep -v '^$'
                  )

          gMessage=$( printf "\tLoop ${lLoopCounter} - adding table ${lTable}" )
          showIndicator

          if [ "${lTable}" != "" ] ; then
            lAdditionalTableList=$(   echo "${lAdditionalTableList} ${cTableSeparator} " \
                                    | sed "s/${cTableSeparator}[ ]*${cTableSeparator}/${cTableSeparator}/g" \
                                    | egrep -v "^[ ]*${cTableSeparator}[ ]*$|^$" ;
                                      echo "       ${lTable} ${cTableSeparator}"
                                  )
          fi
          removeLastSeparator "${lAdditionalTableList}" "" "${cTableSeparator}"
          lAdditionalTableList="${lNewList}"

          [[ "${lForceException}" == "TRUE" ]] && addExceptionTable "${lTable}" "" "UPDATE"
          lLoopCounter=$(( lLoopCounter - 1 ))
          ;;

      "SQL0104N")
          gMessage="Unrecoverable error (${lSqlCode})"
          gErrorNo=50
          showError
          exit ${gErrorNo}
          ;;

      "SQL3603N")
          typeset lConstraint=$(   echo "${lSqlResult}" \
                                 | grep -iv 'SET INTEGRITY FOR' \
                                 | awk -F\" '{print $2}' \
                                 | grep -v '^$' )
          lSchema=$(   echo ${lConstraint} \
                    | cut -d '.' -f1 \
                    | tr -d ' '
                  )
          lTable=$(   echo ${lConstraint} \
                    | cut -d '.' -f2 \
                    | tr -d ' '
                  )
          if [ "${lSchema}" == "${lPreviouSchema}" -a \
               "${lTable}"  == "${lPreviousTable}" ] ; then
            lSchema=""
            lTable=""
          fi

          if [ "${lForceException}" == "TRUE" -a \
               "${lSchema}" != "" -a "${lTable}" != "" ] ; then
            gMessage=$( printf "\tTry to circumvent IR errors for \"${lSchema}\".\"${lTable}\" by creating an exception table" )
            showIndicator
            printf "***\nTry to circumvent IR errors for \"${lSchema}\".\"${lTable}\" by creating an exception table\n" >> ${lLogOutput}

            typeset lTableExistsSQL=$(   echo "${cTableExistsSQL}" \
                                       | sed "s/#SCHEMA#/${lSchema}/g; s/#TABLE#/${lTable}/g"
                                     )
            typeset lTableExists=$( db2 -x "${lTableExistsSQL}" 2>&1 )
            lTableExists=$( echo "${lTableExists}" | tr -d ' ' | grep -v '^$' )
            if [ "${lTableExists}" == "1" ] ; then
              addExceptionTable "${lSchema}" "${lTable}" "ADD"

              # Use this table - giving errors - as a starting point as
              #   probably one of its descendants is giving trouble as well
              lTableList="\t\"${lSchema}\".\"${lTable}\" , "
              lAdditionalTableList=""
              lReloadTableList="FALSE"
              printf "***\nResetting the table list to:\n\t${lTableList}\n***" >> ${lLogOutput}
            fi
          else
            gMessage="Unrecoverable error (${lSqlCode})"
            gErrorNo=51
            showError

            db2 ? ${lSqlCode} | sed "s/<name>/${lConstraint}/g" | more
            exit ${gErrorNo}
          fi
          lPreviousSchema="${lSchema}"
          lPreviousTable="${lTable}"
          ;;

      "SQL0101N")
          gMessage="The statement is too long or too complex (${lSqlCode}).\n(Try to put a higher value for the statement heap)"
          gErrorNo=52
          showError
          db2 ? ${lSqlCode} | more
          exit ${gErrorNo}
          ;;

      "SQL0668N")
          typeset lReason=$(   echo "${lSqlResult}" \
                             | awk -F\" '{print $2}' \
                             | tr -d ' ' \
                             | grep -v '^$'
                           )
          lTable=$(   echo ${lSqlResult} \
                    | awk -F\" '{print $4}' \
                    | tr -d ' ' \
                    | grep -v '^$'
                  )
          gMessage="An error (${lSqlCode}, reason code ${lReason}) occured during the load on the table ${lTable}"
          gErrorNo=53
          showError
          echo ""
          read key?"Press any key to read the full explanation..."
          echo ""
          db2 ? ${lSqlCode} | more
          exit ${gErrorNo}
          ;;

      "SQL0290N")
          gMessage="Table space access is not allowed (${lSqlCode})"
          gErrorNo=54
          showError
          typeset lTbspInfo=$( getCurrentTablespaceStateInfo )
          lReturnCode=$?
          [[ ${lReturnCode} -eq 0 ]] && echo "${lTbspInfo}" | sed 's/^/\t-/g'
          echo ""
          exit ${gErrorNo}
          ;;

      "SQL0204N")
		# Table name is chopped off in the error message coming from Db2.
                # A complete name is needed, so try to search if 'one' exists with
                #  a name beginning with what is captured in ${lProblematicTable}
                #
                # Only tables added to ${lAdditionalTableList} could be incomplete
                #  because a result of a previous error
          typeset lProblematicTable=$( echo ${lSqlResult} | awk -F\" '{print $2}' )
          lSchema=$( echo "${lProblematicTable}" | awk -F\. '{print $1}' )
          lTable=$( echo "${lProblematicTable}" | awk -F\. '{print $2"%"}' )

          typeset lTableFullNameSQL=$(   echo "${cTableFullNameSQL}" \
                                       | sed "s/#SCHEMA#/${lSchema}/g; s/#TABLE#/${lTable}/g"
                                     )
          typeset lFullTableName=$( db2 -x "${lTableFullNameSQL}" 2>&1 )
          lFullTableName=$( echo "${lFullTableName}" | sed 's/[ ]*$//g' | grep -v '^$' )
          if [ $( echo "${lFullTableName}" | grep '^SQL[0-9][0-9]*N' | wc -l ) -gt 0 ] ; then
            gMessage="Problem finding the correct table indicated by the name '${lProblematicTable}'"
            gErrorNo=55
            showError
            exit ${gErrorNo}
          fi

          if [ "${lFullTableName}" != "" ] ; then
            lFullTableName="${lFullTableName} ,"
            lAdditionalTableList=$(   echo "${lAdditionalTableList}" \
                                    | sed "s/${lProblematicTable}[ ,]*$/${lFullTableName}/g")

            removeLastSeparator "${lAdditionalTableList}" "" "${cTableSeparator}"
            lAdditionalTableList="${lNewList}"

            lLoopCounter=$(( lLoopCounter - 1 ))
          fi
          ;;
      "SQL0171N")
          gMessage="${lSqlResult})"
          gErrorNo=56
          showError
          exit ${gErrorNo}
          ;;

      "SQL1224N")
                # SQL1224N -  The database manager is not able to accept new requests
          gMessage="The database manager is not able to accept new requests (SQLCODE=${lSqlCode})"
          gErrorNo=60
          showError
          exit ${gErrorNo}
          ;;

      "SQL1024N")
                #  SQL1024N - A database connection does not exist
          gMessage="The database is not available anymore (SQLCODE=${lSqlCode})"
          gErrorNo=65
          showError
          exit ${gErrorNo}
          ;;

      *)
          lAdditionalTableList=""
          ;;
    esac
    db2 -v commit >/dev/null 2>&1

    # If we loop too many times, we need to stop and give an error
    if [ ${lLoopCounter} -eq ${cMaxNumberOfLoops} ] ; then
      gMessage="Looped too many times during resolving check integrity pending state(s)"
      gErrorNo=10
      showError
      exit ${gErrorNo}
    fi
    lLoopCounter=$(( lLoopCounter + 1 ))
  fi
done
echo "Done."

#
# Finish up
#
db2 -v commit > /dev/null 2>&1
db2 connect reset > /dev/null 2>&1

set +x
return 0
