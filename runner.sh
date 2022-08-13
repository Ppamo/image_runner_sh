#!/bin/sh

if [ $# -lt 1 ]; then
	printf "USAGE:
	$0 <FILE>

FILE: Path to the docker image
"
	exit 1
fi

FILE=
SID=$(date +%Y.%m.%d.%H.%M.%S.%N | base64)
LAYERS=""
RLAYERS=""
IMAGE_PATH=/tmp/$SID
CONTAINER_PATH=$IMAGE_PATH/container
COMMAND=$(echo "$@" | sed "s/^$1//g" | sed 's/ *$//g')
TMPFILE=.output.dat
AUTH_SERVER=https://auth.docker.io
AUTH_SERVICE=registry.docker.io
REGISTRY_SERVER=https://registry-1.docker.io

TOKEN=

###

signal_handler(){
	printf "\n> Killing child processes:\n"
	pkill --signal 3 --parent $$
}

set_sigint(){
	printf "> Setting SIGINT signal handler ($$):\n"
	trap signal_handler INT
	printf "< Done\n"
}

get_token(){
	printf "> Getting auth token:\n"
	rm -f $TMPFILE
	curl -fsSL "$AUTH_SERVER/token?service=$AUTH_SERVICE&scope=repository:$REPO:pull" -o $TMPFILE
	TOKEN=$(grep -Eo '"token"[^:]*:[^"]*"[^"]*"' $TMPFILE | awk -F\" '{ print $4 }')
	if [ ${#TOKEN} -gt 16 ]; then
		printf -- "< Got token!\n$TOKEN\n"
	else
		printf "!ERROR: could not get the token\n"
		exit 1
	fi
}

getManifest(){
	printf "> Getting manifest for $REPO:$VERSION:\n"
	curl --request 'GET' \
		--header "Authorization: Bearer ${TOKEN}" \
		"$REGISTRY_SERVER/v2/$REPO/manifests/$VERSION" -o $TMPFILE
	cat $TMPFILE
	echo
	echo
}

getLayers(){
	printf "> Getting layers for $REPO:$VERSION:\n"
	LAYERS=$(cat $TMPFILE | tr '\n' ' ' | tr '\r' ' ' | grep -Eo '"fsLayers":[^\[]*\[[^]]*]' | tr '"' '\n' | grep -Eo 'sha256:[0-9a-Z]+')
	for i in $LAYERS
	do
		URL="$REGISTRY_SERVER/v2/$DOMAIN/$IMAGENAME/blobs/$i"
		printf "> Downloading $URL:\n"
		curl -s -w "%{http_code}\n" --request 'GET' -L \
			--header "Authorization: Bearer ${TOKEN}" \
			"$URL" -o $i
	done
}

check_file(){
	printf "> Checking file '$FILE':\n"
	if [ ! -f $FILE ]; then
		printf -- "- File not found!\n"
		exit 2
	fi
	file $FILE | grep -E 'POSIX tar archive$' > /dev/null
	if [ $? -ne 0 ]; then
		printf -- "- The file does not looks like a tar file!\n"
		exit 3
	fi
	printf -- "- File OK\n"
	printf "< Done\n"
}

unpack_file(){
	printf "> Unpaking image $FILE:\n"
	if [ -f $IMAGE_PATH ]; then
		printf -- "- SID in use!\n"
		exit 3
	fi
	mkdir $IMAGE_PATH
	tar xfv $FILE --directory=$IMAGE_PATH
	if [ $? -ne 0 ]; then
		printf -- "- Image unpacking failed!\n"
		exit 4
	fi
	printf "< Done\n"
}

unpack_layers(){
	printf "> Unpacking layers:\n"
	LAYERS=$(cat $IMAGE_PATH/manifest.json | tr '\n' ' ' | tr '\r' ' ' | grep -Eo '"Layers":[ ]*[^\[]*\[[^]]*]' | tr '"' '\n' | grep -Eo "[0-9a-Z]{64}.*$")
	rm -Rf $CONTAINER_PATH
	mkdir $CONTAINER_PATH
	for LINE in $LAYERS; do
		printf -- "- Unpacking $(dirname $LINE)\n"
		tar xf $IMAGE_PATH/$LINE --directory=$CONTAINER_PATH --overwrite
		if [ $? -ne 0 ]; then
			printf "- Error unpacking layer\n< Error\n"
			exit 5
		fi
	done
	printf "< Done\n"
}

getting_info(){
	printf "> Getting container info:\n"
	printf -- "- Getting startup info from json files:\n"
	for LINE in $LAYERS; do
		RLAYERS="$LINE $RLAYERS"
	done
	FILE=$(echo "$IMAGE_PATH/$(dirname $LINE)/json")
	printf -- "- Reading $FILE\n"
	CONFIG=$(grep -zPo '"config":(\{([^{}]++|(?1))*\})' $FILE)
	IENV=$(echo $CONFIG | grep -Eo '"Env":\[[^]]*]' | sed 's/^"Env":\[\|]$//g' | tr ',' '\n' | sed 's/^"\|"$//g' )
	printf -- '- ENV:\n%s\n' "$IENV"
	ICMD=$(echo "$CONFIG" | grep -Eo '"Cmd":\[[^]]*]' | sed 's/^"Cmd":\[\|\]$//g' | sed 's/","/" "/g' )
	printf -- '- CMD: %s\n' "$ICMD"
	IWRK=$(echo "$CONFIG" | grep -Eo '"WorkingDir":"[^"]*"' | grep -Eo ':".*"$' | sed 's/^:"\|"$//g')
	printf -- '- WORKDIR: %s\n' "$IWRK"
	printf "< Done\n"
}

start_container(){
	printf "> Preparing container start:\n"
	SS_PATH=$CONTAINER_PATH/.starter.sh
	printf -- "- Changing filesystem path to $CONTAINER_PATH:\n"
	for LINE in $IENV; do
		printf "export %s\n" "$LINE"
	done >> $SS_PATH
	if [ -n "$IWRK" ]; then
		echo "cd $IWRK" >> $SS_PATH
	fi
	if [ -n "$COMMAND" ]; then
		echo "$COMMAND" >> $SS_PATH
	else
		if [ -n "$ICMD" ]; then
			echo "$ICMD" >> $SS_PATH
		else
			echo "/bin/sh" >> $SS_PATH
		fi
	fi

	printf -- "- Startup script:\n"
	cat $SS_PATH
	printf "< Done\n"
	printf "> Starting container $SID:\n"
	set_sigint
	chroot $CONTAINER_PATH sh < $SS_PATH
	printf "< Done\n"
}

clean_up(){
	printf "> Cleaning up:\n"
	rm -Rf $IMAGE_PATH
	printf "< Done\n"
}

check_args(){
	if [ -f $1 ]; then
		FILE=$1
		check_file
	else
		echo "$1" | grep ':' > /dev/null
		if [ $? -ne 0]; then
			IMAGE=$1:latest
		fi
		REPO=${IMAGE%:*}
		DOMAIN=${REPO%/*}
		IMAGENAME=${REPO#*/}
		TAG=${REPO#*:}
		echo "$REPO" | grep "/" > /dev/null
		if [ $? -ne 0 ]; then
			REPO=library/$REPO
		fi
		VERSION=${IMAGE#*:}
		get_token
	fi
}

###

check_args

unpack_file
unpack_layers
getting_info
start_container
clean_up

