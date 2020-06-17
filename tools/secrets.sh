#!/bin/sh
cd $(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/.. && exec python -m tools.secrets "$@"


