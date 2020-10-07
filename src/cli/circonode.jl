# SPDX-License-Identifier: LGPL-3.0-only
module cli
using ..Circo

const INITSCRIPT_ENVNAME = "CIRCO_INITSCRIPT"
const DEFAULT_INITSCRIPT = "circo.jl"
const VERSION = v"0.2.0"

struct Exit
    code::Int
end

doc = """Start a Circo cluster node.

Usage:
  circonode.sh [--roots CIRCO_POSTCODE1,... | --rootsfile FILENAME [--add]] [--threads N] [--zygote]

Options:
  -r --roots      Connect to an existing cluster using one of the listed nodes.
  -f --rootsfile  Read the list of roots from a file. Separator: comma or newline.
  -a --add        Add the address of this node to the roots file, create the file if missing.
  -z --zygote     Call zygote() from the init script and schedule the actor/actors returned by it.
  -t --threads    Number of threads (schedulers) to start. Defaults to 1.
  -s --script     Path to script file. Defaults to $DEFAULT_INITSCRIPT
  -h --help       Show this screen.
  --version       Show version.

Root Nodes:
    Root Nodes are used as entry points to the cluster for nodes connecting later. There is no difference
  between normal and root nodes except that the address of root nodes is "published". You can have
  a single root or you can use every node as root.

Init script:
    Put your actor definitions to "$DEFAULT_INITSCRIPT" or the file named in $INITSCRIPT_ENVNAME environment variable.

    If the --zygote option is used then the zygote() function defined in the init script will be called
  and the returned actors will be scheduled on the started node.

Examples:
  circonode.sh --roots tcp://192.168.1.11:24721/345d60e5554274be,tcp://192.168.1.11:24722/9e1e5b208732de32
    Start a node and connect it to the cluster through one of the listed roots

  circonode.sh -f roots.txt -a
    Start a node using the roots read from roots.txt and append its own adress to the file.
  Also create the file (-a) if it does not exists.

  circonode.sh -z
    Start a node and schedule the actor/actors returned by zygote(), as defined in circo.jl.

  circonode.sh -t 6 -s examples/searchtree.jl -z
    Start six schedulers, connect them into a local (in-process) cluster, and run the zygote defined in
  examples/searchtree.jl on the first scheduler.
"""
function usage()
    println(doc)
end

function parse_args(args)
    longs = Set(["roots", "rootsfile", "add", "help", "version", "script", "threads", "zygote"])
    shorts = Dict([("-r", "roots"), ("--root", "roots"), ("-f", "rootsfile"),
     ("-a", "add"), ("-z", "zygote"), ("-h", "help"), ("-s", "script"), ("-t", "threads"),])
    defaults = Dict([("zygote", "zygote")])
    parsed = Dict()
    key = nothing
    for arg in args
        if isnothing(key) || startswith(arg, "-")
            try
                key = startswith(arg, "--") ? arg[3:end] : arg
                key in longs || (key = shorts[arg])
                default = get(defaults, key, nothing)
                key = Symbol(key)
                parsed[key] = default
            catch
                throw("Invalid argument: $arg")
            end
        else
            parsed[key] = arg
            key = nothing
        end
    end
    return parsed
end

iszygote(args) = isinteractive() ? get(args, :zygote, true) : haskey(args, :zygote)

function create_options(;kwargs...)
    try
        args = merge(parse_args(ARGS), kwargs)
        roots = []
        rootsfilename = nothing
        addmetoroots = false
        threads = 1
        zygoteresult = []
        haskey(args, :help) && (println(doc); return Exit(0))
        haskey(args, :version) && (println(VERSION); return Exit(0))
        haskey(args, :roots) && (append!(roots, parseroots(args[:roots])))
        addmetoroots = haskey(args, :add) && args[:add] != "false"
        script = haskey(args, :script) ? args[:script] : DEFAULT_INITSCRIPT
        if haskey(args, :rootsfile)
            rootsfilename = args[:rootsfile]
            isnothing(rootsfilename) && throw("No roots file provided for --rootsfile or -f")
            append!(roots, readroots(rootsfilename;allow_missing=addmetoroots))
        end
        if haskey(args, :threads)
            threads = args[:threads] isa Int ? args[:threads] : parse(Int, args[:threads])
        end
        return (
            addmetoroots=addmetoroots,
            roots = roots,
            rootsfilename = rootsfilename,
            script = script,
            threads = threads,
            iszygote = iszygote(args),
        )
    catch e
        e isa String ? (println(stderr, e);return Exit(-1)) : rethrow()
    end
end

function parseroots(rootstr)
    isnothing(rootstr) && throw("No root given after --roots (aka -r)")
    parts = map(s->strip(String(s)), split(rootstr, ","))
    return parts
end

function readroots(rootsfilename; allow_missing=false)
    if !isfile(rootsfilename)
        allow_missing ? (return []) : (throw("'$rootsfilename' is not a file. Use --add to create it."))
    end
    roots = []
    open(rootsfilename) do f
        for line in eachline(f)
            line = strip(line)
            length(line) > 0 && !startswith(line, "#") || continue
            append!(roots, parseroots(line))
        end
    end
    return roots
end

function appendpostcode(filename, po)
    open(filename, "a") do f
        write(f, "$po\n")
    end
end

function circonode(ctx; options...)
    if !haskey(options, :roots) || isempty(options[:roots])
        return create_first_node(ctx; options...)
    else
        return create_connecting_node(ctx; options...)
    end
end

function create_first_node(ctx; rootsfilename=nothing, threads=1, zygote=[], unused...)
    host = Host(ctx, threads; zygote = zygote)
    scheduler = host.schedulers[1]
    @info "First node started. To add nodes to this cluster, run:"
    if isnothing(rootsfilename)
        @info "bin/circonode.sh --roots $(postcode(scheduler))"
    else
        appendpostcode(rootsfilename, postcode(scheduler))
        @info "bin/circonode.sh --rootsfile $rootsfilename"
    end
    return host
end

function create_connecting_node(ctx;threads=1, zygote=[], rootsfilename=nothing, addmetoroots=false, unused...)
    host = Host(ctx, threads; zygote = zygote)
    scheduler = host.schedulers[1]
    if addmetoroots
        appendpostcode(rootsfilename, postcode(scheduler))
    end
    @info "Node started. Postcode of this node: $(postcode(scheduler)) $(addmetoroots ? " (added to $rootsfilename)" : "")"
    return host
end

export circonode, parse_args

end
