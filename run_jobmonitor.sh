#!/bin/bash

##########################
##    PARSE ARGS
##########################
RUNUSER="caesar"
CHANGE_USER=true
RUNSCRIPT="/opt/caesar-rest/bin/run_jobmonitor.py"
DBHOST="127.0.0.1"
DBNAME="caesardb"
DBPORT=27017
JOB_MONITORING_PERIOD=30
JOB_SCHEDULER="kubernetes"

MOUNT_RCLONE_VOLUME=0
MOUNT_VOLUME_PATH="/mnt/storage"
RCLONE_REMOTE_STORAGE="neanias-nextcloud"
RCLONE_REMOTE_STORAGE_PATH="."
RCLONE_MOUNT_WAIT_TIME=10

KUBE_INCLUSTER=1
KUBE_CONFIG=""
KUBE_CAFILE=""
KUBE_KEYFILE=""
KUBE_CERTFILE=""

SLURM_KEYFILE=""
SLURM_USER=""
SLURM_HOST=""
SLURM_PORT=""


echo "ARGS: $@"

for item in "$@"
do
	case $item in
		--runuser=*)
    	RUNUSER=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
    --change-runuser=*)
    	CHANGE_USER_FLAG=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
			if [ "$CHANGE_USER_FLAG" = "1" ] ; then
				CHANGE_USER=true
			else
				CHANGE_USER=false
			fi
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
		
		--mount-rclone-volume=*)
    	MOUNT_RCLONE_VOLUME=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--mount-volume-path=*)
    	MOUNT_VOLUME_PATH=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--rclone-remote-storage=*)
    	RCLONE_REMOTE_STORAGE=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--rclone-remote-storage-path=*)
    	RCLONE_REMOTE_STORAGE_PATH=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--rclone-mount-wait=*)
    	RCLONE_MOUNT_WAIT_TIME=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
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

    --slurm-keyfile=*)
    	SLURM_KEYFILE=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--slurm-user=*)
    	SLURM_USER=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--slurm-host=*)
    	SLURM_HOST=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--slurm-port=*)
    	SLURM_PORT=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		

	*)
    # Unknown option
    echo "ERROR: Unknown option ($item)...exit!"
    exit 1
    ;;
	esac
done


###############################
##    MOUNT VOLUMES
###############################
if [ "$MOUNT_RCLONE_VOLUME" = "1" ] ; then

	# - Create mount directory if not existing
	echo "INFO: Creating mount directory $MOUNT_VOLUME_PATH ..."
	mkdir -p $MOUNT_VOLUME_PATH	

	# - Get device ID of standard dir, for example $HOME
	#   To be compared with mount point to check if mount is ready
	DEVICE_ID=`stat "$HOME" -c %d`
	echo "INFO: Standard device id @ $HOME: $DEVICE_ID"

	# - Mount rclone volume in background
	uid=`id -u $RUNUSER`

	echo "INFO: Mounting rclone volume at path $MOUNT_VOLUME_PATH for uid/gid=$uid ..."
	MOUNT_CMD="/usr/bin/rclone mount --daemon --uid=$uid --gid=$uid --umask 000 --allow-other --file-perms 0777 --dir-cache-time 0m5s --vfs-cache-mode full $RCLONE_REMOTE_STORAGE:$RCLONE_REMOTE_STORAGE_PATH $MOUNT_VOLUME_PATH -vvv"
	eval $MOUNT_CMD

	# - Wait until filesystem is ready
	echo "INFO: Sleeping $RCLONE_MOUNT_WAIT_TIME seconds and then check if mount is ready..."
	sleep $RCLONE_MOUNT_WAIT_TIME
	
	# - Get device ID of mount point
	MOUNT_DEVICE_ID=`stat "$MOUNT_VOLUME_PATH" -c %d`
	echo "INFO: MOUNT_DEVICE_ID=$MOUNT_DEVICE_ID"
	if [ "$MOUNT_DEVICE_ID" = "$DEVICE_ID" ] ; then
 		echo "ERROR: Failed to mount rclone storage at $MOUNT_VOLUME_PATH within $RCLONE_MOUNT_WAIT_TIME seconds, exit!"
		exit 1
	fi

	# - Print mount dir content
	echo "INFO: Mounted rclone storage at $MOUNT_VOLUME_PATH with success (MOUNT_DEVICE_ID: $MOUNT_DEVICE_ID)..."
	ls -ltr $MOUNT_VOLUME_PATH

	# - Create job & data directories
	echo "INFO: Creating job & data directories ..."
	mkdir -p 	$MOUNT_VOLUME_PATH/jobs
	mkdir -p 	$MOUNT_VOLUME_PATH/data

fi

###############################
##    SET KUBE CONFIG
###############################
if [ "$JOB_SCHEDULER" = "kubernetes" ] && [ "$KUBE_INCLUSTER" = "0" ] ; then

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

SLURM_OPTS="--slurm_keyfile=$SLURM_KEYFILE --slurm_user=$SLURM_USER --slurm_host=$SLURM_HOST --slurm_port=$SLURM_PORT "

###############################
##    RUN JOB MONITOR
###############################
# - Define run command & args

if [ "$CHANGE_USER" = true ]; then
	CMD="runuser -l $RUNUSER -g $RUNUSER -c'""/opt/caesar-rest/bin/run_jobmonitor.py --job_monitoring_period=$JOB_MONITORING_PERIOD --dbhost=$DBHOST --dbname=$DBNAME --dbport=$DBPORT $JOB_SCHEDULER_OPT $KUBE_OPTS $SLURM_OPTS ""'"
else
	CMD="python /opt/caesar-rest/bin/run_jobmonitor.py --job_monitoring_period=$JOB_MONITORING_PERIOD --dbhost=$DBHOST --dbname=$DBNAME --dbport=$DBPORT $JOB_SCHEDULER_OPT $KUBE_OPTS $SLURM_OPTS"
fi


# - Run command
echo "INFO: Running command: $CMD ..."
eval "$CMD"

