#!/bin/sh

if [ $# -ne 1 ]; then
	printf "USAGE:
	$0 <FILE>

FILE: Path to the docker image
"
	exit 1
fi

FILE=$1
SID=$(date +%Y.%m.%d.%H.%M.%S.%N | base64)
LAYERS=""
RLAYERS=""
IMAGE_PATH=/tmp/$SID
CONTAINER_PATH=$IMAGE_PATH/container

###

check_payload(){
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
	ICMD=$(echo "$CONFIG" | grep -Eo '"Cmd":\[[^]]*]' | sed 's/^"Cmd":\[\|\]$//g' | sed 's/^"\|"$//g' | sed 's/","/ /g' )
	printf -- '- CMD: %s\n' "$ICMD"
	IWRK=$(echo "$CONFIG" | grep -Eo '"WorkingDir":"[^"]*"' | grep -Eo ':".*"$' | sed 's/^:"\|"$//g')
	printf -- '- WORKDIR: %s\n' "$IWRK"
	printf "< Done\n"
}

start_container(){
	printf "> Starting container:\n"
	printf "< Done\n"
}

###

check_payload
unpack_file
unpack_layers
getting_info
start_container
printf -- "* $IMAGE_PATH\n"

