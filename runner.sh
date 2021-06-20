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
	FOLDER=/tmp/$SID
	if [ -f $FOLDER ]; then
		printf -- "- SID in use!\n"
		exit 3
	fi
	mkdir $FOLDER
	tar xfv $FILE --directory=$FOLDER
	if [ $? -ne 0 ]; then
		printf -- "- Image unpacking failed!\n"
		exit 4
	fi
	printf "< Done\n"
}

unpack_layers(){
	printf "> Unpacking layers:\n"
	BASEPATH=/tmp/$SID
	LAYERS=$(cat $BASEPATH/manifest.json | tr '\n' ' ' | tr '\r' ' ' | grep -Eo '"Layers":[ ]*[^\[]*\[[^]]*]' | tr '"' '\n' | grep -Eo "[0-9a-Z]{64}.*$")
	ALAYERS=""
	for LINE in $LAYERS; do
		ALAYERS="$LINE $ALAYERS"
	done
	FOLDER=/tmp/$SID/container
	rm -Rf $FOLDER
	mkdir $FOLDER
	for LINE in $ALAYERS; do
		printf -- "- Unpacking $(dirname $LINE)\n"
		tar xf $BASEPATH/$LINE --directory=$FOLDER --overwrite
		if [ $? -ne 0 ]; then
			printf "- Error unpacking layer\n< Error\n"
			exit 5
		fi
	done
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
start_container
printf -- "* $BASEPATH\n"
