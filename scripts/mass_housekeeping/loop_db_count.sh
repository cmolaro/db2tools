#/bin/bash
# usage => first argument is the target database
umask 022

# establish connection to target database
echo "--> Connecting to DB2";
db2 connect to $1;
echo "";

echo "+---------+-------------------------------------------+----------------------+";
echo "| DB NAME |  TABLE NAME                               |            # OF ROWS |";
echo "+---------+-------------------------------------------+----------------------+";

tb_list=`db2 -x "select distinct rtrim(tabschema) || '.' || rtrim(tabname) from syscat.tables where tabschema in (select distinct tabschema from syscat.tables where tabschema in  ('ABS','BABS')) and type = 'T' " ` ;

cnt=0
while read -r tblist
do
    ((cnt++))


    tb_count=`db2 -x "select count(*) from $tblist with ur"` ;


    tb=`printf '%-40s' "$tblist"`
    tbc=`printf '%20s' "$tb_count"`


    echo "| $1 |  $tb | $tbc |";



done <<< "$tb_list"

dt=$(date '+%d/%m/%Y %H:%M:%S');
dtc=`printf '%-30s' "$dt"`;


echo "+---------+-------------------------------------------+----------------------+";
echo "| $dtc                                             |"; 
echo "+---------+-------------------------------------------+----------------------+";
echo "--> Processed $cnt tables"



# terminate the connection with db2
echo "--> Terminating with DB2";
db2 connect reset;
echo "";

