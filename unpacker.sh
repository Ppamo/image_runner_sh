#!/bin/bash

IMAGE=alpine:3.15.0
IMAGE=ubuntu:latest
IMAGE=ppamo/mq-access-pre:v0.1.5
REPO=${IMAGE%:*}
DOMAIN=${REPO%/*}
IMAGENAME=${REPO#*/}
TAG=${REPO#*:}
echo "$REPO" | grep "/" > /dev/null
if [ $? -ne 0 ]; then
	REPO=library/$REPO
fi
VERSION=${IMAGE#*:}

TMPFILE=.output.dat
AUTH_SERVER=https://auth.docker.io
AUTH_SERVICE=registry.docker.io
REGISTRY_SERVER=https://registry-1.docker.io

TOKEN=

getToken(){

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


echo "* Authenticating"
getToken
echo "* Getting data:"
getManifest
echo "* Getting layers"
getLayers
exit 0








TOKEN="$(curl \
	--silent \
	--header 'GET' \
	"https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/$REPO:pull" \
	| jq -r '.token')"


echo "+ Got token:
$TOKEN
"

echo "=> 1"
curl --request 'GET' \
	--header "Authorization: Bearer ${TOKEN}" \
	"https://registry-1.docker.io/v2/library/$REPO/manifests/$VERSION"
exit 0

# LAYERS=$(curl --request 'GET' \
	# --header "Authorization: Bearer ${TOKEN}" \
	# "https://registry-1.docker.io/v2/library/$REPO/manifests/$VERSION" | jq -r '.fsLayers[].blobSum')

# "https://registry-1.docker.io/v2/library/$REPO/manifests/$VERSION" | jq -r '.fsLayers[].blobSum')


echo "+ Got layers:
$LAYERS
"

echo "+ Download layers"
for LAYER in $LAYERS
do
	FILENAME=${LAYER/*:/}.gz
	# FILENAME=layer.gz
	rm -f $FILENAME
	echo "+ Downloading $LAYER"
	# curl --request 'GET' \
		# --location \
		# --header "Authorization: Bearer ${TOKEN}" \
		# --output "$FILENAME" \
		# "https://registry-1.docker.io/v2/library/$REPO/blobs/$LAYER"
	# echo "+ Gunziping $FILENAME"
	# gunzip $FILENAME
done
