#!/bin/sh
docker run -i --rm -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -g) --entrypoint=/usr/local/bin/bootnode \
  quorumengineering/quorum:2.6.0 "$@"
