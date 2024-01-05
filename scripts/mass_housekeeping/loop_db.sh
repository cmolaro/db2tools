#!/bin/bash

# Parse command-line options

# Option strings
SHORT=hcvti:x:
LONG=help,connect,verbose,test,include:,exclude:

# read the options
OPTS=$(getopt --options $SHORT --long $LONG --name "$0" -- "$@")

if [ $? != 0 ] ; then echo "Failed to parse options...exiting." >&2 ; exit 1 ; fi

eval set -- "$OPTS"

VERBOSE=true
CONNECT=false
TEST=false
EXCLUDE=""
INCLUDE=""

# extract options and their arguments into variables.
while true ; do
	case "$1" in
	-h | --help )
		echo ""
		echo "usage $0 [-h] [-v] [-c] [-t] [-i] [-x] cmd"
		echo "   -h | --help"
		echo "   -v | --verbose  : display more tracing info"
		echo "   -c | --connect  : do the connect before the script"
		echo "                     otherwise call script with -d"
		echo "   -t | --test     : only echo the cmd, do not execute"
		echo "   -i | --include= : grep-pattern for which DB to include"
		echo "   -x | --exclude= : grep-pattern for which DB to exclude"
		echo "   cmd : Command to be executed"
		echo ""
		echo " $0 loops thru all database in the instance and "
		echo " execute the specified cmd against each database"
		echo ""
		echo " You can choose whether:"
		echo "  - $0 connects before and terminate after the command to be executed"
		echo "  or"
		echo "  - $0 will pass the option -d\$dbase to the command to be executed" 
		echo ""
                echo " Example:"
		echo "   do a test loop thru the databases,"
		echo "   excluding db containing DDOP190, DUB or DABS:"
		echo " 		/shared/db2/scripts/loop_db_new.sh +"
		echo " 		 -t -x'DDOP190\|DUB\|DABS' +"
		echo " 		 /shared/db2/scripts/db2_hk_autots.sh"
                echo "   to add extra -option to the command use quotes :"
		echo "   Loop only thru database DDBN* and do an SQL:"
		echo "          /shared/db2/scripts/loop_db_new.sh +"
		echo "            -iDDBN -c \"db2 -x select IBMREQD from sysibm.sysdummy1\" "
		shift
		exit 
		;;
        -v | --verbose )
                VERBOSE=true
                shift
                ;;
	-c | --connect )
		CONNECT=true
		shift
		;;
	-t | --test )
		TEST=true
		shift
		;;
	-i | --include )
		INCLUDE="$2"
		shift 2
		;;
	-x | --exclude )
		EXCLUDE="$2"
		shift 2
		;;
	-- )
		shift
		break
		;;
	*)
		echo "Internal error!"
		exit 1
		;;
	esac
done

COMMAND="$@"
SCRIPT="$1"
shift 1
REST="$@"

# Print the variables
if $VERBOSE; then
	echo "db2_instance=$DB2INSTANCE"
	echo "VERBOSE = $VERBOSE"
	echo "CONNECT = $CONNECT"
	echo "Command = $COMMAND"
	if [ -n "$INCLUDE" ]; then
        	echo "INCLUDE = $INCLUDE"
	fi
	if [ -n "$EXCLUDE" ]; then 
		echo "EXCLUDE = $EXCLUDE"
	fi
fi

tmpfile1="$(mktemp /tmp/testtmpf1.XXXXXX)"
tmpfile2="$(mktemp /tmp/testtmpf2.XXXXXX)"

db2 list database directory  | grep -B6 -i indirect | grep "Database name"  > $tmpfile1
if [[ $? -ge 4 ]]; then
  echo "Failed to list database directory"
  cat $tmpfile1
  exit 8
fi
if [ -n "$INCLUDE" ]; then
        cat $tmpfile1 | grep $INCLUDE > $tmpfile2
else
        cat $tmpfile1 > $tmpfile2
fi
if [ -n "$EXCLUDE" ]; then
	cat $tmpfile2 | grep -v $EXCLUDE > $tmpfile1
else
	cat $tmpfile2 > $tmpfile1
fi
rm $tmpfile2

cnt=0
for dbase in `awk '{print $4}' $tmpfile1` ; do
	((cnt++))
	if $VERBOSE; then 
		echo "====================================="
		echo "   Working with database: $dbase"
		echo "====================================="
        else
		echo "database: $dbase"
	fi
	if $CONNECT; then
		if $TEST; then 
			echo db2 connect to $dbase
			echo $COMMAND
			echo db2 terminate
		else 
	        	if $VERBOSE; then
				db2 connect to $dbase
			else
				db2 connect to $dbase >/dev/null 2>&1
			fi
			if [[ $? -ge 4 ]]; then
				echo "Failed to connect to $dbase"
				#   exit 8
				continue
			fi

			$COMMAND

                	if $VERBOSE; then
 				db2 terminate
			else
				db2 terminate >/dev/null 2>&1;
			fi
			if [[ $? -ge 4 ]]; then
				echo "Failed to disconnect from $dbase"
				exit 8
			fi
		fi
	else
		if $TEST; then
			echo  $SCRIPT -d$dbase $REST
		else 
	                if $VERBOSE; then 
				echo  $SCRIPT -d$dbase $REST
			fi
			$SCRIPT -d$dbase $REST
		fi
	fi
done 

echo "----> processed $cnt databases."
rm $tmpfile1

