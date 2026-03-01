#!/bin/sh

set -eu
umask 022

cd "$(dirname "$0")"

podman run --rm \
    --env "IMG_NAME=console" \
    --env "ADDITIONAL_KERNEL_MODULES=nf_* nft_*" \
    --env "DEFAULT_ROOT_PASSWORD=secret" \
    --volume "$(pwd)/image.sh:/input/image.sh:z" \
    --volume "$(pwd):/output:z" \
    ghcr.io/raspi-alpine/builder:latest
