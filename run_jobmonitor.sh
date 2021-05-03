#!/bin/bash

##########################
##    PARSE ARGS
##########################
RUNUSER="caesar"
RUNSCRIPT="/opt/caesar-rest/bin/run_jobmonitor.py"
DBHOST="127.0.0.1"
DBNAME="caesardb"
DBPORT=27017
JOB_MONITORING_PERIOD=30
JOB_SCHEDULER="kubernetes"
KUBE_INCLUSTER=1
KUBE_CONFIG=""
KUBE_CAFILE=""
KUBE_KEYFILE=""
KUBE_CERTFILE=""


echo "ARGS: $@"

for item in "$@"
do
	case $item in
		--runuser=*)
    	RUNUSER=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--job-monitoring-period=*)
    	JOB_MONITORING_PERIOD=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--dbhost=*)
    	DBHOST=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--dbport=*)
    	DBPORT=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--dbname=*)
    	DBNAME=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--job-scheduler=*)
    	JOB_SCHEDULER=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--kube-incluster=*)
    	KUBE_INCLUSTER=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;	
		--kube-config=*)
    	KUBE_CONFIG=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--kube-cafile=*)
    	KUBE_CAFILE=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--kube-keyfile=*)
    	KUBE_KEYFILE=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--kube-certfile=*)
    	KUBE_CERTFILE=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;

	*)
    # Unknown option
    echo "ERROR: Unknown option ($item)...exit!"
    exit 1
    ;;
	esac
done




###############################
##    SET KUBE CONFIG
###############################
if [ "$KUBE_INCLUSTER" = "0" ] ; then
	
	echo "INFO: Creating kube config dir in /home/$RUNUSER ..."
	KUBE_CONFIG_TOP_DIR="/home/$RUNUSER/.kube"
	mkdir -p "$KUBE_CONFIG_TOP_DIR"

	uid=`id -u $RUNUSER`

	# - Copy Kube config file (if not empty)
	if [ "$KUBE_CONFIG" != "" ] ; then
		if [ -e "$KUBE_CONFIG" ] ; then
			echo "INFO: Copying kube config file $KUBE_CONFIG to $KUBE_CONFIG_TOP_DIR ..."
			cp $KUBE_CONFIG $KUBE_CONFIG_TOP_DIR/config
			
			echo "INFO: Renaming KUBE_CONFIG to $KUBE_CONFIG_TOP_DIR/config and set uid/gid to $id ..."
			KUBE_CONFIG="$KUBE_CONFIG_TOP_DIR/config"
			chown $uid:$uid $KUBE_CONFIG
		fi
	fi

	# - Copy Kube ca file to local RUNUSER dir
	if [ "$KUBE_CAFILE" != "" ] ; then
		if [ -e "$KUBE_CAFILE" ] ; then
			echo "INFO: Copying kube ca file $KUBE_CAFILE to $KUBE_CONFIG_TOP_DIR ..."
			cp $KUBE_CAFILE $KUBE_CONFIG_TOP_DIR/ca.pem
			
			echo "INFO: Renaming KUBE_CAFILE to $KUBE_CONFIG_TOP_DIR/ca.pem and set uid/gid to $id ..."
			KUBE_CAFILE="$KUBE_CONFIG_TOP_DIR/ca.pem"
			chown $uid:$uid $KUBE_CAFILE
		fi
	fi

	# - Copy Kube key file to local RUNUSER dir
	if [ "$KUBE_KEYFILE" != "" ] ; then
		if [ -e "$KUBE_KEYFILE" ] ; then
			echo "INFO: Copying kube key file $KUBE_KEYFILE to $KUBE_CONFIG_TOP_DIR ..."
			cp $KUBE_KEYFILE $KUBE_CONFIG_TOP_DIR/client.key
			
			echo "INFO: Renaming KUBE_KEYFILE to $KUBE_CONFIG_TOP_DIR/client.key and set uid/gid to $id ..."
			KUBE_KEYFILE="$KUBE_CONFIG_TOP_DIR/client.key"
			chown $uid:$uid $KUBE_KEYFILE
		fi
	fi

	# - Copy Kube cert file to local RUNUSER dir
	if [ "$KUBE_CERTFILE" != "" ] ; then
		if [ -e "$KUBE_CERTFILE" ] ; then
			echo "INFO: Copying kube cert file $KUBE_CERTFILE to $KUBE_CONFIG_TOP_DIR ..."
			cp $KUBE_CERTFILE $KUBE_CONFIG_TOP_DIR/client.pem
			
			echo "INFO: Renaming KUBE_CERTFILE to $KUBE_CONFIG_TOP_DIR/client.cert and set uid/gid to $id ..."
			KUBE_CERTFILE="$KUBE_CONFIG_TOP_DIR/client.pem"
			chown $uid:$uid $KUBE_CERTFILE
		fi
	fi

	# - Change dir permissions
	echo "INFO: Setting 755 permissions to Kube config dir ..."
	chmod -R 755 $KUBE_CONFIG_TOP_DIR

fi

###############################
##    SET CMD ARGS
###############################
JOB_SCHEDULER_OPT=""
if [ "$JOB_SCHEDULER" != "" ] ; then
  JOB_SCHEDULER_OPT="--job_scheduler=$JOB_SCHEDULER"
fi

KUBE_OPTS=""
if [ "$KUBE_INCLUSTER" = "1" ] ; then
  KUBE_OPTS="--kube_incluster "
fi
KUBE_OPTS="$KUBE_OPTS --kube_config=$KUBE_CONFIG --kube_cafile=$KUBE_CAFILE --kube_keyfile=$KUBE_KEYFILE --kube_certfile=$KUBE_CERTFILE"
	

###############################
##    RUN UWSGI
###############################
# - Define run command & args
CMD="runuser -l $RUNUSER -g $RUNUSER -c'""/opt/caesar-rest/bin/run_jobmonitor.py --job_monitoring_period=$JOB_MONITORING_PERIOD --dbhost=$DBHOST --dbname=$DBNAME --dbport=$DBPORT $JOB_SCHEDULER_OPT $KUBE_OPTS""'"

# - Run command
echo "INFO: Running command: $CMD ..."
eval "$CMD"

