#!/bin/bash
# SPDX-License-Identifier: MPL-2.0

# Starts a Circo node. For more info, call with -h

BOOT_SCRIPT=$(cat <<-END
    using Circo
    
    args = Circo.cli.parse_args(ARGS)
    opts = Circo.cli.create_options()
    opts isa Circo.cli.Exit && exit(opts.code)

    if isfile(opts.script)
        include(opts.script)
    else
        @error "Cannot open \$(opts.script)"
    end

    if @isdefined(options)
        opts = merge(opts, options())
    end
    if @isdefined(profile)
        opts = merge(opts, (profilefn = profile,))
    end
    if @isdefined(plugins)
        opts = merge(opts, (userpluginsfn = plugins,))
    end
    ctx = CircoContext(;opts...)

    zygoteresult = []
    if opts[:iszygote] && @isdefined(zygote)
        zygoteresult = zygote(ctx)
        zygoteresult = zygoteresult isa AbstractArray ? zygoteresult : [zygoteresult]
    end

    node = Circo.cli.circonode(ctx; zygote = zygoteresult, opts...)
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