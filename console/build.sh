#!/bin/sh

set -eu
umask 022

cd "$(dirname "$0")"

token="$(curl -sSf "https://ghcr.io/token?service=ghcr.io&scope=repository:raspi-alpine/builder:pull" | jq -r ".token")"
tag="$(curl -sSf -H "Authorization: Bearer ${token}" "https://ghcr.io/v2/raspi-alpine/builder/tags/list" | jq -r '.tags | last')"

podman run --rm \
    --env "IMG_NAME=console" \
    --env "ADDITIONAL_KERNEL_MODULES=nf_* nft_*" \
    --env-file "$(pwd)/../default.env" \
    --volume "$(pwd)/image.sh:/input/image.sh:z" \
    --volume "$(pwd):/output:z" \
    "ghcr.io/raspi-alpine/builder:${tag}"
