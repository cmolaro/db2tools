#!/bin/bash

# populate historic monitor tables
# /shared/db2/scripts/performance/

. $HOME/.bash_profile

# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

umask 022

db2 connect to $1 

db2 -x "INSERT INTO CRIS.MON_BP_UTILIZATION_HIST ( SELECT
   BP_NAME                         
  ,MEMBER                          
  ,DATA_PHYSICAL_READS             
  ,DATA_HIT_RATIO_PERCENT          
  ,INDEX_PHYSICAL_READS            
  ,INDEX_HIT_RATIO_PERCENT         
  ,XDA_PHYSICAL_READS              
  ,XDA_HIT_RATIO_PERCENT           
  ,COL_PHYSICAL_READS              
  ,COL_HIT_RATIO_PERCENT           
  ,TOTAL_PHYSICAL_READS            
  ,AVG_PHYSICAL_READ_TIME          
  ,PREFETCH_RATIO_PERCENT          
  ,ASYNC_NOT_READ_PERCENT          
  ,TOTAL_WRITES                    
  ,AVG_WRITE_TIME                  
  ,SYNC_WRITES_PERCENT             
  ,GBP_DATA_HIT_RATIO_PERCENT      
  ,GBP_INDEX_HIT_RATIO_PERCENT     
  ,GBP_XDA_HIT_RATIO_PERCENT       
  ,GBP_COL_HIT_RATIO_PERCENT       
  ,CACHING_TIER_DATA_HIT_RATIO_PERCENT 
  ,CACHING_TIER_INDEX_HIT_RATIO_PERCENT
  ,CACHING_TIER_XDA_HIT_RATIO_PERCENT
  ,CACHING_TIER_COL_HIT_RATIO_PERCENT
  ,AVG_SYNC_READ_TIME              
  ,AVG_ASYNC_READ_TIME             
  ,AVG_SYNC_WRITE_TIME             
  ,AVG_ASYNC_WRITE_TIME
  ,CURRENT SERVER
  ,CURRENT DATE
  ,CURRENT TIME
  ,CURRENT TIMESTAMP
FROM SYSIBMADM.MON_BP_UTILIZATION )" 

db2 connect reset 
db2 terminate 

