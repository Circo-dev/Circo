#!/bin/bash
# SPDX-License-Identifier: LGPL-3.0-only

# Starts a Circo node. For more info, call with -h

BOOT_SCRIPT=$(cat <<-END
    using Circo
    
    args = Circo.cli.parse_args(ARGS)
    options = Circo.cli.create_options()
    options isa Circo.cli.Exit && exit(options.code)

    if isfile(options.script)
        include(options.script)
    else
        @error "Cannot open \$(options.script)"
    end

    if @isdefined(profile)
        options = merge(options, (profilefn = profile,))
    end
    if @isdefined(plugins)
        options = merge(options, (userpluginsfn = plugins,))
    end
    ctx = CircoContext(;options...)

    zygoteresult = []
    if options[:iszygote] && @isdefined(zygote)
        zygoteresult = zygote(ctx)
        zygoteresult = zygoteresult isa AbstractArray ? zygoteresult : [zygoteresult]
    end

    node = Circo.cli.circonode(ctx; zygote = zygoteresult, options...)
    nodetask = @async node()
    try
        while true
            sleep(1)
        end
    catch e
        @info "Shutting down Circo node..."
        shutdown!(node)
        wait(nodetask)
    end
END
)
ROOTS_FILE=${ROOTS_FILE:-roots.txt}
export JULIA_NUM_THREADS=${JULIA_NUM_THREADS:-10000}
export JULIA_EXECUTABLE=${JULIA_EXECUTABLE:-julia}

# JULIA_EXCLUSIVE is needed as a workaround to a crash at websocket disconnection
JULIA_EXCLUSIVE=1 $JULIA_EXECUTABLE --project -e "$BOOT_SCRIPT" -- "$@"