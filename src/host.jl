# SPDX-License-Identifier: MPL-2.0
using DataStructures
import Base.getproperty

#const MSG_BUFFER_SIZE = 100_000

struct HostProfile{TInner <: CircoCore.Profiles.AbstractProfile} <: CircoCore.Profiles.AbstractProfile
    innerprofile::TInner
    options
    HostProfile(innerprofile; options...) = new{typeof(innerprofile)}(innerprofile, options)
end

CircoCore.Profiles.core_plugins(p::HostProfile) = [
    HostService(;p.options...),
    CircoCore.Profiles.core_plugins(p.innerprofile)... # Inner plugins do not see host-added options
]

struct HostContext{TInner <: CircoCore.AbstractContext} <: CircoCore.AbstractContext
    innerctx::TInner
    options
    profile
    plugins
end

function HostContext(innerctx; hostoptions...)
    options = merge(innerctx.options, hostoptions)
    profile = HostProfile(innerctx.profile; options = options)
    plugins = CircoCore.instantiate_plugins(profile, innerctx.userpluginsfn)
    types = CircoCore.generate_types(plugins)
    @assert types.corestate_type == innerctx.corestate_type # HostContext currently does not handle staging
    @assert types.msg_type == innerctx.msg_type
    return HostContext(innerctx, options, profile, plugins)
end

Base.getproperty(ctx::HostContext, name::Symbol) = begin
    if name == :options || name == :profile || name == :plugins || name == :innerctx
        return getfield(ctx, name)
    end
    return getproperty(ctx.innerctx, name)
end

mutable struct HostActor{TCore} <: AbstractActor{TCore}
    core::TCore
end
monitorprojection(::Type{ <: HostActor }) = JS("projections.nonimportant")

mutable struct HostService <: Plugin
    in_msg::Deque
    in_lock::Threads.SpinLock
    iamzygote::Bool
    hostid::Int64
    peercache::Dict{PostCode, HostService}
    hostroot::PostCode
    helper::Addr
    postcode::PostCode
    HostService(;options...) = new(
        Deque{Any}(),#get(options, :buffer_size, MSG_BUFFER_SIZE)
        Threads.SpinLock(),
        get(options, :iamzygote, false),
        get(options, :hostid, 0),
        Dict()
    )
end

Plugins.symbol(::HostService) = :host
Circo.postcode(hs::HostService) = hs.postcode

function Circo.schedule_start(hs::HostService, scheduler)
    hs.postcode = postcode(scheduler)
    hs.helper = spawn(scheduler.service, HostActor(emptycore(scheduler.service)))
end

@inline function CircoCore.remoteroutes(hostservice::HostService, scheduler, msg)::Bool
    target_postcode = postcode(target(msg))
    if CircoCore.network_host(target_postcode) !=  CircoCore.network_host(hostservice.postcode)
        return false
    end
    #@debug "remoteroutes in host.jl $msg"
    peer = get(hostservice.peercache, target_postcode, nothing)
    if !isnothing(peer)
        #@debug "Inter-thread delivery of $(hostservice.postcode): $msg"
        lock(peer.in_lock)
        try
            push!(peer.in_msg, msg)
        finally
            unlock(peer.in_lock)
        end
        return true
    end
    return false
end

@inline function CircoCore.letin_remote(hs::HostService, scheduler)::Bool
    isempty(hs.in_msg) && return false
    msgs = []
    lock(hs.in_lock)
    try
        for i = 1:min(length(hs.in_msg), 30)
            push!(msgs, pop!(hs.in_msg))
            #@debug "arrived at $(hs.postcode): $msg"
        end
    finally
        unlock(hs.in_lock)
    end
    for msg in msgs # The lock must be released before delivering (hostroutes aquires the peer lock)
        CircoCore.deliver!(scheduler, msg)
    end
    return false
end

struct Host
    schedulers::Vector{CircoCore.AbstractScheduler}
    id::UInt64
end

function Host(ctx, threadcount::Int; zygote=[])
    hostid = rand(UInt64)
    schedulers = create_schedulers(ctx, threadcount; zygote = zygote)
    return Host(schedulers, hostid)
end

Base.show(io::IO, ::MIME"text/plain", host::Host) = begin
    print(io, "Circo.Host with $(length(host.schedulers)) schedulers")
end

function create_schedulers(ctx, threadcount; zygote)
    schedulers = []
    for i = 1:threadcount
        iamzygote = i == 1
        myzygote = iamzygote ? zygote : []
        sdl_ctx = HostContext(ctx; iamzygote = iamzygote)
        scheduler = CircoCore.Scheduler(sdl_ctx, myzygote)
        push!(schedulers, scheduler)
    end
    return schedulers
end

cluster_initialized(hs::HostService, scheduler, cluster) = begin
    if hs.hostroot != postcode(hs) && length(cluster.roots) == 0
        send(scheduler, cluster.helper, ForceAddRoot(hs.hostroot))
    end
end

function crossadd_peers(schedulers)
    hostroot = postcode(schedulers[1])
    for scheduler in schedulers
        hs = scheduler.plugins[:host]
        hs.hostroot = hostroot
        for peer_scheduler in schedulers
            if postcode(peer_scheduler) != postcode(scheduler)
                hs.peercache[postcode(peer_scheduler)] = peer_scheduler.plugins[:host]
            end
        end
    end
end

CircoCore.send(host::Host, target::Addr, msgbody) = CircoCore.send(host.schedulers[1], target, msgbody)

# From https://discourse.julialang.org/t/lightweight-tasks-julia-vs-elixir-otp/35082/22
function onthread(f, id::Int)
    t = Task(nothing)
    @assert id in 1:Threads.nthreads() "thread $id not available!"
    Threads.@threads for i in 1:Threads.nthreads()
        if i == id
            t = @async f()
        end
    end
    return t
end

function (ts::Host)(;remote=true, exit=false)
    crossadd_peers(ts.schedulers)#TODO only once
    tasks = []
    next_threadid = min(Threads.nthreads(), 2)
    for scheduler in ts.schedulers
        sleep(length(tasks) in (4:length(ts.schedulers) - 4)  ? 0.1 : 1.0) # TODO sleeping is a workaround for a bug in cluster.jl
        t = onthread(next_threadid) do
            try
                scheduler(;remote=remote, exit=exit)
            catch e
                @show e
            end
        end
        push!(tasks, t)
        next_threadid = next_threadid == Threads.nthreads() ? 1 : next_threadid + 1
    end
    for task in tasks
        wait(task)
    end
    return nothing
end

function Circo.shutdown!(host::Host)
    for scheduler in host.schedulers
        CircoCore.shutdown!(scheduler)
    end
end
