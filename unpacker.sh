#!/bin/bash

IMAGE=alpine:3.15.0
# IMAGE=ubuntu:latest
IMAGE=ppamo/mq-access-pre:v0.1.5
REPO=${IMAGE%:*}
VERSION=${IMAGE#*:}

echo "+ Getting $REPO - $VERSION"

TOKEN="$(curl \
	--silent \
	--header 'GET' \
	"https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/$REPO:pull" \
	| jq -r '.token')"


echo "+ Got token:
$TOKEN
"

LAYERS=$(curl --request 'GET' \
	--header "Authorization: Bearer ${TOKEN}" \
	"https://registry-1.docker.io/v2/library/$REPO/manifests/$VERSION" | jq -r '.fsLayers[].blobSum')


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
	curl --request 'GET' \
		--location \
		--header "Authorization: Bearer ${TOKEN}" \
		--output "$FILENAME" \
		"https://registry-1.docker.io/v2/library/$REPO/blobs/$LAYER"
	echo "+ Gunziping $FILENAME"
	gunzip $FILENAME
done
