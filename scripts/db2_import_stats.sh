#!/bin/ksh
#
# Script     : db2_import_stats.sh
# Description: Import statistical information into the DDWHPERF database
#
#<header>
#
# Remarks   : Parameters:
#   * Mandatory
#       -I | --instance        : Instance name
#       -D | --database        : Database name
#
#   * Optional
#       -s | --importhostname  : Import data from a specific hostname
#       -i | --importinstance  : Import data from a specific instance
#       -d | --importdatabase  : Import data from a specific database name
#       -U | --user            : User name to connect to the database
#       -P | --password        : The password matching the user name to connect
#                                 to the database
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
typeset    cCmdSwitchesShort="I:D:U:P:a:j:m:c:s:i:d:qhH"
typeset -l cCmdSwitchesLong="instance:,database:,user:,password:,alias:,job:,mailto:,mailcc:,importhostname:,importinstance:,importdatabase:quiet,help"
typeset    cHostName=$( hostname )
typeset    cScriptName="${0}"
typeset    cBaseNameScript=$( basename ${cScriptName} )
typeset    cScriptDir="${cScriptName%/*}"
typeset    cCurrentDir=$( pwd )
typeset    cLogsDirBase="/shared/db2/logs/${cBaseNameScript%.*}/${cHostName}"
typeset    cExportDir="/shared/db2/exports"
typeset    cMailFrom="OCCTEam@allianz.be"
typeset    cDb2CommonSecurityGroup="db2admx"
typeset    cMasking="0002"

[[ "${cScriptDir}" == "." ]] && cScriptDir="${cCurrentDir}"

typeset    cImportNoneErrors="^SQL3109N|^SQL3110N|^SQL3149N^|^SQL3150N|^SQL3153N"

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
               | sed 's/^#//g; s/^[ ]*Remarks[ ]*://g' )

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
    typeset -l lInstance="${2}"
    typeset -u lDatabase="${3}"
    typeset    lErrorNo="${4}"
    typeset    lErrorMsg="${5}"
    typeset -u lExitScript="${6}"

    typeset    lDatabaseId=""
    typeset    lSubject=""

    [[ "${lExitScript}" != "NO" ]] && lExitScript="YES"

    lDatabaseId="${lHostName},${lInstance},${lDatabase}"
    [[ "${lAlias}" != "" ]] && lDatabaseId="${lAlias}=${lDatabaseId}"
    [[ "${lJobName}" == "" ]] && lJobName="Statistics import"
    lSubject="${lJobName} (${lDatabaseId}) - ${cBaseNameScript} failed"

    if [ "${lVerbose}" == "YES" ] ; then
      echo "${lErrorMsg}"
      echo "  Return code: ${lErrorNo}"
    fi

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

  function formatErrorMsg {

    typeset lReturnedText="${1}"
    typeset lTable="${2}"
    typeset lInputFile="${3}"
    typeset lErrorText=""

    lErrorText=$(   echo "${lReturnedText}" \
                  | awk '/^SQL3109N/ { matched = 1 } matched' )
    if [ "${lErrorText}" == "" ] ; then
      lErrorText=$(   echo "${lReturnedText}" \
                    | egrep -v "${cImportNoneErrors}" \
                    | awk '/^SQL3[2-9][0-9]*N/ { matched = 1 } matched' )
    fi
    if [ "${lErrorText}" == "" ] ; then
      lErrorText=$(   echo "${lReturnedText}" \
                    | awk '/^SQL0104N/ { matched = 1 } matched' )
    fi
    if [ "${lErrorText}" != "" ] ; then
      lErrorText="Failed importing ${lInputFile} into ${lTable} ==>

${lErrorText}"
    else
      lErrorText="Failed importing ${lInputFile} into ${lTable}"
    fi

    set +x
    echo "${lErrorText}"
    return 0

  }

  function importGET_PKG_CACHE_STMT {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="ABSDBA.GET_PKG_CACHE_STMT"
    typeset lPattern="*${lTable}.ixf"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.GET_PKG_CACHE_STMT (
              DBNAME
            , HOSTNAME
            , CAPTURE_TIMESTAMP
            , MEMBER
            , SECTION_TYPE
            , INSERT_TIMESTAMP
            , EXECUTABLE_ID
            , PACKAGE_SCHEMA
            , PACKAGE_NAME
            , PACKAGE_VERSION_ID
            , SECTION_NUMBER
            , EFFECTIVE_ISOLATION
            , NUM_EXECUTIONS
            , NUM_EXEC_WITH_METRICS
            , PREP_TIME
            , TOTAL_ACT_TIME
            , TOTAL_ACT_WAIT_TIME
            , TOTAL_CPU_TIME
            , POOL_READ_TIME
            , POOL_WRITE_TIME
            , DIRECT_READ_TIME
            , DIRECT_WRITE_TIME
            , LOCK_WAIT_TIME
            , TOTAL_SECTION_SORT_TIME
            , TOTAL_SECTION_SORT_PROC_TIME
            , TOTAL_SECTION_SORTS
            , LOCK_ESCALS
            , LOCK_WAITS
            , ROWS_MODIFIED
            , ROWS_READ
            , ROWS_RETURNED
            , DIRECT_READS
            , DIRECT_READ_REQS
            , DIRECT_WRITES
            , DIRECT_WRITE_REQS
            , POOL_DATA_L_READS
            , POOL_TEMP_DATA_L_READS
            , POOL_XDA_L_READS
            , POOL_TEMP_XDA_L_READS
            , POOL_INDEX_L_READS
            , POOL_TEMP_INDEX_L_READS
            , POOL_DATA_P_READS
            , POOL_TEMP_DATA_P_READS
            , POOL_XDA_P_READS
            , POOL_TEMP_XDA_P_READS
            , POOL_INDEX_P_READS
            , POOL_TEMP_INDEX_P_READS
            , POOL_DATA_WRITES
            , POOL_XDA_WRITES
            , POOL_INDEX_WRITES
            , TOTAL_SORTS
            , POST_THRESHOLD_SORTS
            , POST_SHRTHRESHOLD_SORTS
            , SORT_OVERFLOWS
            , WLM_QUEUE_TIME_TOTAL
            , WLM_QUEUE_ASSIGNMENTS_TOTAL
            , DEADLOCKS
            , FCM_RECV_VOLUME
            , FCM_RECVS_TOTAL
            , FCM_SEND_VOLUME
            , FCM_SENDS_TOTAL
            , FCM_RECV_WAIT_TIME
            , FCM_SEND_WAIT_TIME
            , LOCK_TIMEOUTS
            , LOG_BUFFER_WAIT_TIME
            , NUM_LOG_BUFFER_FULL
            , LOG_DISK_WAIT_TIME
            , LOG_DISK_WAITS_TOTAL
            , LAST_METRICS_UPDATE
            , NUM_COORD_EXEC
            , NUM_COORD_EXEC_WITH_METRICS
            , VALID
            , TOTAL_ROUTINE_TIME
            , TOTAL_ROUTINE_INVOCATIONS
            , ROUTINE_ID
            , STMT_TYPE_ID
            , QUERY_COST_ESTIMATE
            , STMT_PKG_CACHE_ID
            , COORD_STMT_EXEC_TIME
            , STMT_EXEC_TIME
            , TOTAL_SECTION_TIME
            , TOTAL_SECTION_PROC_TIME
            , TOTAL_ROUTINE_NON_SECT_TIME
            , TOTAL_ROUTINE_NON_SECT_PROC_TIME
            , LOCK_WAITS_GLOBAL
            , LOCK_WAIT_TIME_GLOBAL
            , LOCK_TIMEOUTS_GLOBAL
            , LOCK_ESCALS_MAXLOCKS
            , LOCK_ESCALS_LOCKLIST
            , LOCK_ESCALS_GLOBAL
            , RECLAIM_WAIT_TIME
            , SPACEMAPPAGE_RECLAIM_WAIT_TIME
            , CF_WAITS
            , CF_WAIT_TIME
            , POOL_DATA_GBP_L_READS
            , POOL_DATA_GBP_P_READS
            , POOL_DATA_LBP_PAGES_FOUND
            , POOL_DATA_GBP_INVALID_PAGES
            , POOL_INDEX_GBP_L_READS
            , POOL_INDEX_GBP_P_READS
            , POOL_INDEX_LBP_PAGES_FOUND
            , POOL_INDEX_GBP_INVALID_PAGES
            , POOL_XDA_GBP_L_READS
            , POOL_XDA_GBP_P_READS
            , POOL_XDA_LBP_PAGES_FOUND
            , POOL_XDA_GBP_INVALID_PAGES
            , AUDIT_EVENTS_TOTAL
            , AUDIT_FILE_WRITES_TOTAL
            , AUDIT_FILE_WRITE_WAIT_TIME
            , AUDIT_SUBSYSTEM_WAITS_TOTAL
            , AUDIT_SUBSYSTEM_WAIT_TIME
            , DIAGLOG_WRITES_TOTAL
            , DIAGLOG_WRITE_WAIT_TIME
            , FCM_MESSAGE_RECVS_TOTAL
            , FCM_MESSAGE_RECV_VOLUME
            , FCM_MESSAGE_RECV_WAIT_TIME
            , FCM_MESSAGE_SENDS_TOTAL
            , FCM_MESSAGE_SEND_VOLUME
            , FCM_MESSAGE_SEND_WAIT_TIME
            , FCM_TQ_RECVS_TOTAL
            , FCM_TQ_RECV_VOLUME
            , FCM_TQ_RECV_WAIT_TIME
            , FCM_TQ_SENDS_TOTAL
            , FCM_TQ_SEND_VOLUME
            , FCM_TQ_SEND_WAIT_TIME
            , NUM_LW_THRESH_EXCEEDED
            , THRESH_VIOLATIONS
            , TOTAL_APP_SECTION_EXECUTIONS
            , TOTAL_ROUTINE_USER_CODE_PROC_TIME
            , TOTAL_ROUTINE_USER_CODE_TIME
            , TQ_TOT_SEND_SPILLS
            , EVMON_WAIT_TIME
            , EVMON_WAITS_TOTAL
            , TOTAL_EXTENDED_LATCH_WAIT_TIME
            , TOTAL_EXTENDED_LATCH_WAITS
            , MAX_COORD_STMT_EXEC_TIME
            , MAX_COORD_STMT_EXEC_TIMESTAMP
            , TOTAL_DISP_RUN_QUEUE_TIME
            , QUERY_DATA_TAG_LIST
            , TOTAL_STATS_FABRICATION_TIME
            , TOTAL_STATS_FABRICATIONS
            , TOTAL_SYNC_RUNSTATS_TIME
            , TOTAL_SYNC_RUNSTATS
            , TOTAL_PEDS
            , DISABLED_PEDS
            , POST_THRESHOLD_PEDS
            , TOTAL_PEAS
            , POST_THRESHOLD_PEAS
            , TQ_SORT_HEAP_REQUESTS
            , TQ_SORT_HEAP_REJECTIONS
            , POOL_QUEUED_ASYNC_DATA_REQS
            , POOL_QUEUED_ASYNC_INDEX_REQS
            , POOL_QUEUED_ASYNC_XDA_REQS
            , POOL_QUEUED_ASYNC_TEMP_DATA_REQS
            , POOL_QUEUED_ASYNC_TEMP_INDEX_REQS
            , POOL_QUEUED_ASYNC_TEMP_XDA_REQS
            , POOL_QUEUED_ASYNC_OTHER_REQS
            , POOL_QUEUED_ASYNC_DATA_PAGES
            , POOL_QUEUED_ASYNC_INDEX_PAGES
            , POOL_QUEUED_ASYNC_XDA_PAGES
            , POOL_QUEUED_ASYNC_TEMP_DATA_PAGES
            , POOL_QUEUED_ASYNC_TEMP_INDEX_PAGES
            , POOL_QUEUED_ASYNC_TEMP_XDA_PAGES
            , POOL_FAILED_ASYNC_DATA_REQS
            , POOL_FAILED_ASYNC_INDEX_REQS
            , POOL_FAILED_ASYNC_XDA_REQS
            , POOL_FAILED_ASYNC_TEMP_DATA_REQS
            , POOL_FAILED_ASYNC_TEMP_INDEX_REQS
            , POOL_FAILED_ASYNC_TEMP_XDA_REQS
            , POOL_FAILED_ASYNC_OTHER_REQS
            , PREFETCH_WAIT_TIME
            , PREFETCH_WAITS
            , POOL_DATA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_INDEX_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_XDA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , NUM_WORKING_COPIES
            , IDA_SEND_WAIT_TIME
            , IDA_SENDS_TOTAL
            , IDA_SEND_VOLUME
            , IDA_RECV_WAIT_TIME
            , IDA_RECVS_TOTAL
            , IDA_RECV_VOLUME
            , STMTNO
            , NUM_ROUTINES
            , ROWS_DELETED
            , ROWS_INSERTED
            , ROWS_UPDATED
            , TOTAL_HASH_JOINS
            , TOTAL_HASH_LOOPS
            , HASH_JOIN_OVERFLOWS
            , HASH_JOIN_SMALL_OVERFLOWS
            , POST_SHRTHRESHOLD_HASH_JOINS
            , TOTAL_OLAP_FUNCS
            , OLAP_FUNC_OVERFLOWS
            , INT_ROWS_DELETED
            , INT_ROWS_INSERTED
            , INT_ROWS_UPDATED
            , POOL_COL_L_READS
            , POOL_TEMP_COL_L_READS
            , POOL_COL_P_READS
            , POOL_TEMP_COL_P_READS
            , POOL_COL_LBP_PAGES_FOUND
            , POOL_COL_WRITES
            , POOL_COL_GBP_L_READS
            , POOL_COL_GBP_P_READS
            , POOL_COL_GBP_INVALID_PAGES
            , POOL_COL_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_QUEUED_ASYNC_COL_REQS
            , POOL_QUEUED_ASYNC_TEMP_COL_REQS
            , POOL_QUEUED_ASYNC_COL_PAGES
            , POOL_QUEUED_ASYNC_TEMP_COL_PAGES
            , POOL_FAILED_ASYNC_COL_REQS
            , POOL_FAILED_ASYNC_TEMP_COL_REQS
            , TOTAL_COL_TIME
            , TOTAL_COL_PROC_TIME
            , TOTAL_COL_EXECUTIONS
            , COMM_EXIT_WAIT_TIME
            , COMM_EXIT_WAITS
            , POST_THRESHOLD_HASH_JOINS
            , POOL_DATA_CACHING_TIER_L_READS
            , POOL_INDEX_CACHING_TIER_L_READS
            , POOL_XDA_CACHING_TIER_L_READS
            , POOL_COL_CACHING_TIER_L_READS
            , POOL_DATA_CACHING_TIER_PAGE_WRITES
            , POOL_INDEX_CACHING_TIER_PAGE_WRITES
            , POOL_XDA_CACHING_TIER_PAGE_WRITES
            , POOL_COL_CACHING_TIER_PAGE_WRITES
            , POOL_DATA_CACHING_TIER_PAGE_UPDATES
            , POOL_INDEX_CACHING_TIER_PAGE_UPDATES
            , POOL_XDA_CACHING_TIER_PAGE_UPDATES
            , POOL_COL_CACHING_TIER_PAGE_UPDATES
            , POOL_CACHING_TIER_PAGE_READ_TIME
            , POOL_CACHING_TIER_PAGE_WRITE_TIME
            , POOL_DATA_CACHING_TIER_PAGES_FOUND
            , POOL_INDEX_CACHING_TIER_PAGES_FOUND
            , POOL_XDA_CACHING_TIER_PAGES_FOUND
            , POOL_COL_CACHING_TIER_PAGES_FOUND
            , POOL_DATA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_INDEX_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_XDA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_COL_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_DATA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_INDEX_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_XDA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_COL_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , TOTAL_HASH_GRPBYS
            , HASH_GRPBY_OVERFLOWS
            , POST_THRESHOLD_HASH_GRPBYS
            , POST_THRESHOLD_OLAP_FUNCS
            , SEMANTIC_ENV_ID
            , STMTID
            , PLANID
            , PREP_WARNING
            , PREP_WARNING_REASON
            , POST_THRESHOLD_COL_VECTOR_CONSUMERS
            , TOTAL_COL_VECTOR_CONSUMERS
            , ACTIVE_HASH_GRPBYS_TOP
            , ACTIVE_HASH_JOINS_TOP
            , ACTIVE_OLAP_FUNCS_TOP
            , ACTIVE_PEAS_TOP
            , ACTIVE_PEDS_TOP
            , ACTIVE_SORT_CONSUMERS_TOP
            , ACTIVE_SORTS_TOP
            , ACTIVE_COL_VECTOR_CONSUMERS_TOP
            , SORT_CONSUMER_HEAP_TOP
            , SORT_CONSUMER_SHRHEAP_TOP
            , SORT_HEAP_TOP
            , SORT_SHRHEAP_TOP
            , TOTAL_INDEX_BUILD_TIME
            , TOTAL_INDEX_BUILD_PROC_TIME
            , TOTAL_INDEXES_BUILT
            , FCM_TQ_RECV_WAITS_TOTAL
            , FCM_MESSAGE_RECV_WAITS_TOTAL
            , FCM_TQ_SEND_WAITS_TOTAL
            , FCM_MESSAGE_SEND_WAITS_TOTAL
            , FCM_SEND_WAITS_TOTAL
            , FCM_RECV_WAITS_TOTAL
            , STMT_TEXT
            , COMP_ENV_DESC
            , MAX_COORD_STMT_EXEC_TIME_ARGS
          ) "
    
    if [[ -n "${lImportDatabase}" ]] ; then lPattern="*${lImportDatabase}${lPattern}" ; fi
    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi
 
    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importGET_TABLE_CUMUL {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="ABSDBA.GET_TABLE_CUMUL"
    typeset lPattern="*${lTable}.ixf"
 
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.GET_TABLE_CUMUL (
              TABNAME
            , TABSCHEMA
            , DBNAME
            , HOSTNAME
            , CAPTURE_TIMESTAMP
            , MEMBER
            , TAB_TYPE
            , TAB_FILE_ID
            , DATA_PARTITION_ID
            , TBSP_ID
            , INDEX_TBSP_ID
            , LONG_TBSP_ID
            , TABLE_SCANS
            , ROWS_READ
            , ROWS_INSERTED
            , ROWS_UPDATED
            , ROWS_DELETED
            , OVERFLOW_ACCESSES
            , OVERFLOW_CREATES
            , PAGE_REORGS
            , DATA_OBJECT_L_PAGES
            , LOB_OBJECT_L_PAGES
            , LONG_OBJECT_L_PAGES
            , INDEX_OBJECT_L_PAGES
            , XDA_OBJECT_L_PAGES
            , DBPARTITIONNUM
            , NO_CHANGE_UPDATES
            , LOCK_WAIT_TIME
            , LOCK_WAIT_TIME_GLOBAL
            , LOCK_WAITS
            , LOCK_WAITS_GLOBAL
            , LOCK_ESCALS
            , LOCK_ESCALS_GLOBAL
            , DATA_SHARING_STATE
            , DATA_SHARING_STATE_CHANGE_TIME
            , DATA_SHARING_REMOTE_LOCKWAIT_COUNT
            , DATA_SHARING_REMOTE_LOCKWAIT_TIME
            , DIRECT_WRITES
            , DIRECT_WRITE_REQS
            , DIRECT_READS
            , DIRECT_READ_REQS
            , OBJECT_DATA_L_READS
            , OBJECT_DATA_P_READS
            , OBJECT_DATA_GBP_L_READS
            , OBJECT_DATA_GBP_P_READS
            , OBJECT_DATA_GBP_INVALID_PAGES
            , OBJECT_DATA_LBP_PAGES_FOUND
            , OBJECT_DATA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , OBJECT_XDA_L_READS
            , OBJECT_XDA_P_READS
            , OBJECT_XDA_GBP_L_READS
            , OBJECT_XDA_GBP_P_READS
            , OBJECT_XDA_GBP_INVALID_PAGES
            , OBJECT_XDA_LBP_PAGES_FOUND
            , OBJECT_XDA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , NUM_PAGE_DICT_BUILT
            , STATS_ROWS_MODIFIED
            , RTS_ROWS_MODIFIED
            , COL_OBJECT_L_PAGES
            , TAB_ORGANIZATION
            , OBJECT_COL_L_READS
            , OBJECT_COL_P_READS
            , OBJECT_COL_GBP_L_READS
            , OBJECT_COL_GBP_P_READS
            , OBJECT_COL_GBP_INVALID_PAGES
            , OBJECT_COL_LBP_PAGES_FOUND
            , OBJECT_COL_GBP_INDEP_PAGES_FOUND_IN_LBP
            , NUM_COLUMNS_REFERENCED
            , SECTION_EXEC_WITH_COL_REFERENCES
            , OBJECT_DATA_CACHING_TIER_L_READS
            , OBJECT_DATA_CACHING_TIER_PAGES_FOUND
            , OBJECT_DATA_CACHING_TIER_GBP_INVALID_PAGES
            , OBJECT_DATA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , OBJECT_XDA_CACHING_TIER_L_READS
            , OBJECT_XDA_CACHING_TIER_PAGES_FOUND
            , OBJECT_XDA_CACHING_TIER_GBP_INVALID_PAGES
            , OBJECT_XDA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , OBJECT_COL_CACHING_TIER_L_READS
            , OBJECT_COL_CACHING_TIER_PAGES_FOUND
            , OBJECT_COL_CACHING_TIER_GBP_INVALID_PAGES
            , OBJECT_COL_CACHING_TIER_GBP_INDEP_PAGES_FOUND
          ) "

    if [[ -n "${lImportDatabase}" ]] ; then lPattern="*${lImportDatabase}${lPattern}" ; fi
    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importGET_DATABASE_CUMUL {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="ABSDBA.GET_DATABASE_CUMUL"
    typeset lPattern="*${lTable}.ixf"    
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.GET_DATABASE_CUMUL (
              DBNAME
            , HOSTNAME
            , CAPTURE_TIMESTAMP
            , MEMBER
            , DB_STATUS
            , DB_ACTIVATION_STATE
            , DB_CONN_TIME
            , CATALOG_PARTITION
            , LAST_BACKUP
            , CONNECTIONS_TOP
            , TOTAL_CONS
            , TOTAL_SEC_CONS
            , APPLS_CUR_CONS
            , APPLS_IN_DB2
            , NUM_ASSOC_AGENTS
            , AGENTS_TOP
            , NUM_COORD_AGENTS
            , COORD_AGENTS_TOP
            , NUM_LOCKS_HELD
            , NUM_LOCKS_WAITING
            , LOCK_LIST_IN_USE
            , ACTIVE_SORTS
            , ACTIVE_HASH_JOINS
            , ACTIVE_OLAP_FUNCS
            , DB_PATH
            , ACT_ABORTED_TOTAL
            , ACT_COMPLETED_TOTAL
            , ACT_REJECTED_TOTAL
            , AGENT_WAIT_TIME
            , AGENT_WAITS_TOTAL
            , POOL_DATA_L_READS
            , POOL_INDEX_L_READS
            , POOL_TEMP_DATA_L_READS
            , POOL_TEMP_INDEX_L_READS
            , POOL_TEMP_XDA_L_READS
            , POOL_XDA_L_READS
            , POOL_DATA_P_READS
            , POOL_INDEX_P_READS
            , POOL_TEMP_DATA_P_READS
            , POOL_TEMP_INDEX_P_READS
            , POOL_TEMP_XDA_P_READS
            , POOL_XDA_P_READS
            , POOL_DATA_WRITES
            , POOL_INDEX_WRITES
            , POOL_XDA_WRITES
            , POOL_READ_TIME
            , POOL_WRITE_TIME
            , CLIENT_IDLE_WAIT_TIME
            , DEADLOCKS
            , DIRECT_READS
            , DIRECT_READ_TIME
            , DIRECT_WRITES
            , DIRECT_WRITE_TIME
            , DIRECT_READ_REQS
            , DIRECT_WRITE_REQS
            , FCM_RECV_VOLUME
            , FCM_RECVS_TOTAL
            , FCM_SEND_VOLUME
            , FCM_SENDS_TOTAL
            , FCM_RECV_WAIT_TIME
            , FCM_SEND_WAIT_TIME
            , IPC_RECV_VOLUME
            , IPC_RECV_WAIT_TIME
            , IPC_RECVS_TOTAL
            , IPC_SEND_VOLUME
            , IPC_SEND_WAIT_TIME
            , IPC_SENDS_TOTAL
            , LOCK_ESCALS
            , LOCK_TIMEOUTS
            , LOCK_WAIT_TIME
            , LOCK_WAITS
            , LOG_BUFFER_WAIT_TIME
            , NUM_LOG_BUFFER_FULL
            , LOG_DISK_WAIT_TIME
            , LOG_DISK_WAITS_TOTAL
            , RQSTS_COMPLETED_TOTAL
            , ROWS_MODIFIED
            , ROWS_READ
            , ROWS_RETURNED
            , TCPIP_RECV_VOLUME
            , TCPIP_SEND_VOLUME
            , TCPIP_RECV_WAIT_TIME
            , TCPIP_RECVS_TOTAL
            , TCPIP_SEND_WAIT_TIME
            , TCPIP_SENDS_TOTAL
            , TOTAL_APP_RQST_TIME
            , TOTAL_RQST_TIME
            , WLM_QUEUE_TIME_TOTAL
            , WLM_QUEUE_ASSIGNMENTS_TOTAL
            , TOTAL_RQST_MAPPED_IN
            , TOTAL_RQST_MAPPED_OUT
            , TOTAL_CPU_TIME
            , TOTAL_WAIT_TIME
            , APP_RQSTS_COMPLETED_TOTAL
            , TOTAL_SECTION_SORT_TIME
            , TOTAL_SECTION_SORT_PROC_TIME
            , TOTAL_SECTION_SORTS
            , TOTAL_SORTS
            , POST_THRESHOLD_SORTS
            , POST_SHRTHRESHOLD_SORTS
            , SORT_OVERFLOWS
            , TOTAL_COMPILE_TIME
            , TOTAL_COMPILE_PROC_TIME
            , TOTAL_COMPILATIONS
            , TOTAL_IMPLICIT_COMPILE_TIME
            , TOTAL_IMPLICIT_COMPILE_PROC_TIME
            , TOTAL_IMPLICIT_COMPILATIONS
            , TOTAL_SECTION_TIME
            , TOTAL_SECTION_PROC_TIME
            , TOTAL_APP_SECTION_EXECUTIONS
            , TOTAL_ACT_TIME
            , TOTAL_ACT_WAIT_TIME
            , ACT_RQSTS_TOTAL
            , TOTAL_ROUTINE_TIME
            , TOTAL_ROUTINE_INVOCATIONS
            , TOTAL_COMMIT_TIME
            , TOTAL_COMMIT_PROC_TIME
            , TOTAL_APP_COMMITS
            , INT_COMMITS
            , TOTAL_ROLLBACK_TIME
            , TOTAL_ROLLBACK_PROC_TIME
            , TOTAL_APP_ROLLBACKS
            , INT_ROLLBACKS
            , TOTAL_RUNSTATS_TIME
            , TOTAL_RUNSTATS_PROC_TIME
            , TOTAL_RUNSTATS
            , TOTAL_REORG_TIME
            , TOTAL_REORG_PROC_TIME
            , TOTAL_REORGS
            , TOTAL_LOAD_TIME
            , TOTAL_LOAD_PROC_TIME
            , TOTAL_LOADS
            , CAT_CACHE_INSERTS
            , CAT_CACHE_LOOKUPS
            , PKG_CACHE_INSERTS
            , PKG_CACHE_LOOKUPS
            , THRESH_VIOLATIONS
            , NUM_LW_THRESH_EXCEEDED
            , LOCK_WAITS_GLOBAL
            , LOCK_WAIT_TIME_GLOBAL
            , LOCK_TIMEOUTS_GLOBAL
            , LOCK_ESCALS_MAXLOCKS
            , LOCK_ESCALS_LOCKLIST
            , LOCK_ESCALS_GLOBAL
            , DATA_SHARING_REMOTE_LOCKWAIT_COUNT
            , DATA_SHARING_REMOTE_LOCKWAIT_TIME
            , RECLAIM_WAIT_TIME
            , SPACEMAPPAGE_RECLAIM_WAIT_TIME
            , CF_WAITS
            , CF_WAIT_TIME
            , POOL_DATA_GBP_L_READS
            , POOL_DATA_GBP_P_READS
            , POOL_DATA_LBP_PAGES_FOUND
            , POOL_DATA_GBP_INVALID_PAGES
            , POOL_INDEX_GBP_L_READS
            , POOL_INDEX_GBP_P_READS
            , POOL_INDEX_LBP_PAGES_FOUND
            , POOL_INDEX_GBP_INVALID_PAGES
            , POOL_XDA_GBP_L_READS
            , POOL_XDA_GBP_P_READS
            , POOL_XDA_LBP_PAGES_FOUND
            , POOL_XDA_GBP_INVALID_PAGES
            , AUDIT_EVENTS_TOTAL
            , AUDIT_FILE_WRITES_TOTAL
            , AUDIT_FILE_WRITE_WAIT_TIME
            , AUDIT_SUBSYSTEM_WAITS_TOTAL
            , AUDIT_SUBSYSTEM_WAIT_TIME
            , DIAGLOG_WRITES_TOTAL
            , DIAGLOG_WRITE_WAIT_TIME
            , FCM_MESSAGE_RECVS_TOTAL
            , FCM_MESSAGE_RECV_VOLUME
            , FCM_MESSAGE_RECV_WAIT_TIME
            , FCM_MESSAGE_SENDS_TOTAL
            , FCM_MESSAGE_SEND_VOLUME
            , FCM_MESSAGE_SEND_WAIT_TIME
            , FCM_TQ_RECVS_TOTAL
            , FCM_TQ_RECV_VOLUME
            , FCM_TQ_RECV_WAIT_TIME
            , FCM_TQ_SENDS_TOTAL
            , FCM_TQ_SEND_VOLUME
            , FCM_TQ_SEND_WAIT_TIME
            , TOTAL_ROUTINE_USER_CODE_PROC_TIME
            , TOTAL_ROUTINE_USER_CODE_TIME
            , TQ_TOT_SEND_SPILLS
            , EVMON_WAIT_TIME
            , EVMON_WAITS_TOTAL
            , TOTAL_EXTENDED_LATCH_WAIT_TIME
            , TOTAL_EXTENDED_LATCH_WAITS
            , TOTAL_STATS_FABRICATION_TIME
            , TOTAL_STATS_FABRICATION_PROC_TIME
            , TOTAL_STATS_FABRICATIONS
            , TOTAL_SYNC_RUNSTATS_TIME
            , TOTAL_SYNC_RUNSTATS_PROC_TIME
            , TOTAL_SYNC_RUNSTATS
            , TOTAL_DISP_RUN_QUEUE_TIME
            , TOTAL_PEDS
            , DISABLED_PEDS
            , POST_THRESHOLD_PEDS
            , TOTAL_PEAS
            , POST_THRESHOLD_PEAS
            , TQ_SORT_HEAP_REQUESTS
            , TQ_SORT_HEAP_REJECTIONS
            , POOL_QUEUED_ASYNC_DATA_REQS
            , POOL_QUEUED_ASYNC_INDEX_REQS
            , POOL_QUEUED_ASYNC_XDA_REQS
            , POOL_QUEUED_ASYNC_TEMP_DATA_REQS
            , POOL_QUEUED_ASYNC_TEMP_INDEX_REQS
            , POOL_QUEUED_ASYNC_TEMP_XDA_REQS
            , POOL_QUEUED_ASYNC_OTHER_REQS
            , POOL_QUEUED_ASYNC_DATA_PAGES
            , POOL_QUEUED_ASYNC_INDEX_PAGES
            , POOL_QUEUED_ASYNC_XDA_PAGES
            , POOL_QUEUED_ASYNC_TEMP_DATA_PAGES
            , POOL_QUEUED_ASYNC_TEMP_INDEX_PAGES
            , POOL_QUEUED_ASYNC_TEMP_XDA_PAGES
            , POOL_FAILED_ASYNC_DATA_REQS
            , POOL_FAILED_ASYNC_INDEX_REQS
            , POOL_FAILED_ASYNC_XDA_REQS
            , POOL_FAILED_ASYNC_TEMP_DATA_REQS
            , POOL_FAILED_ASYNC_TEMP_INDEX_REQS
            , POOL_FAILED_ASYNC_TEMP_XDA_REQS
            , POOL_FAILED_ASYNC_OTHER_REQS
            , PREFETCH_WAIT_TIME
            , PREFETCH_WAITS
            , APP_ACT_COMPLETED_TOTAL
            , APP_ACT_ABORTED_TOTAL
            , APP_ACT_REJECTED_TOTAL
            , TOTAL_CONNECT_REQUEST_TIME
            , TOTAL_CONNECT_REQUEST_PROC_TIME
            , TOTAL_CONNECT_REQUESTS
            , TOTAL_CONNECT_AUTHENTICATION_TIME
            , TOTAL_CONNECT_AUTHENTICATION_PROC_TIME
            , TOTAL_CONNECT_AUTHENTICATIONS
            , POOL_DATA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_INDEX_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_XDA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , COMM_EXIT_WAIT_TIME
            , COMM_EXIT_WAITS
            , POOL_ASYNC_DATA_READS
            , POOL_ASYNC_DATA_READ_REQS
            , POOL_ASYNC_DATA_WRITES
            , POOL_ASYNC_INDEX_READS
            , POOL_ASYNC_INDEX_READ_REQS
            , POOL_ASYNC_INDEX_WRITES
            , POOL_ASYNC_XDA_READS
            , POOL_ASYNC_XDA_READ_REQS
            , POOL_ASYNC_XDA_WRITES
            , POOL_NO_VICTIM_BUFFER
            , POOL_LSN_GAP_CLNS
            , POOL_DRTY_PG_STEAL_CLNS
            , POOL_DRTY_PG_THRSH_CLNS
            , VECTORED_IOS
            , PAGES_FROM_VECTORED_IOS
            , BLOCK_IOS
            , PAGES_FROM_BLOCK_IOS
            , UNREAD_PREFETCH_PAGES
            , FILES_CLOSED
            , POOL_ASYNC_DATA_GBP_L_READS
            , POOL_ASYNC_DATA_GBP_P_READS
            , POOL_ASYNC_DATA_LBP_PAGES_FOUND
            , POOL_ASYNC_DATA_GBP_INVALID_PAGES
            , POOL_ASYNC_INDEX_GBP_L_READS
            , POOL_ASYNC_INDEX_GBP_P_READS
            , POOL_ASYNC_INDEX_LBP_PAGES_FOUND
            , POOL_ASYNC_INDEX_GBP_INVALID_PAGES
            , POOL_ASYNC_XDA_GBP_L_READS
            , POOL_ASYNC_XDA_GBP_P_READS
            , POOL_ASYNC_XDA_LBP_PAGES_FOUND
            , POOL_ASYNC_XDA_GBP_INVALID_PAGES
            , POOL_ASYNC_READ_TIME
            , POOL_ASYNC_WRITE_TIME
            , SKIPPED_PREFETCH_DATA_P_READS
            , SKIPPED_PREFETCH_INDEX_P_READS
            , SKIPPED_PREFETCH_XDA_P_READS
            , SKIPPED_PREFETCH_TEMP_DATA_P_READS
            , SKIPPED_PREFETCH_TEMP_INDEX_P_READS
            , SKIPPED_PREFETCH_TEMP_XDA_P_READS
            , SKIPPED_PREFETCH_UOW_DATA_P_READS
            , SKIPPED_PREFETCH_UOW_INDEX_P_READS
            , SKIPPED_PREFETCH_UOW_XDA_P_READS
            , SKIPPED_PREFETCH_UOW_TEMP_DATA_P_READS
            , SKIPPED_PREFETCH_UOW_TEMP_INDEX_P_READS
            , SKIPPED_PREFETCH_UOW_TEMP_XDA_P_READS
            , POOL_ASYNC_DATA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_ASYNC_INDEX_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_ASYNC_XDA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , CACHING_TIER
            , CACHING_TIER_IO_ERRORS
            , POOL_DATA_CACHING_TIER_L_READS
            , POOL_INDEX_CACHING_TIER_L_READS
            , POOL_XDA_CACHING_TIER_L_READS
            , POOL_COL_CACHING_TIER_L_READS
            , POOL_DATA_CACHING_TIER_PAGE_WRITES
            , POOL_INDEX_CACHING_TIER_PAGE_WRITES
            , POOL_XDA_CACHING_TIER_PAGE_WRITES
            , POOL_COL_CACHING_TIER_PAGE_WRITES
            , POOL_DATA_CACHING_TIER_PAGE_UPDATES
            , POOL_INDEX_CACHING_TIER_PAGE_UPDATES
            , POOL_XDA_CACHING_TIER_PAGE_UPDATES
            , POOL_COL_CACHING_TIER_PAGE_UPDATES
            , POOL_CACHING_TIER_PAGE_READ_TIME
            , POOL_CACHING_TIER_PAGE_WRITE_TIME
            , POOL_DATA_CACHING_TIER_PAGES_FOUND
            , POOL_INDEX_CACHING_TIER_PAGES_FOUND
            , POOL_XDA_CACHING_TIER_PAGES_FOUND
            , POOL_COL_CACHING_TIER_PAGES_FOUND
            , POOL_DATA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_INDEX_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_XDA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_COL_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_DATA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_INDEX_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_XDA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_COL_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_ASYNC_DATA_CACHING_TIER_READS
            , POOL_ASYNC_INDEX_CACHING_TIER_READS
            , POOL_ASYNC_XDA_CACHING_TIER_READS
            , POOL_ASYNC_COL_CACHING_TIER_READS
            , POOL_ASYNC_DATA_CACHING_TIER_PAGE_WRITES
            , POOL_ASYNC_INDEX_CACHING_TIER_PAGE_WRITES
            , POOL_ASYNC_XDA_CACHING_TIER_PAGE_WRITES
            , POOL_ASYNC_COL_CACHING_TIER_PAGE_WRITES
            , POOL_ASYNC_DATA_CACHING_TIER_PAGE_UPDATES
            , POOL_ASYNC_INDEX_CACHING_TIER_PAGE_UPDATES
            , POOL_ASYNC_XDA_CACHING_TIER_PAGE_UPDATES
            , POOL_ASYNC_COL_CACHING_TIER_PAGE_UPDATES
            , POOL_ASYNC_DATA_CACHING_TIER_PAGES_FOUND
            , POOL_ASYNC_INDEX_CACHING_TIER_PAGES_FOUND
            , POOL_ASYNC_XDA_CACHING_TIER_PAGES_FOUND
            , POOL_ASYNC_COL_CACHING_TIER_PAGES_FOUND
            , POOL_ASYNC_DATA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_ASYNC_INDEX_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_ASYNC_XDA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_ASYNC_COL_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_ASYNC_DATA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_ASYNC_INDEX_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_ASYNC_XDA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_ASYNC_COL_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , ROWS_DELETED
            , ROWS_INSERTED
            , ROWS_UPDATED
            , TOTAL_HASH_JOINS
            , TOTAL_HASH_LOOPS
            , HASH_JOIN_OVERFLOWS
            , HASH_JOIN_SMALL_OVERFLOWS
            , POST_SHRTHRESHOLD_HASH_JOINS
            , TOTAL_OLAP_FUNCS
            , OLAP_FUNC_OVERFLOWS
            , DYNAMIC_SQL_STMTS
            , STATIC_SQL_STMTS
            , FAILED_SQL_STMTS
            , SELECT_SQL_STMTS
            , UID_SQL_STMTS
            , DDL_SQL_STMTS
            , MERGE_SQL_STMTS
            , XQUERY_STMTS
            , IMPLICIT_REBINDS
            , BINDS_PRECOMPILES
            , INT_ROWS_DELETED
            , INT_ROWS_INSERTED
            , INT_ROWS_UPDATED
            , CALL_SQL_STMTS
            , POOL_COL_L_READS
            , POOL_TEMP_COL_L_READS
            , POOL_COL_P_READS
            , POOL_TEMP_COL_P_READS
            , POOL_COL_LBP_PAGES_FOUND
            , POOL_COL_WRITES
            , POOL_ASYNC_COL_READS
            , POOL_ASYNC_COL_READ_REQS
            , POOL_ASYNC_COL_WRITES
            , POOL_ASYNC_COL_LBP_PAGES_FOUND
            , POOL_COL_GBP_L_READS
            , POOL_COL_GBP_P_READS
            , POOL_COL_GBP_INVALID_PAGES
            , POOL_COL_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_ASYNC_COL_GBP_L_READS
            , POOL_ASYNC_COL_GBP_P_READS
            , POOL_ASYNC_COL_GBP_INVALID_PAGES
            , POOL_ASYNC_COL_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_QUEUED_ASYNC_COL_REQS
            , POOL_QUEUED_ASYNC_TEMP_COL_REQS
            , POOL_QUEUED_ASYNC_COL_PAGES
            , POOL_QUEUED_ASYNC_TEMP_COL_PAGES
            , POOL_FAILED_ASYNC_COL_REQS
            , POOL_FAILED_ASYNC_TEMP_COL_REQS
            , SKIPPED_PREFETCH_COL_P_READS
            , SKIPPED_PREFETCH_TEMP_COL_P_READS
            , SKIPPED_PREFETCH_UOW_COL_P_READS
            , SKIPPED_PREFETCH_UOW_TEMP_COL_P_READS
            , TOTAL_COL_TIME
            , TOTAL_COL_PROC_TIME
            , TOTAL_COL_EXECUTIONS
            , NUM_POOLED_AGENTS
            , POST_THRESHOLD_HASH_JOINS
            , PKG_CACHE_NUM_OVERFLOWS
            , CAT_CACHE_OVERFLOWS
            , TOTAL_ASYNC_RUNSTATS
            , STATS_CACHE_SIZE
            , TOTAL_HASH_GRPBYS
            , HASH_GRPBY_OVERFLOWS
            , POST_THRESHOLD_HASH_GRPBYS
            , ACTIVE_HASH_GRPBYS
            , SORT_HEAP_ALLOCATED
            , SORT_SHRHEAP_ALLOCATED
            , SORT_SHRHEAP_TOP
            , POST_THRESHOLD_OLAP_FUNCS
            , POST_THRESHOLD_COL_VECTOR_CONSUMERS
            , TOTAL_COL_VECTOR_CONSUMERS
            , ACTIVE_HASH_GRPBYS_TOP
            , ACTIVE_HASH_JOINS_TOP
            , ACTIVE_OLAP_FUNCS_TOP
            , ACTIVE_PEAS
            , ACTIVE_PEAS_TOP
            , ACTIVE_PEDS
            , ACTIVE_PEDS_TOP
            , ACTIVE_SORT_CONSUMERS
            , ACTIVE_SORT_CONSUMERS_TOP
            , ACTIVE_SORTS_TOP
            , ACTIVE_COL_VECTOR_CONSUMERS
            , ACTIVE_COL_VECTOR_CONSUMERS_TOP
            , SORT_CONSUMER_HEAP_TOP
            , SORT_CONSUMER_SHRHEAP_TOP
            , SORT_HEAP_TOP
            , TOTAL_BACKUP_TIME
            , TOTAL_BACKUP_PROC_TIME
            , TOTAL_BACKUPS
            , TOTAL_INDEX_BUILD_TIME
            , TOTAL_INDEX_BUILD_PROC_TIME
            , TOTAL_INDEXES_BUILT
            , IDA_SEND_WAIT_TIME
            , IDA_SENDS_TOTAL
            , IDA_SEND_VOLUME
            , IDA_RECV_WAIT_TIME
            , IDA_RECVS_TOTAL
            , IDA_RECV_VOLUME
            , FCM_TQ_RECV_WAITS_TOTAL
            , FCM_MESSAGE_RECV_WAITS_TOTAL
            , FCM_TQ_SEND_WAITS_TOTAL
            , FCM_MESSAGE_SEND_WAITS_TOTAL
            , FCM_SEND_WAITS_TOTAL
            , FCM_RECV_WAITS_TOTAL
          ) "

    if [[ -n "${lImportDatabase}" ]] ; then lPattern="*${lImportDatabase}${lPattern}" ; fi
    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importGET_BP_CUMUL {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="ABSDBA.GET_BP_CUMUL"
    typeset lPattern="*${lTable}.ixf"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.GET_BP_CUMUL (
              BP_NAME
            , DBNAME
            , HOSTNAME
            , CAPTURE_TIMESTAMP
            , MEMBER
            , AUTOMATIC
            , DIRECT_READS
            , DIRECT_READ_REQS
            , DIRECT_WRITES
            , DIRECT_WRITE_REQS
            , POOL_DATA_L_READS
            , POOL_TEMP_DATA_L_READS
            , POOL_XDA_L_READS
            , POOL_TEMP_XDA_L_READS
            , POOL_INDEX_L_READS
            , POOL_TEMP_INDEX_L_READS
            , POOL_DATA_P_READS
            , POOL_TEMP_DATA_P_READS
            , POOL_XDA_P_READS
            , POOL_TEMP_XDA_P_READS
            , POOL_INDEX_P_READS
            , POOL_TEMP_INDEX_P_READS
            , POOL_DATA_WRITES
            , POOL_XDA_WRITES
            , POOL_INDEX_WRITES
            , DIRECT_READ_TIME
            , DIRECT_WRITE_TIME
            , POOL_READ_TIME
            , POOL_WRITE_TIME
            , POOL_ASYNC_DATA_READS
            , POOL_ASYNC_DATA_READ_REQS
            , POOL_ASYNC_DATA_WRITES
            , POOL_ASYNC_INDEX_READS
            , POOL_ASYNC_INDEX_READ_REQS
            , POOL_ASYNC_INDEX_WRITES
            , POOL_ASYNC_XDA_READS
            , POOL_ASYNC_XDA_READ_REQS
            , POOL_ASYNC_XDA_WRITES
            , POOL_NO_VICTIM_BUFFER
            , POOL_LSN_GAP_CLNS
            , POOL_DRTY_PG_STEAL_CLNS
            , POOL_DRTY_PG_THRSH_CLNS
            , VECTORED_IOS
            , PAGES_FROM_VECTORED_IOS
            , BLOCK_IOS
            , PAGES_FROM_BLOCK_IOS
            , UNREAD_PREFETCH_PAGES
            , FILES_CLOSED
            , POOL_DATA_GBP_L_READS
            , POOL_DATA_GBP_P_READS
            , POOL_DATA_LBP_PAGES_FOUND
            , POOL_DATA_GBP_INVALID_PAGES
            , POOL_INDEX_GBP_L_READS
            , POOL_INDEX_GBP_P_READS
            , POOL_INDEX_LBP_PAGES_FOUND
            , POOL_INDEX_GBP_INVALID_PAGES
            , POOL_ASYNC_DATA_GBP_L_READS
            , POOL_ASYNC_DATA_GBP_P_READS
            , POOL_ASYNC_DATA_LBP_PAGES_FOUND
            , POOL_ASYNC_DATA_GBP_INVALID_PAGES
            , POOL_ASYNC_INDEX_GBP_L_READS
            , POOL_ASYNC_INDEX_GBP_P_READS
            , POOL_ASYNC_INDEX_LBP_PAGES_FOUND
            , POOL_ASYNC_INDEX_GBP_INVALID_PAGES
            , POOL_XDA_GBP_L_READS
            , POOL_XDA_GBP_P_READS
            , POOL_XDA_LBP_PAGES_FOUND
            , POOL_XDA_GBP_INVALID_PAGES
            , POOL_ASYNC_XDA_GBP_L_READS
            , POOL_ASYNC_XDA_GBP_P_READS
            , POOL_ASYNC_XDA_LBP_PAGES_FOUND
            , POOL_ASYNC_XDA_GBP_INVALID_PAGES
            , POOL_ASYNC_READ_TIME
            , POOL_ASYNC_WRITE_TIME
            , BP_CUR_BUFFSZ
            , POOL_QUEUED_ASYNC_DATA_REQS
            , POOL_QUEUED_ASYNC_INDEX_REQS
            , POOL_QUEUED_ASYNC_XDA_REQS
            , POOL_QUEUED_ASYNC_TEMP_DATA_REQS
            , POOL_QUEUED_ASYNC_TEMP_INDEX_REQS
            , POOL_QUEUED_ASYNC_TEMP_XDA_REQS
            , POOL_QUEUED_ASYNC_OTHER_REQS
            , POOL_QUEUED_ASYNC_DATA_PAGES
            , POOL_QUEUED_ASYNC_INDEX_PAGES
            , POOL_QUEUED_ASYNC_XDA_PAGES
            , POOL_QUEUED_ASYNC_TEMP_DATA_PAGES
            , POOL_QUEUED_ASYNC_TEMP_INDEX_PAGES
            , POOL_QUEUED_ASYNC_TEMP_XDA_PAGES
            , POOL_FAILED_ASYNC_DATA_REQS
            , POOL_FAILED_ASYNC_INDEX_REQS
            , POOL_FAILED_ASYNC_XDA_REQS
            , POOL_FAILED_ASYNC_TEMP_DATA_REQS
            , POOL_FAILED_ASYNC_TEMP_INDEX_REQS
            , POOL_FAILED_ASYNC_TEMP_XDA_REQS
            , POOL_FAILED_ASYNC_OTHER_REQS
            , SKIPPED_PREFETCH_DATA_P_READS
            , SKIPPED_PREFETCH_INDEX_P_READS
            , SKIPPED_PREFETCH_XDA_P_READS
            , SKIPPED_PREFETCH_TEMP_DATA_P_READS
            , SKIPPED_PREFETCH_TEMP_INDEX_P_READS
            , SKIPPED_PREFETCH_TEMP_XDA_P_READS
            , SKIPPED_PREFETCH_UOW_DATA_P_READS
            , SKIPPED_PREFETCH_UOW_INDEX_P_READS
            , SKIPPED_PREFETCH_UOW_XDA_P_READS
            , SKIPPED_PREFETCH_UOW_TEMP_DATA_P_READS
            , SKIPPED_PREFETCH_UOW_TEMP_INDEX_P_READS
            , SKIPPED_PREFETCH_UOW_TEMP_XDA_P_READS
            , PREFETCH_WAIT_TIME
            , PREFETCH_WAITS
            , POOL_DATA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_INDEX_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_XDA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_ASYNC_DATA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_ASYNC_INDEX_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_ASYNC_XDA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_COL_L_READS
            , POOL_TEMP_COL_L_READS
            , POOL_COL_P_READS
            , POOL_TEMP_COL_P_READS
            , POOL_COL_LBP_PAGES_FOUND
            , POOL_COL_WRITES
            , POOL_ASYNC_COL_READS
            , POOL_ASYNC_COL_READ_REQS
            , POOL_ASYNC_COL_WRITES
            , POOL_ASYNC_COL_LBP_PAGES_FOUND
            , POOL_COL_GBP_L_READS
            , POOL_COL_GBP_P_READS
            , POOL_COL_GBP_INVALID_PAGES
            , POOL_COL_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_ASYNC_COL_GBP_L_READS
            , POOL_ASYNC_COL_GBP_P_READS
            , POOL_ASYNC_COL_GBP_INVALID_PAGES
            , POOL_ASYNC_COL_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_QUEUED_ASYNC_COL_REQS
            , POOL_QUEUED_ASYNC_TEMP_COL_REQS
            , POOL_QUEUED_ASYNC_COL_PAGES
            , POOL_QUEUED_ASYNC_TEMP_COL_PAGES
            , POOL_FAILED_ASYNC_COL_REQS
            , POOL_FAILED_ASYNC_TEMP_COL_REQS
            , SKIPPED_PREFETCH_COL_P_READS
            , SKIPPED_PREFETCH_TEMP_COL_P_READS
            , SKIPPED_PREFETCH_UOW_COL_P_READS
            , SKIPPED_PREFETCH_UOW_TEMP_COL_P_READS
            , BP_PAGES_LEFT_TO_REMOVE
            , BP_TBSP_USE_COUNT
            , POOL_DATA_CACHING_TIER_L_READS
            , POOL_INDEX_CACHING_TIER_L_READS
            , POOL_XDA_CACHING_TIER_L_READS
            , POOL_COL_CACHING_TIER_L_READS
            , POOL_DATA_CACHING_TIER_PAGE_WRITES
            , POOL_INDEX_CACHING_TIER_PAGE_WRITES
            , POOL_XDA_CACHING_TIER_PAGE_WRITES
            , POOL_COL_CACHING_TIER_PAGE_WRITES
            , POOL_DATA_CACHING_TIER_PAGE_UPDATES
            , POOL_INDEX_CACHING_TIER_PAGE_UPDATES
            , POOL_XDA_CACHING_TIER_PAGE_UPDATES
            , POOL_COL_CACHING_TIER_PAGE_UPDATES
            , POOL_CACHING_TIER_PAGE_READ_TIME
            , POOL_CACHING_TIER_PAGE_WRITE_TIME
            , POOL_DATA_CACHING_TIER_PAGES_FOUND
            , POOL_INDEX_CACHING_TIER_PAGES_FOUND
            , POOL_XDA_CACHING_TIER_PAGES_FOUND
            , POOL_COL_CACHING_TIER_PAGES_FOUND
            , POOL_DATA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_INDEX_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_XDA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_COL_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_DATA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_INDEX_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_XDA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_COL_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_ASYNC_DATA_CACHING_TIER_READS
            , POOL_ASYNC_INDEX_CACHING_TIER_READS
            , POOL_ASYNC_XDA_CACHING_TIER_READS
            , POOL_ASYNC_COL_CACHING_TIER_READS
            , POOL_ASYNC_DATA_CACHING_TIER_PAGE_WRITES
            , POOL_ASYNC_INDEX_CACHING_TIER_PAGE_WRITES
            , POOL_ASYNC_XDA_CACHING_TIER_PAGE_WRITES
            , POOL_ASYNC_COL_CACHING_TIER_PAGE_WRITES
            , POOL_ASYNC_DATA_CACHING_TIER_PAGE_UPDATES
            , POOL_ASYNC_INDEX_CACHING_TIER_PAGE_UPDATES
            , POOL_ASYNC_XDA_CACHING_TIER_PAGE_UPDATES
            , POOL_ASYNC_COL_CACHING_TIER_PAGE_UPDATES
            , POOL_ASYNC_DATA_CACHING_TIER_PAGES_FOUND
            , POOL_ASYNC_INDEX_CACHING_TIER_PAGES_FOUND
            , POOL_ASYNC_XDA_CACHING_TIER_PAGES_FOUND
            , POOL_ASYNC_COL_CACHING_TIER_PAGES_FOUND
            , POOL_ASYNC_DATA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_ASYNC_INDEX_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_ASYNC_XDA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_ASYNC_COL_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_ASYNC_DATA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_ASYNC_INDEX_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_ASYNC_XDA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_ASYNC_COL_CACHING_TIER_GBP_INDEP_PAGES_FOUND
          ) "

    if [[ -n "${lImportDatabase}" ]] ; then lPattern="*${lImportDatabase}${lPattern}" ; fi
    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importGET_CONNECTION_INFO {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="ABSDBA.GET_CONNECTION_INFO"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lIngestSQL="
      FORMAT DELIMITED (
        \$HOSTNAME          CHARACTER( 18),
        \$INSTANCENAME      CHARACTER( 18),
        \$DBNAME            CHARACTER( 18),
        \$CAPTURE_TIMESTAMP TIMESTAMP,
        \$CLIENT_WRKSTNNAME CHARACTER(255),
        \$CLIENT_HOSTNAME   CHARACTER(255),
        \$CLIENT_IPADDR     CHARACTER(128),
        \$CLIENT_APPLNAME   CHARACTER(255),
        \$CLIENT_PRDID      CHARACTER(128),
        \$CLIENT_PLATFORM   CHARACTER( 12),
        \$SYSTEM_AUTH_ID    CHARACTER(128),
        \$SESSION_AUTH_ID   CHARACTER(128)
      )
      RESTART OFF
      MERGE INTO ABSDBA.GET_CONNECTION_INFO ON  (
            HOSTNAME        = \$HOSTNAME
        AND INSTANCENAME    = \$INSTANCENAME
        AND DBNAME          = \$DBNAME
        AND COALESCE(CLIENT_WRKSTNNAME, 'NULL') =
              COALESCE(\$CLIENT_WRKSTNNAME, CAST('NULL' as VARCHAR(255)))
        AND COALESCE(CLIENT_HOSTNAME  , 'NULL') =
              COALESCE(\$CLIENT_HOSTNAME  , CAST('NULL' as VARCHAR(255)))
        AND COALESCE(CLIENT_IPADDR    , 'NULL') =
              COALESCE(\$CLIENT_IPADDR    , CAST('NULL' as VARCHAR(128)))
        AND COALESCE(CLIENT_APPLNAME  , 'NULL') =
              COALESCE(\$CLIENT_APPLNAME  , CAST('NULL' as VARCHAR(255)))
        AND COALESCE(CLIENT_PRDID     , 'NULL') =
              COALESCE(\$CLIENT_PRDID     , CAST('NULL' as VARCHAR(128)))
        AND COALESCE(CLIENT_PLATFORM  , 'NULL') =
              COALESCE(\$CLIENT_PLATFORM  , CAST('NULL' as VARCHAR( 12)))
        AND COALESCE(SYSTEM_AUTH_ID   , 'NULL') =
              COALESCE(\$SYSTEM_AUTH_ID   , CAST('NULL' as VARCHAR(128)))
        AND COALESCE(SESSION_AUTH_ID  , 'NULL') =
              COALESCE(\$SESSION_AUTH_ID  , CAST('NULL' as VARCHAR(128)))
      )
      WHEN MATCHED THEN
        UPDATE SET CAPTURE_TIMESTAMP = \$CAPTURE_TIMESTAMP
      WHEN NOT MATCHED THEN
        INSERT VALUES(
          \$HOSTNAME, \$INSTANCENAME, \$DBNAME, \$CAPTURE_TIMESTAMP,
          \$CLIENT_WRKSTNNAME, \$CLIENT_HOSTNAME, \$CLIENT_IPADDR,
          \$CLIENT_APPLNAME, \$CLIENT_PRDID, \$CLIENT_PLATFORM,
          \$SYSTEM_AUTH_ID, \$SESSION_AUTH_ID
      ) "

    typeset lFileList=$( ls ${cExportDir}/*_${lTable}.del 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern *_${lTable}.del"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    db2 -v "INGEST SET commit_count 1000" >/dev/null 2>&1
    db2 -v "INGEST SET commit_period   0" >/dev/null 2>&1
    db2 -v "INGEST SET shm_max_size 2 GB" >/dev/null 2>&1

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$(
        db2 -v "INGEST DATA FROM FILE ${lInputFile} ${lIngestSQL}"
      )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | egrep '^SQL3[2-9][0-9]*N|^SQL0104N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi

      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importGET_DBCFG {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="SYSIBMADM.DBCFG"
    typeset lPattern="*${lTable}.ixf"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.GET_DBCFG (
              HOSTNAME
            , INSTANCENAME
            , DBNAME
            , CAPTURE_TIMESTAMP
            , NAME
            , \"VALUE\"
            , VALUE_FLAGS
            , DEFERRED_VALUE
            , DEFERRED_VALUE_FLAGS
            , DATATYPE
            , \"DBPARTITIONNUM\"
            , MEMBER
          ) "

    if [[ -n "${lImportDatabase}" ]] ; then lPattern="*${lImportDatabase}${lPattern}" ; fi
    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    typeset lFileList=$( ls ${cExportDir}/*_${lTable}.ixf 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern *_${lTable}.ixf"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importGET_DBMCFG {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="SYSIBMADM.DBMCFG"
    typeset lPattern="*${lTable}.ixf"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.GET_DBMCFG (
              HOSTNAME
            , INSTANCENAME
            , CAPTURE_TIMESTAMP
            , NAME
            , \"VALUE\"
            , VALUE_FLAGS
            , DEFERRED_VALUE
            , DEFERRED_VALUE_FLAGS
            , DATATYPE
          ) "

    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile}"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile}" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importGET_REG_VARIABLES {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="SYSIBMADM.REG_VARIABLES"
    typeset lPattern="*${lTable}.ixf"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.GET_REG_VARIABLES (
              HOSTNAME
            , INSTANCENAME
            , CAPTURE_TIMESTAMP
            , REG_VAR_NAME
            , REG_VAR_VALUE
            , IS_AGGREGATE
            , AGGREGATE_NAME
            , LEVEL
            , DBPARTITIONNUM
          ) "

    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    typeset lFileList=$( ls ${cExportDir}/*_${lTable}.ixf 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern *_${lTable}.ixf"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile}"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile}" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importGET_DBSIZE_INFO {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="SYSTOOLS.STMG_DBSIZE_INFO"
    typeset lPattern="*${lTable}.ixf"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.DBSIZE_INFO (
              HOSTNAME
            , INSTANCENAME
            , CAPTURE_TIMESTAMP
            , DBNAME
            , SNAPSHOT_TIMESTAMP
            , DBSIZE
            , DBCAPACITY
          ) "

    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    typeset lFileList=$( ls ${cExportDir}/*_${lTable}.ixf 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern *_${lTable}.ixf"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile}"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile}" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importTHR_VIOL_EV {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="ABSDBA.THRESHOLDVIOLATIONS_THRESHOLD_EV"
    typeset lPattern="*${lTable}.ixf"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.THRESHOLDVIOLATIONS_THRESHOLD_EV (
             DBNAME
            , HOSTNAME
            , PARTITION_KEY
            , ACTIVATE_TIMESTAMP
            , ACTIVITY_COLLECTED
            , ACTIVITY_ID
            , AGENT_ID
            , APPL_ID
            , APPLICATION_NAME
            , CLIENT_ACCTNG
            , CLIENT_APPLNAME
            , CLIENT_HOSTNAME
            , CLIENT_PID
            , CLIENT_PLATFORM
            , CLIENT_PORT_NUMBER
            , CLIENT_PRDID
            , CLIENT_PROTOCOL
            , CLIENT_USERID
            , CLIENT_WRKSTNNAME
            , CONNECTION_START_TIME
            , COORD_PARTITION_NUM
            , DESTINATION_SERVICE_CLASS_ID
            , PARTITION_NUMBER
            , SESSION_AUTH_ID
            , SOURCE_SERVICE_CLASS_ID
            , SYSTEM_AUTH_ID
            , THRESHOLD_ACTION
            , THRESHOLD_MAXVALUE
            , THRESHOLD_PREDICATE
            , THRESHOLD_QUEUESIZE
            , THRESHOLDID
            , TIME_OF_VIOLATION
            , UOW_ID
            , WORKLOAD_ID  
          ) "

    if [[ -n "${lImportDatabase}" ]] ; then lPattern="*${lImportDatabase}${lPattern}" ; fi
    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importTHR_ACTIVI_EV {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="ABSDBA.ACTIVITY_THRESHOLD_ACTIVI_EV"
    typeset lPattern="*${lTable}.ixf"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.ACTIVITY_THRESHOLD_ACTIVI_EV (
             DBNAME
            , HOSTNAME
            , PARTITION_KEY
            , ACT_EXEC_TIME
            , ACTIVATE_TIMESTAMP
            , ACTIVE_COL_VECTOR_CONSUMERS_TOP
            , ACTIVE_HASH_GRPBYS_TOP
            , ACTIVE_HASH_JOINS_TOP
            , ACTIVE_OLAP_FUNCS_TOP
            , ACTIVE_PEAS_TOP
            , ACTIVE_PEDS_TOP
            , ACTIVE_SORT_CONSUMERS_TOP
            , ACTIVE_SORTS_TOP
            , ACTIVITY_ID
            , ACTIVITY_SECONDARY_ID
            , ACTIVITY_TYPE
            , ADDRESS
            , AGENT_ID
            , APPL_ID
            , APPL_NAME
            , ARM_CORRELATOR
            , COORD_PARTITION_NUM
            , DB_WORK_ACTION_SET_ID
            , DB_WORK_CLASS_ID
            , DETAILS_XML
            , MON_INTERVAL_ID
            , NUM_REMAPS
            , PARENT_ACTIVITY_ID
            , PARENT_UOW_ID
            , PARTIAL_RECORD
            , PARTITION_NUMBER
            , POOL_DATA_L_READS
            , POOL_DATA_P_READS
            , POOL_INDEX_L_READS
            , POOL_INDEX_P_READS
            , POOL_TEMP_DATA_L_READS
            , POOL_TEMP_DATA_P_READS
            , POOL_TEMP_INDEX_L_READS
            , POOL_TEMP_INDEX_P_READS
            , POOL_TEMP_XDA_L_READS
            , POOL_TEMP_XDA_P_READS
            , POOL_XDA_L_READS
            , POOL_XDA_P_READS
            , PREP_TIME
            , QUERY_ACTUAL_DEGREE
            , QUERY_CARD_ESTIMATE
            , QUERY_COST_ESTIMATE
            , QUERY_DATA_TAG_LIST
            , ROWS_FETCHED
            , ROWS_MODIFIED
            , ROWS_RETURNED
            , SC_WORK_ACTION_SET_ID
            , SC_WORK_CLASS_ID
            , SECTION_ACTUALS
            , SERVICE_SUBCLASS_NAME
            , SERVICE_SUPERCLASS_NAME
            , SESSION_AUTH_ID
            , SORT_CONSUMER_HEAP_TOP
            , SORT_CONSUMER_SHRHEAP_TOP
            , SORT_HEAP_TOP
            , SORT_OVERFLOWS
            , SORT_SHRHEAP_TOP
            , SQLCABC
            , SQLCAID
            , SQLCODE
            , SQLERRD1
            , SQLERRD2
            , SQLERRD3
            , SQLERRD4
            , SQLERRD5
            , SQLERRD6
            , SQLERRM
            , SQLERRP
            , SQLSTATE
            , SQLWARN
            , SYSTEM_CPU_TIME
            , TIME_COMPLETED
            , TIME_CREATED
            , TIME_STARTED
            , TOTAL_SORT_TIME
            , TOTAL_SORTS
            , TOTAL_STATS_FABRICATION_TIME
            , TOTAL_STATS_FABRICATIONS
            , TOTAL_SYNC_RUNSTATS
            , TOTAL_SYNC_RUNSTATS_TIME
            , TPMON_ACC_STR
            , TPMON_CLIENT_APP
            , TPMON_CLIENT_USERID
            , TPMON_CLIENT_WKSTN
            , UOW_ID
            , USER_CPU_TIME
            , WL_WORK_ACTION_SET_ID
            , WL_WORK_CLASS_ID
            , WORKLOAD_ID
            , WORKLOAD_OCCURRENCE_ID
          ) "

    if [[ -n "${lImportDatabase}" ]] ; then lPattern="*${lImportDatabase}${lPattern}" ; fi
    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importTHR_ACTIVI_EV_METRICS {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="ABSDBA.ACTIVITYMETRICS_THRESHOLD_ACTIVI_EV"
    typeset lPattern="*${lTable}.ixf"     
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.ACTIVITYMETRICS_THRESHOLD_ACTIVI_EV (
             DBNAME
            , HOSTNAME
            , PARTITION_KEY
            , ACTIVATE_TIMESTAMP
            , ACTIVITY_ID
            , ACTIVITY_SECONDARY_ID
            , APPL_ID
            , PARTITION_NUMBER
            , UOW_ID
            , WLM_QUEUE_TIME_TOTAL
            , WLM_QUEUE_ASSIGNMENTS_TOTAL
            , FCM_TQ_RECV_WAIT_TIME
            , FCM_MESSAGE_RECV_WAIT_TIME
            , FCM_TQ_SEND_WAIT_TIME
            , FCM_MESSAGE_SEND_WAIT_TIME
            , LOCK_WAIT_TIME
            , LOCK_WAITS
            , DIRECT_READ_TIME
            , DIRECT_READ_REQS
            , DIRECT_WRITE_TIME
            , DIRECT_WRITE_REQS
            , LOG_BUFFER_WAIT_TIME
            , NUM_LOG_BUFFER_FULL
            , LOG_DISK_WAIT_TIME
            , LOG_DISK_WAITS_TOTAL
            , POOL_WRITE_TIME
            , POOL_READ_TIME
            , AUDIT_FILE_WRITE_WAIT_TIME
            , AUDIT_FILE_WRITES_TOTAL
            , AUDIT_SUBSYSTEM_WAIT_TIME
            , AUDIT_SUBSYSTEM_WAITS_TOTAL
            , DIAGLOG_WRITE_WAIT_TIME
            , DIAGLOG_WRITES_TOTAL
            , FCM_SEND_WAIT_TIME
            , FCM_RECV_WAIT_TIME
            , TOTAL_ACT_WAIT_TIME
            , TOTAL_SECTION_SORT_PROC_TIME
            , TOTAL_SECTION_SORTS
            , TOTAL_SECTION_SORT_TIME
            , TOTAL_ACT_TIME
            , ROWS_READ
            , ROWS_MODIFIED
            , POOL_DATA_L_READS
            , POOL_INDEX_L_READS
            , POOL_TEMP_DATA_L_READS
            , POOL_TEMP_INDEX_L_READS
            , POOL_XDA_L_READS
            , POOL_TEMP_XDA_L_READS
            , TOTAL_CPU_TIME
            , POOL_DATA_P_READS
            , POOL_TEMP_DATA_P_READS
            , POOL_XDA_P_READS
            , POOL_TEMP_XDA_P_READS
            , POOL_INDEX_P_READS
            , POOL_TEMP_INDEX_P_READS
            , POOL_DATA_WRITES
            , POOL_XDA_WRITES
            , POOL_INDEX_WRITES
            , DIRECT_READS
            , DIRECT_WRITES
            , ROWS_RETURNED
            , DEADLOCKS
            , LOCK_TIMEOUTS
            , LOCK_ESCALS
            , FCM_SENDS_TOTAL
            , FCM_RECVS_TOTAL
            , FCM_SEND_VOLUME
            , FCM_RECV_VOLUME
            , FCM_MESSAGE_SENDS_TOTAL
            , FCM_MESSAGE_RECVS_TOTAL
            , FCM_MESSAGE_SEND_VOLUME
            , FCM_MESSAGE_RECV_VOLUME
            , FCM_TQ_SENDS_TOTAL
            , FCM_TQ_RECVS_TOTAL
            , FCM_TQ_SEND_VOLUME
            , FCM_TQ_RECV_VOLUME
            , TQ_TOT_SEND_SPILLS
            , POST_THRESHOLD_SORTS
            , POST_SHRTHRESHOLD_SORTS
            , SORT_OVERFLOWS
            , AUDIT_EVENTS_TOTAL
            , TOTAL_SORTS
            , STMT_EXEC_TIME
            , COORD_STMT_EXEC_TIME
            , TOTAL_ROUTINE_NON_SECT_PROC_TIME
            , TOTAL_ROUTINE_NON_SECT_TIME
            , TOTAL_SECTION_PROC_TIME
            , TOTAL_APP_SECTION_EXECUTIONS
            , TOTAL_SECTION_TIME
            , TOTAL_ROUTINE_USER_CODE_PROC_TIME
            , TOTAL_ROUTINE_USER_CODE_TIME
            , TOTAL_ROUTINE_TIME
            , THRESH_VIOLATIONS
            , NUM_LW_THRESH_EXCEEDED
            , TOTAL_ROUTINE_INVOCATIONS
            , LOCK_WAIT_TIME_GLOBAL
            , LOCK_WAITS_GLOBAL
            , RECLAIM_WAIT_TIME
            , SPACEMAPPAGE_RECLAIM_WAIT_TIME
            , LOCK_TIMEOUTS_GLOBAL
            , LOCK_ESCALS_MAXLOCKS
            , LOCK_ESCALS_LOCKLIST
            , LOCK_ESCALS_GLOBAL
            , CF_WAIT_TIME
            , CF_WAITS
            , POOL_DATA_GBP_L_READS
            , POOL_DATA_GBP_P_READS
            , POOL_DATA_LBP_PAGES_FOUND
            , POOL_DATA_GBP_INVALID_PAGES
            , POOL_INDEX_GBP_L_READS
            , POOL_INDEX_GBP_P_READS
            , POOL_INDEX_LBP_PAGES_FOUND
            , POOL_INDEX_GBP_INVALID_PAGES
            , POOL_XDA_GBP_L_READS
            , POOL_XDA_GBP_P_READS
            , POOL_XDA_LBP_PAGES_FOUND
            , POOL_XDA_GBP_INVALID_PAGES
            , EVMON_WAIT_TIME
            , EVMON_WAITS_TOTAL
            , TOTAL_EXTENDED_LATCH_WAIT_TIME
            , TOTAL_EXTENDED_LATCH_WAITS
            , TOTAL_DISP_RUN_QUEUE_TIME
            , POOL_QUEUED_ASYNC_DATA_REQS
            , POOL_QUEUED_ASYNC_INDEX_REQS
            , POOL_QUEUED_ASYNC_XDA_REQS
            , POOL_QUEUED_ASYNC_TEMP_DATA_REQS
            , POOL_QUEUED_ASYNC_TEMP_INDEX_REQS
            , POOL_QUEUED_ASYNC_TEMP_XDA_REQS
            , POOL_QUEUED_ASYNC_OTHER_REQS
            , POOL_QUEUED_ASYNC_DATA_PAGES
            , POOL_QUEUED_ASYNC_INDEX_PAGES
            , POOL_QUEUED_ASYNC_XDA_PAGES
            , POOL_QUEUED_ASYNC_TEMP_DATA_PAGES
            , POOL_QUEUED_ASYNC_TEMP_INDEX_PAGES
            , POOL_QUEUED_ASYNC_TEMP_XDA_PAGES
            , POOL_FAILED_ASYNC_DATA_REQS
            , POOL_FAILED_ASYNC_INDEX_REQS
            , POOL_FAILED_ASYNC_XDA_REQS
            , POOL_FAILED_ASYNC_TEMP_DATA_REQS
            , POOL_FAILED_ASYNC_TEMP_INDEX_REQS
            , POOL_FAILED_ASYNC_TEMP_XDA_REQS
            , POOL_FAILED_ASYNC_OTHER_REQS
            , TOTAL_PEDS
            , DISABLED_PEDS
            , POST_THRESHOLD_PEDS
            , TOTAL_PEAS
            , POST_THRESHOLD_PEAS
            , TQ_SORT_HEAP_REQUESTS
            , TQ_SORT_HEAP_REJECTIONS
            , PREFETCH_WAIT_TIME
            , PREFETCH_WAITS
            , POOL_DATA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_INDEX_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_XDA_GBP_INDEP_PAGES_FOUND_IN_LBP
            , FCM_TQ_RECV_WAITS_TOTAL
            , FCM_MESSAGE_RECV_WAITS_TOTAL
            , FCM_TQ_SEND_WAITS_TOTAL
            , FCM_MESSAGE_SEND_WAITS_TOTAL
            , FCM_SEND_WAITS_TOTAL
            , FCM_RECV_WAITS_TOTAL
            , IDA_SEND_WAIT_TIME
            , IDA_SENDS_TOTAL
            , IDA_SEND_VOLUME
            , IDA_RECV_WAIT_TIME
            , IDA_RECVS_TOTAL
            , IDA_RECV_VOLUME
            , ROWS_DELETED
            , ROWS_INSERTED
            , ROWS_UPDATED
            , TOTAL_HASH_JOINS
            , TOTAL_HASH_LOOPS
            , HASH_JOIN_OVERFLOWS
            , HASH_JOIN_SMALL_OVERFLOWS
            , POST_SHRTHRESHOLD_HASH_JOINS
            , TOTAL_OLAP_FUNCS
            , OLAP_FUNC_OVERFLOWS
            , INT_ROWS_DELETED
            , INT_ROWS_INSERTED
            , INT_ROWS_UPDATED
            , COMM_EXIT_WAIT_TIME
            , COMM_EXIT_WAITS
            , POOL_COL_L_READS
            , POOL_TEMP_COL_L_READS
            , POOL_COL_P_READS
            , POOL_TEMP_COL_P_READS
            , POOL_COL_LBP_PAGES_FOUND
            , POOL_COL_WRITES
            , POOL_COL_GBP_L_READS
            , POOL_COL_GBP_P_READS
            , POOL_COL_GBP_INVALID_PAGES
            , POOL_COL_GBP_INDEP_PAGES_FOUND_IN_LBP
            , POOL_QUEUED_ASYNC_COL_REQS
            , POOL_QUEUED_ASYNC_TEMP_COL_REQS
            , POOL_QUEUED_ASYNC_COL_PAGES
            , POOL_QUEUED_ASYNC_TEMP_COL_PAGES
            , POOL_FAILED_ASYNC_COL_REQS
            , POOL_FAILED_ASYNC_TEMP_COL_REQS
            , TOTAL_COL_PROC_TIME
            , TOTAL_COL_EXECUTIONS
            , TOTAL_COL_TIME
            , POST_THRESHOLD_HASH_JOINS
            , POOL_CACHING_TIER_PAGE_READ_TIME
            , POOL_CACHING_TIER_PAGE_WRITE_TIME
            , POOL_DATA_CACHING_TIER_L_READS
            , POOL_INDEX_CACHING_TIER_L_READS
            , POOL_XDA_CACHING_TIER_L_READS
            , POOL_COL_CACHING_TIER_L_READS
            , POOL_DATA_CACHING_TIER_PAGE_WRITES
            , POOL_INDEX_CACHING_TIER_PAGE_WRITES
            , POOL_XDA_CACHING_TIER_PAGE_WRITES
            , POOL_COL_CACHING_TIER_PAGE_WRITES
            , POOL_DATA_CACHING_TIER_PAGE_UPDATES
            , POOL_INDEX_CACHING_TIER_PAGE_UPDATES
            , POOL_XDA_CACHING_TIER_PAGE_UPDATES
            , POOL_COL_CACHING_TIER_PAGE_UPDATES
            , POOL_DATA_CACHING_TIER_PAGES_FOUND
            , POOL_INDEX_CACHING_TIER_PAGES_FOUND
            , POOL_XDA_CACHING_TIER_PAGES_FOUND
            , POOL_COL_CACHING_TIER_PAGES_FOUND
            , POOL_DATA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_INDEX_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_XDA_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_COL_CACHING_TIER_GBP_INVALID_PAGES
            , POOL_DATA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_INDEX_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_XDA_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , POOL_COL_CACHING_TIER_GBP_INDEP_PAGES_FOUND
            , TOTAL_HASH_GRPBYS
            , HASH_GRPBY_OVERFLOWS
            , POST_THRESHOLD_HASH_GRPBYS
            , POST_THRESHOLD_OLAP_FUNCS
            , POST_THRESHOLD_COL_VECTOR_CONSUMERS
            , TOTAL_COL_VECTOR_CONSUMERS
            , TOTAL_INDEX_BUILD_PROC_TIME
            , TOTAL_INDEXES_BUILT
            , TOTAL_INDEX_BUILD_TIME
          ) "

    if [[ -n "${lImportDatabase}" ]] ; then lPattern="*${lImportDatabase}${lPattern}" ; fi
    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importTHR_ACTIVI_EV_STMT {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="ABSDBA.ACTIVITYSTMT_THRESHOLD_ACTIVI_EV"
    typeset lPattern="*${lTable}.ixf"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.ACTIVITYSTMT_THRESHOLD_ACTIVI_EV (
             DBNAME
            , HOSTNAME
            , PARTITION_KEY
            , ACTIVATE_TIMESTAMP
            , ACTIVITY_ID
            , ACTIVITY_SECONDARY_ID
            , APPL_ID
            , COMP_ENV_DESC
            , CREATOR
            , EFF_STMT_TEXT
            , EXECUTABLE_ID
            , NUM_ROUTINES
            , PACKAGE_NAME
            , PACKAGE_VERSION_ID
            , PARTITION_NUMBER
            , PLANID
            , ROUTINE_ID
            , SECTION_ENV
            , SECTION_NUMBER
            , SEMANTIC_ENV_ID
            , STMT_FIRST_USE_TIME
            , STMT_INVOCATION_ID
            , STMT_ISOLATION
            , STMT_LAST_USE_TIME
            , STMT_LOCK_TIMEOUT
            , STMT_NEST_LEVEL
            , STMT_PKGCACHE_ID
            , STMT_QUERY_ID
            , STMT_SOURCE_ID
            , STMT_TEXT
            , STMT_TYPE
            , STMTID
            , STMTNO
            , UOW_ID
          ) "

    if [[ -n "${lImportDatabase}" ]] ; then lPattern="*${lImportDatabase}${lPattern}" ; fi
    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

  function importTHR_ACTIVI_EV_VALS {

    typeset lHostName="${1}"
    typeset lInstance="${2}"
    typeset lDatabase="${3}"

    typeset lTimestamp=""
    typeset lTable="ABSDBA.ACTIVITYVALS_THRESHOLD_ACTIVI_EV"
    typeset lPattern="*${lTable}.ixf"
    typeset lReturnedText=""
    typeset lErrorText=""
    typeset lNumberImported=""
    typeset lImportSQL="
          INSERT_UPDATE into ABSDBA.ACTIVITYVALS_THRESHOLD_ACTIVI_EV (
             DBNAME
            , HOSTNAME
            , PARTITION_KEY
            , ACTIVATE_TIMESTAMP
            , ACTIVITY_ID
            , ACTIVITY_SECONDARY_ID
            , APPL_ID
            , PARTITION_NUMBER
            , STMT_VALUE_DATA
            , STMT_VALUE_INDEX
            , STMT_VALUE_ISNULL
            , STMT_VALUE_ISREOPT
            , STMT_VALUE_TYPE
            , UOW_ID
          ) "
   
    if [[ -n "${lImportDatabase}" ]] ; then lPattern="*${lImportDatabase}${lPattern}" ; fi
    if [[ -n "${lImportInstance}" ]] ; then lPattern="*${lImportInstance}${lPattern}" ; fi
    if [[ -n "${lImportHostname}" ]] ; then lPattern="${lImportHostname}${lPattern}" ; fi

    typeset lFileList=$( ls ${cExportDir}/${lPattern} 2>&1 | grep -v 'No such' )
    typeset lNumberOfFiles=$( echo "${lFileList}" | grep -v '^$' | wc -l )
    typeset lCurrentFile=1

    if [ ${lNumberOfFiles} -eq 0 ] ; then
      gMessage="No files found matching the pattern ${lPattern}"
      [[ "${lVerbose}" == "YES" ]] && showInfo
      printf "\n${gMessage}\n\n" >> ${lLogOutput}
      set +x
      return 0
    fi

    for lInputFile in ${lFileList}
    do
      lTimestamp=$( db2 -x "values current timestamp" )
      if [ "${lVerbose}" == "YES" ] ; then
        echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})"
      fi
      echo "${lTimestamp} - ${lTable} - ${lInputFile} (${lCurrentFile}/${lNumberOfFiles})" >> ${lLogOutput}

      lReturnedText=$( db2 -v "IMPORT FROM ${lInputFile} OF IXF "${lImportSQL} )
      lReturnCode=$?
      if [ ${lReturnCode} -eq 0 -a \
           $( echo "${lReturnedText}" | egrep -v "${cImportNoneErrors}" | grep '^SQL3[2-9][0-9]*N' | wc -l ) -gt 0 ] ; then
        lReturnCode=8
      fi
      printf "\n---\n%s\n---\n" "${lReturnedText}" >> ${lLogOutput}
      if [ ${lReturnCode} -gt 2 ] ; then
        lErrorText=$( formatErrorMsg "${lReturnedText}" "${lTable}" "${lInputFile}" )
        sendMail "${lHostName}" "${lInstance}" "${lDatabase}" \
                    "8" "${lErrorText}"
      fi
      if [ "${lVerbose}" == "YES" ] ; then
        lNumberImported=$( echo "${lReturnedText}" | grep 'Number of rows' )
        [[ "${lNumberImported}" != "" ]] && echo "${lNumberImported}" | tr '^' '\t'
        printf "  Return code: ${lReturnCode}\n\n"
      fi
      lCurrentFile=$(( lCurrentFile + 1 ))
    done

    set +x
    return ${lReturnCode}

  }

#
# Primary initialization of commonly used variables
#
typeset    lTimestampToday=$( date "+%Y-%m-%d-%H.%M.%S" )
  ## typeset    lDb2Profile=""
typeset -l lInstance=""
typeset -u lDatabase=""
typeset    lImportHostname=""
typeset    lImportInstance=""
typeset -u lImportDatabase=""
typeset    lUsername=""
typeset    lPassword=""
typeset    lAlias=""
typeset    lJobName=""
typeset    lMailTo=""
typeset    lMailCc=""
typeset -u lVerbose="YES"
typeset    lTimestamp=""
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
      -s | --importhostname )
        lImportHostname="${_lCmdValue}"
        shift 2
        ;;
      -i | --importinstance )
        lImportInstance="${_lCmdValue}"
        shift 2
        ;;
      -d | --importdatabase )
        lImportDatabase="${_lCmdValue}"
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
[[ "${lInstance}" == "" ]] && gErrorNo=1 && gMessage="Please provide an instance to do the work for" && scriptUsage
[[ "${lDatabase}" == "" ]] && gErrorNo=1 && gMessage="Please provide a database to do the work for" && scriptUsage

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
typeset lLogOutput="${lLogOutputDir}/${lTimestampToday}_${cBaseNameScript}.log"
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
[[ "${lMailTo}" == "" && "${lMailCc}" != "" ]] && lMailTo="${lMailCc}"
[[ "${lMailTo}" == "${lMailCc}" ]] && lMailCc=""

#
# Load Db2 library
#
loadDb2Profile "${lInstance}"
lReturnCode=$?
[[ ! -f ${gDb2Profile} ]] && gErrorNo=2 && gMessage="Cannot load ${gDb2Profile}" && scriptUsage

#
# Main - Get to work
#
ulimit -s unlimited  # Facilitate Ingest, values are only meant for this script
gDatabase="${lDatabase}"
handleDb2DbConnect
lReturnCode=$?
[[ ${lReturnCode} -ne 0 ]] && gErrorNo=5 && gMessage="Cannot connect to ${gDatabase}" && scriptUsage

lTimestamp=$( db2 -x "values current timestamp" )
lTimestamp=$( echo "${lTimestamp}" | sed 's/^[ ]*//g; s/[ ]*$//g' )
#
# Even though the export functions will send back a return code,
#   no additional error handling is to be taken up. Each function
#   takes proper care of that
#
importGET_PKG_CACHE_STMT    "${cHostName}" "${lInstance}" "${lDatabase}"
importGET_TABLE_CUMUL       "${cHostName}" "${lInstance}" "${lDatabase}"
importGET_DATABASE_CUMUL    "${cHostName}" "${lInstance}" "${lDatabase}"
importGET_BP_CUMUL          "${cHostName}" "${lInstance}" "${lDatabase}"
importGET_CONNECTION_INFO   "${cHostName}" "${lInstance}" "${lDatabase}" "${lTimestamp}"
importGET_DBCFG             "${cHostName}" "${lInstance}" "${lDatabase}" "${lTimestamp}"
importGET_DBMCFG            "${cHostName}" "${lInstance}" "${lDatabase}" "${lTimestamp}"
importGET_REG_VARIABLES     "${cHostName}" "${lInstance}" "${lDatabase}" "${lTimestamp}"
importGET_DBSIZE_INFO       "${cHostName}" "${lInstance}" "${lDatabase}" "${lTimestamp}"
importTHR_VIOL_EV           "${cHostName}" "${lInstance}" "${lDatabase}"
importTHR_ACTIVI_EV         "${cHostName}" "${lInstance}" "${lDatabase}"
importTHR_ACTIVI_EV_METRICS "${cHostName}" "${lInstance}" "${lDatabase}"
importTHR_ACTIVI_EV_STMT    "${cHostName}" "${lInstance}" "${lDatabase}"
importTHR_ACTIVI_EV_VALS    "${cHostName}" "${lInstance}" "${lDatabase}"

#
# Finish up
#
handleDb2DbDisconnect
set +x
return 0
