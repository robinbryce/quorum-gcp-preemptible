#!/bin/sh
docker run -i --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) -w $(pwd) quorumengineering/quorum:2.6.0 "$@"
