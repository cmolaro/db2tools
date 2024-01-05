#!/bin/ksh
#
# Script     : db2_reorg.sh
# Description: Runstats, Reorg, Runstats, Rebind and Reduce of tables(paces)
#                within a database
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
#       -s | --schema     : (List of comma separated) schema(s) to handle
#       -t | --table      : (List of comma separated) table(s) to handle
#       -u | --runstats   : Perform run statistics
#       -o | --reorg      : Perform reorganisations on tables and indexes
#                             preceded and followed by a run statistics and
#                             a rebind of packages using one of the tables
#       -i | --reorg-idx  : Perform reorganisations on indexes
#       -b | --rebind     : Rebind packges touching a table in scope; typically
#                             ran after a run statistics as these might have
#                             shifted and thus might be beneficial for the
#                             package to use the newly calculated optimal path
#       -d | --reduce     : Reduce the size of a tablespace; this makes only
#                             sense when the reorganisation has been ran
#       -q | --quiet      : Quiet - show no messages
#       -h | -H | --help  : Help
#
# Note: if not explicitly chosen to run with --runstats, --reorg, --rebind
#       and/or --reduce, then all options will be supposed to be given
#
#</header>

#
# Constants
#
typeset    cCmdSwitchesShort="I:D:U:P:s:t:uoibdqhH"
typeset -l cCmdSwitchesLong="instance:,database:,user:,password:,schema:,table:,runstats,reorg,reorg-idx,rebind,reduce,quiet,help"
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

  function getValidSchemas {

    typeset    lSchemaList="${1}"
    typeset    lTableList="${2}"
    typeset    lReturnedText=""
    typeset -i lReturnCode=0

    typeset    lSql="SELECT SCHEMANAME
                       FROM SYSCAT.SCHEMATA SCHEMA
                      WHERE SCHEMA.OWNERTYPE = 'U'
                        AND EXISTS (
                              SELECT 1
                                FROM SYSCAT.TABLES TABLE
                               WHERE TABLE.TABSCHEMA = SCHEMA.SCHEMANAME
                                 AND TABLE.TYPE      = 'T'
                                 -- ## TABLE PLACE HOLDER ##
                            ) "
    if [ "${lSchemaList}" != "" ] ; then
      lSchemaList=$( echo ${lSchemaList} | sed "s/[ ]*,[ ]*/','/g" )
      lSql="${lSql} AND SCHEMANAME IN ('${lSchemaList}')"
    fi
    if [ "${lTableList}" != "" ] ; then
      lTableList=$( echo ${lTableList} | sed "s/[ ]*,[ ]*/','/g" )
      lSql=$( echo "${lSql}" | sed "s/-- ## TABLE PLACE HOLDER ##/ AND TABNAME IN ('${lTableList}')/g" )
    fi
    lReturnedText=$( db2 -x "${lSql}" )
    lReturnCode=$?

    if [ ${lReturnCode} -eq 0 ] ; then
      lReturnedText=$( echo "${lReturnedText}" | tr -d ' ' )
    else
      lReturnedText=""
    fi

    set +x
    echo ${lReturnedText}
    return ${lReturnCode}

  }

  function getValidTables {

    typeset    lSchemaList="${1}"
    typeset    lTableList="${2}"
    typeset    lReturnedText=""
    typeset -i lReturnCode=0

    typeset    lSql="SELECT TRIM(TABSCHEMA) || '.' || TRIM(TABNAME) || '=' ||
                            CASE WHEN NOT STATISTICS_PROFILE IS NULL
                              THEN '1'
                              ELSE '0'
                            END
                       FROM SYSCAT.TABLES TABLE
                      WHERE TABLE.TYPE    = 'T'
                        AND EXISTS (
                              SELECT 1
                                FROM SYSCAT.SCHEMATA SCHEMA
                               WHERE SCHEMA.OWNERTYPE  = 'U'
                                 AND SCHEMA.SCHEMANAME = TABLE.TABSCHEMA
                            ) "
    if [ "${lSchemaList}" != "" ] ; then
      lSchemaList=$( echo ${lSchemaList} | sed "s/[ ,][ ]*/','/g" )
      lSql="${lSql} AND TABLE.TABSCHEMA IN ('${lSchemaList}')"
    fi
    if [ "${lTableList}" != "" ] ; then
      lTableList=$( echo ${lTableList} | sed "s/[ ,][ ]*/','/g" )
      lSql="${lSql} AND TABLE.TABNAME IN ('${lTableList}')"
    fi
    lReturnedText=$( db2 -x "${lSql} ORDER BY TABLE.TABSCHEMA, TABLE.TABNAME WITH UR FOR READ ONLY" )
    lReturnCode=$?

    if [ ${lReturnCode} -eq 0 ] ; then
      lReturnedText=$( echo "${lReturnedText}" | tr -d ' ' )
      typeset    lTable
      typeset -i lProfile
      for lCurrentFqTable in ${lReturnedText}
      do
        lTable=$( echo "${lCurrentFqTable}" | cut -d '=' -f 1 )
        lProfile=$( echo "${lCurrentFqTable}" | cut -d '=' -f 2 )
        lTableArray[${lTable}]=${lProfile}
      done
    fi

    set +x
    return ${lReturnCode}

  }

  function performRunstats {

    typeset    lReturnedText=""
    typeset -i lReturnCode=0

    typeset    lSchema=$( echo "${1}" | cut -d '.' -f 1 )
    typeset    lTable=$( echo "${1}" | cut -d '.' -f 2 )
    typeset -i lHasProfile=${2}

    if [ ${lHasProfile} == 0 ] ; then
      lReturnedText=$( db2 -v "RUNSTATS ON TABLE "${lSchema}"."${lTable}" ON ALL COLUMNS AND INDEXES ALL" 2>&1 )
    else
      lReturnedText=$( db2 -v "RUNSTATS ON TABLE "${lSchema}"."${lTable}" USE PROFILE" 2>&1 )
    fi
    lReturnCode=$?
    [[ "${lVerbose}" == "YES" ]] && echo "${lReturnedText}"

    set +x
    return ${lReturnCode}

  }

  function performReorg {

    typeset    lReturnedText=""
    typeset -i lReturnCode=0

    typeset    lSchema=$( echo "${1}" | cut -d '.' -f 1 )
    typeset    lTable=$( echo "${1}" | cut -d '.' -f 2 )
    typeset -i lNonPartIdx=${2}

    typeset    lSql="REORG TABLE \"${lSchema}\".\"${lTable}\"
                           ALLOW NO ACCESS
                           LONGLOBDATA"
    lReturnedText=$( db2 -v "${lSql}" 2>&1 )
    lReturnCode=$?
    [[ "${lVerbose}" == "YES" ]] && echo "${lReturnedText}"

    set +x
    return ${lReturnCode}

  }


  function performReorgIdx {

    typeset    lReturnedText=""
    typeset -i lReturnCode=0

    typeset    lSchema=$( echo "${1}" | cut -d '.' -f 1 )
    typeset    lTable=$( echo "${1}" | cut -d '.' -f 2 )
    typeset -i lNonPartIdx=${2}

    typeset    lSql=""

    #
    # - Get a list of indexes that are not partitioned
    #     --> REORG per INDEX
    # - Get a list of indexes and group them per table and partitionname
    #     --> REORG all INDEXES for that table together
    #
    lSql="SELECT DISTINCT
                 TRIM(INDEX.INDSCHEMA) || '.'
              || CASE WHEN NOT PARTITION.DATAPARTITIONNAME IS NULL
                   THEN TRIM(INDEX.TABNAME) || '=1'
                   ELSE TRIM(INDEX.INDNAME) || '=0'
                 END
              || ';'
              || CASE WHEN PARTITION.DATAPARTITIONNAME = 'PART0'
                   THEN PARTITION.DATAPARTITIONNAME
                   ELSE ''
                 END
              || ';'
              || COALESCE( MONTBSP_DP.RECLAIMABLE_SPACE_ENABLED,
                   COALESCE(MONTBSP_TB.RECLAIMABLE_SPACE_ENABLED, '' ) )
            FROM SYSCAT.INDEXES INDEX
            LEFT JOIN SYSCAT.DATAPARTITIONS PARTITION ON (     PARTITION.TABNAME   = INDEX.TABNAME
                                                           AND PARTITION.TABSCHEMA = INDEX.TABSCHEMA )
            LEFT JOIN TABLE( mon_get_tablespace('',-1) ) MONTBSP_DP ON ( MONTBSP_DP.TBSP_ID = PARTITION.TBSPACEID )
           INNER JOIN SYSCAT.TABLES TABLE ON (     TABLE.TABSCHEMA = INDEX.TABSCHEMA
                                               AND TABLE.TABNAME   = INDEX.TABNAME )
            LEFT JOIN TABLE( mon_get_tablespace('',-1) ) MONTBSP_TB ON ( MONTBSP_TB.TBSP_ID = TABLE.TBSPACEID )
           WHERE INDEX.TABSCHEMA = '${lSchema}'
             AND INDEX.TABNAME   = '${lTable}'
            WITH UR
             FOR READ ONLY "

    lReturnedText=$( db2 -x "${lSql}" 2>&1 )
    lReturnCode=$?

    if [ ${lReturnCode} -eq 0 ] ; then
      lReturnedText=$( echo "${lReturnedText}" | tr -d ' ' )

      typeset    lCmdText
      typeset    lIndSchema
      typeset    lIndex
      typeset -i lNoPartIndex
      typeset    lDataPartition
      typeset -i lReclaimable

      for lCurrentIndex in ${lReturnedText}
      do
        lIndSchema=$( echo "${lCurrentIndex}" | cut -d '=' -f 1 | cut -d '.' -f 1 )
        lIndex=$( echo "${lCurrentIndex}" | cut -d '=' -f 1 | cut -d '.' -f 2 | cut -d ';' -f 1 )
        lNoPartIndex=$( echo "${lCurrentIndex}" | cut -d '=' -f 2 | cut -d ';' -f 1 )
        lDataPartition=$( echo "${lCurrentIndex}" | cut -d '=' -f 2 | cut -d ';' -f 2 )
        lReclaimable=$( echo "${lCurrentIndex}" | cut -d '=' -f 2 | cut -d ';' -f 3 )

        if [ ${lNoPartIndex} -eq 0 ] ; then
          if [ ${lReclaimable} -ne 1 ] ; then
            lSql="REORG INDEX \"${lIndSchema}\".\"${lIndex}\" CLEANUP ALL"
          else
            lSql="REORG INDEX \"${lIndSchema}\".\"${lIndex}\" CLEANUP ALL RECLAIM EXTENTS"
          fi
        else
          if [ "${lDataPartition}" == "PART0" ] ; then
            lSql="REORG INDEXES ALL FOR TABLE \"${lSchema}\".\"${lTable}\" ON DATA PARTITION \"PART0\""
          else
            if [ ${lReclaimable} -ne 1 ] ; then
              lSql="REORG INDEXES ALL FOR TABLE \"${lSchema}\".\"${lTable}\" CLEANUP ALL ON ALL DBPARTITIONNUMS"
            else
              lSql="REORG INDEXES ALL FOR TABLE \"${lSchema}\".\"${lTable}\" CLEANUP ALL RECLAIM EXTENTS ON ALL DBPARTITIONNUMS"
            fi
          fi
        fi
        lCmdText=$( db2 -v "${lSql}" 2>&1 )
        [[ "${lVerbose}" == "YES" ]] && echo "${lCmdText}"
      done
    else
      if [ "${lReturnedText}" == "" -a ${lReturnCode} -eq 0 ] ; then
          #
          # No indexes where found and that is fine as well
          #
        lReturnCode=0
      fi
    fi

    set +x
    return ${lReturnCode}

  }


  function performRebind {

    typeset    lReturnedText=""
    typeset -i lReturnCode=0

    typeset    lSchema="${1}"
    typeset    lTableList=$( echo "${2}" | sed "s/,/','/g" )
    typeset    lTmpFile=$(mktemp /tmp/${cBaseNameScript}_${lSchema}.XXXXXX)

    typeset    lCmdText

    lSql="SELECT DISTINCT
                 'REBIND PACKAGE \"' || TRIM(pD.PKGSCHEMA) || '\".\"' ||
                 TRIM(pD.PKGNAME) || '\" VERSION \"' || TRIM(pD.PKGVERSION) || '\";'
            FROM SYSCAT.PACKAGEDEP pD
            JOIN SYSCAT.PACKAGES p ON (     p.PKGNAME    = pD.PKGNAME
                                        AND p.PKGSCHEMA  = pD.PKGSCHEMA
                                        AND p.PKGVERSION = pD.PKGVERSION
                                      )
           WHERE pD.BNAME   IN ('${lTableList}')
             AND pD.BSCHEMA = '${lSchema}'
             AND p.VALID    = 'Y'
             AND p.LAST_BIND_TIME = ( SELECT MAX(p2.LAST_BIND_TIME)
                                        FROM SYSCAT.PACKAGES p2
                                       WHERE p2.PKGNAME   = p.PKGNAME
                                         AND p2.PKGSCHEMA = p.PKGSCHEMA )
           ORDER BY 1
            WITH UR
             FOR READ ONLY "

    lReturnedText=$( db2 -x "${lSql}" 2>&1 )
      echo "${lReturnedText}" \
    | sed 's/\-\-.*$/\n/g; s/ [ ]*/ /g; s/[ ]*$//g' \
    | grep -v '^$' > ${lTmpFile}
    lReturnCode=$?

    if [ ${lReturnCode} -eq 0 -a "${lReturnedText}" != "" ] ; then
      echo "Rebind for ${1}
"
      while read lDb2Cmd
      do
        if [ "${lDb2Cmd}" != "" ] ; then
          lCmdText=$( db2 -tv "${lDb2Cmd}" 2>&1 )
          [[ "${lVerbose}" == "YES" ]] && echo "${lCmdText}"
        fi
      done <${lTmpFile}
      [[ -f ${lTmpFile} ]] && rm -fR ${lTmpFile}
    else
      if [ "${lVerbose}" == "YES" ] ; then
        echo "No packages with table dependencies within schema ${1} found for rebind
"
      fi
    fi

    set +x
    return ${lReturnCode}

  }

  function performReduce {

    typeset    lReturnedText=""
    typeset -i lReturnCode=0

    typeset    lSchema="${1}"
    typeset    lTableList=$( echo "${2}" | sed "s/,/','/g" )
    typeset    lReclaimableTbSp="${3}"

    typeset    lCmdText

    lSql="SELECT DISTINCT TABLE.TBSPACE
              || CASE WHEN NOT TABLE.INDEX_TBSPACE IS NULL
                   THEN x'0A' || TABLE.INDEX_TBSPACE
                   ELSE ''
                 END
              || CASE WHEN NOT TABLE.LONG_TBSPACE IS NULL
                   THEN x'0A' || TABLE.LONG_TBSPACE
                   ELSE ''
                 END
            FROM SYSCAT.TABLES TABLE
           WHERE TABLE.TABNAME   IN ('${lTableList}')
             AND TABLE.TABSCHEMA  = '${lSchema}'
           ORDER BY 1"

    lReturnedText=$( db2 -x "${lSql}" 2>&1 )
    lReturnedText=$( echo "${lReturnedText}" | tr -d ' ' | grep -v '^$' | sort -u )
    lReturnCode=$?

    if [ ${lReturnCode} -eq 0 -a "${lReturnedText}" != "" ] ; then
      for lCurrentTbSp in ${lReturnedText}
      do
        if [ $( echo "${lReclaimableTbSp}" | grep "^${lCurrentTbSp}$" | wc -l ) -gt 0 ] ; then
          lCmdText=$( db2 -v "ALTER TABLESPACE \"${lCurrentTbSp}\" LOWER HIGH WATER MARK" 2>&1 ;
                      db2 -v "ALTER TABLESPACE \"${lCurrentTbSp}\" REDUCE MAX" 2>&1 )
          [[ "${lVerbose}" == "YES" ]] && echo "${lCmdText}"
        else
          if [ "${lVerbose}" == "YES" ] ; then
            echo " - ${lCurrentTbSp} tablespace for which the reclaimable storage attribute is not set"
          fi
        fi
      done
    fi
    set +x
    return ${lReturnCode}

  }

#
# Primary initialization of commonly used variables
#
typeset    lTimestampToday=$( date "+%Y-%m-%d-%H.%M.%S" )
typeset    lDb2Profile=""
typeset    lDb2ProfileHome=""
typeset -l lInstance=""
typeset -u lDatabase=""
typeset    lUsername=""
typeset    lPassword=""
typeset    lSchema=""
typeset    lTable=""
typeset -u lAllPhases="YES"
typeset -u lRunstats="NO"
typeset -u lReorg="NO"
typeset -u lReorgIdx="NO"
typeset -u lRebind="NO"
typeset -u lReduce="NO"
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
                 | sed 's:\(\-\-[a-z_\-]*\)\( \):\1[_]:g; s:\( \)\(\-\-\):[_]\2:g; s: :[blank]:g; s:\[_\]: :g' \
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
      -s | --schema )
        lSchema="${_lCmdValue}"
        shift 2
        ;;
      -t | --table )
        lTable="${_lCmdValue}"
        shift 2
        ;;
      -u | --runstats )
        lRunstats="YES"
        lAllPhases="NO"
        shift 1
        ;;
      -o | --reorg )
        lReorg="YES"
        lAllPhases="NO"
        shift 1
        ;;
      -i | --reorg-idx )
        lReorgIdx="YES"
        lAllPhases="NO"
        shift 1
        ;;
      -b | --rebind )
        lRebind="YES"
        lAllPhases="NO"
        shift 1
        ;;
      -d | --reduce )
        lReduce="YES"
        lAllPhases="NO"
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
[[ "${lInstance}" == "" ]] && gErrorNo=1 && gMessage="Please provide an instance to do the work for" && scriptUsage
[[ "${lDatabase}" == "" ]] && gErrorNo=1 && gMessage="Please provide a database to do the work for" && scriptUsage

#
# Force variable(s) to values within boundaries and set a default when needed
#
[[ "${lVerbose}"  != "NO" ]] && lVerbose="YES"
[[ "${lRunstats}" != "NO" ]] && lRunstats="YES"
[[ "${lReorg}"    != "NO" ]] && lReorg="YES"
[[ "${lReorgIdx}" != "NO" ]] && lReorgIdx="YES"
[[ "${lRebind}"   != "NO" ]] && lRebind="YES"
[[ "${lReduce}"   != "NO" ]] && lReduce="YES"
if [ "${lRunstats}" == "YES" -a "${lReorg}"  == "YES" -a \
     "${lReorgIdx}" == "YES" -a "${lRebind}" == "YES" -a \
     "${lReduce}"   == "YES" ] ; then
  lAllPhases="YES"
fi
if [ "${lAllPhases}" == "YES" ] ; then
  lRunstats="YES"
  lReorg="YES"
  lReorgIdx="YES"
  lRebind="YES"
  lReduce="YES"
fi
if [ "${lVerbose}" == "YES" ] ; then
  echo "-- Work summary -------------------------
Run statistics        : ${lRunstats}
Reorganisation tables : ${lReorg}
Reorganisation indexes: ${lReorgIdx}
Rebind packages       : ${lRebind}
Reduce tablespaces    : ${lReduce}
Schema                : ${lSchema}
Table                 : ${lTable}
-----------------------------------------"
fi

#
# Set default umask
#
umask ${cMasking}

#
# Make sure logging can be done properly
#
  ##  typeset lLogOutputDir="${cLogsDirBase}/${lInstance}/${lDatabase}"
  ##  typeset lLogOutput="${lLogOutputDir}/${lTimestampToday}_ ... .log"
  ##  mkdir -p ${lLogOutputDir} >/dev/null 2>&1
  ##  chgrp -R db2admx ${lLogOutputDir} >/dev/null 2>&1
  ##  rm -f ${lLogOutput} >/dev/null 2>&1
  ##  touch ${lLogOutput} >/dev/null 2>&1
  ##  lReturnCode=$?
  ##  if [ ${lReturnCode} -ne 0 ] ; then
  ##    gErrorNo=4
  ##    gMessage="Cannot create an outputfile ${lLogOutput}"
  ##    scriptUsage
  ##  elif [ "${lVerbose}" == "YES" ] ; then
  ##    echo "Execution log is written to :  ${lLogOutput}"
  ##  fi

#
# Validate the input data
#

#
# Load Db2 library
#
  # Only load when not yet done
loadDb2Profile "${lInstance}"
lReturnCode=$?
[[ ! -f ${gDb2Profile} ]] && gErrorNo=2 && gMessage="Cannot load ${gDb2Profile}" && scriptUsage

#
# Validate the input data
#

#
# Main - Get to work
#
gDatabase="${lDatabase}"
handleDb2DbConnect
lReturnCode=$?
[[ ${lReturnCode} -ne 0 ]] && gErrorNo=5 && gMessage="Cannot connect to ${gDatabase}" && scriptUsage

lSchema=$( getValidSchemas "${lSchema}" "${lTable}" )
lReturnCode=$?
[[ ${lReturnCode} -ne 0 ]] && gErrorNo=6 && gMessage="Cannot find valid schemas" && scriptUsage

typeset -A lTableArray
getValidTables "${lSchema}" "${lTable}"
lReturnCode=$?
[[ ${lReturnCode} -ne 0 ]] && gErrorNo=7 && gMessage="Cannot find valid tables" && scriptUsage

typeset lCurrentSchema=""
typeset lCurrentTable=""
typeset lTableList=""

typeset lReclaimableTbSp=$( db2 -x "SELECT TBSP_NAME FROM TABLE(mon_get_tablespace('',-1)) WHERE RECLAIMABLE_SPACE_ENABLED=1" )
lReclaimableTbSp=$( echo "${lReclaimableTbSp}" | tr -d ' ' )

for lCurrentFqTable in ${!lTableArray[*]}
do
  lCurrentTable=$( echo "${lCurrentFqTable}" | cut -d '.' -f 2 )
  if [ $( echo "${lCurrentFqTable}" | grep "^${lCurrentSchema}\." | wc -l ) -eq 0 ] ; then
    if [ "${lCurrentSchema}" != "" -a "${lTableList}" != "" ] ; then
      if [ "${lRebind}" == "YES" ] ; then
        time ( performRebind "${lCurrentSchema}" "${lTableList}" )
      fi
      if [ "${lReduce}" == "YES" ] ; then
        time ( performReduce "${lCurrentSchema}" "${lTableList}" "${lReclaimableTbSp}" )
      fi
    fi
    lCurrentSchema=$( echo "${lCurrentFqTable}" | cut -d '.' -f 1 )
    lTableList="${lCurrentTable}"
  else
    lTableList="${lTableList},${lCurrentTable}"
  fi

    #
    # Check out: https://dba.stackexchange.com/questions/30231/do-i-need-to-runstats-after-a-reorg-in-db2
    #
  echo "Handling ${lCurrentFqTable}"
  if [ "${lRunstats}" == "YES" ] ; then
    time ( performRunstats "${lCurrentFqTable}" "${lTableArray[${lCurrentFqTable}]}" )
  fi
  if [ "${lReorg}" == "YES" ] ; then
    time ( performReorg    "${lCurrentFqTable}" )
  fi
  if [ "${lReorgIdx}" == "YES" ] ; then
    time ( performReorgIdx "${lCurrentFqTable}" )
  fi
  if [ "${lRunstats}" == "YES" ] ; then
    time ( performRunstats "${lCurrentFqTable}" "${lTableArray[${lCurrentFqTable}]}" )
  fi
done

if [ "${lCurrentSchema}" != "" -a "${lTableList}" != "" ] ; then
  if [ "${lRebind}" == "YES" ] ; then
    time ( performRebind "${lCurrentSchema}" "${lTableList}" )
  fi
  if [ "${lReduce}" == "YES" ] ; then
    time ( performReduce "${lCurrentSchema}" "${lTableList}" "${lReclaimableTbSp}" )
  fi
fi

#
# Finish up
#
handleDb2DbDisconnect
set +x
return 0
