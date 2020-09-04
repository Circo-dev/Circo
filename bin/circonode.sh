#!/bin/bash
# SPDX-License-Identifier: LGPL-3.0-only

# Starts a Circo node. For more info, call with -h

BOOT_SCRIPT=$(cat <<-END
    using Circo
    using Circo.cli
    
    # TODO Move this functionality to CircoCore.cli (needs some code-loading gimmick)
    args = parse_args(ARGS)
    initscript = get(ENV, "CIRCO_INITSCRIPT", "circo.jl") 
    if !haskey(args, :help) && !haskey(args, :version)
        if isfile(initscript)
            include(initscript)
        else
            @error "Cannot open \$(initscript)"
        end
    end
    circonode(@isdefined(zygote) ? zygote : nothing; userpluginsfn = @isdefined(plugins) ? plugins : nothing, profile = @isdefined(profile) ? profile() : nothing)
END
)
ROOTS_FILE=${ROOTS_FILE:-roots.txt}
export JULIA_NUM_THREADS=${JULIA_NUM_THREADS:-10000}
export JULIA_EXECUTABLE=${JULIA_EXECUTABLE:-julia}

# JULIA_EXCLUSIVE is needed as a workaround to a crash at websocket disconnection
JULIA_EXCLUSIVE=1 $JULIA_EXECUTABLE --project -e "$BOOT_SCRIPT" -- "$@"