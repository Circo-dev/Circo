#!/bin/bash
# SPDX-License-Identifier: MPL-2.0

# Starts a Circo node. For more info, call with -h

BOOT_SCRIPT=$(cat <<-END
    import Circo
    eval(Circo.cli.runnerquote(true))
END
)
CORE_COUNT=1
if command -v nproc &> /dev/null
then
    CORE_COUNT=`nproc`
else
    CORE_COUNT=`sysctl -n hw.ncpu`
fi

ROOTS_FILE=${ROOTS_FILE:-roots.txt}
export JULIA_NUM_THREADS=${JULIA_NUM_THREADS:-$CORE_COUNT}
export JULIA_EXECUTABLE=${JULIA_EXECUTABLE:-julia}

# JULIA_EXCLUSIVE is needed as a workaround to a crash at websocket disconnection
JULIA_EXCLUSIVE=1 $JULIA_EXECUTABLE --project -e "$BOOT_SCRIPT" -- "$@"