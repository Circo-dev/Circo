# SPDX-License-Identifier: LGPL-3.0-only
using Base.Threads
using DataStructures

const MSG_BUFFER_SIZE = 100_000

mutable struct HostActor <: AbstractActor
    core::CoreState
    HostActor() = new()
end
monitorprojection(::Type{HostActor}) = JS("projections.nonimportant")


mutable struct HostService <: Plugin
    in_msg::Deque
    in_lock::SpinLock
    iamzygote
    hostid
    peers::Dict{PostCode, HostService}
    helper::Addr
    postcode::PostCode
    HostService(;options...) = new(
        Deque{Any}(),#get(options, :buffer_size, MSG_BUFFER_SIZE)
        SpinLock(),
        get(options, :iamzygote, false),
        get(options, :hostid, 0),
        Dict()
    )
end

Plugins.symbol(::HostService) = :host
Circo.postcode(hs::HostService) = hs.postcode

function Plugins.setup!(hs::HostService, scheduler)
    hs.postcode = postcode(scheduler)
    hs.helper = spawn(scheduler.service, HostActor())
end

function addpeers!(hs::HostService, peers::Array{HostService}, scheduler)
    for peer in peers
        if postcode(peer) != postcode(hs)
            hs.peers[postcode(peer)] = peer
        end
    end
    cluster = get(scheduler.plugins, :cluster, nothing)
    if !isnothing(cluster) && !hs.iamzygote && length(cluster.roots) == 0
        root = peers[1].postcode
        deliver!(scheduler, Msg(cluster.helper, ForceAddRoot(root))) # TODO avoid using the internal API
    end
end

@inline function CircoCore.remoteroutes(hostservice::HostService, scheduler::AbstractActorScheduler, msg::AbstractMsg)::Bool
    target_postcode =  postcode(target(msg))
    if CircoCore.network_host(target_postcode) !=  CircoCore.network_host(hostservice.postcode)
        return false
    end
    #@debug "remoteroutes in host.jl $msg"
    peer = get(hostservice.peers, target_postcode, nothing)
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

@inline function CircoCore.letin_remote(hs::HostService, scheduler::AbstractActorScheduler)::Bool
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
    for msg in msgs # The lock must be released before delivering (hostroutes now aquires the peer lock)
        deliver!(scheduler, msg)
    end
    return false
end

struct Host
    schedulers::Array{ActorScheduler}
    id::UInt64
end

function Host(threadcount::Int; options...)
    hostid = rand(UInt64)
    schedulers = create_schedulers(threadcount, hostid; options...)
    hostservices = [scheduler.plugins[:host] for scheduler in schedulers]
    addpeers(hostservices, schedulers)
    return Host(schedulers, hostid)
end

function create_schedulers(threadcount, hostid; options...)
    zygote = get(options, :zygote, [])
    profile = get(options, :profile, Profiles.DefaultProfile(;options...))
    userpluginsfn =  get(options, :userpluginsfn, (;options...) -> [])
    schedulers = []
    for i = 1:threadcount
        iamzygote = i == 1
        myzygote = iamzygote ? zygote : []
        scheduler = ActorScheduler(myzygote;
            profile = profile,
            userplugins = [userpluginsfn()..., HostService(;iamzygote = iamzygote, hostid = hostid, options...)])
        push!(schedulers, scheduler)
    end
    return schedulers
end

function addpeers(hostservices::Array{HostService}, schedulers)
    for i in 1:length(hostservices)
        addpeers!(hostservices[i], hostservices, schedulers[i])
    end
end

# From https://discourse.julialang.org/t/lightweight-tasks-julia-vs-elixir-otp/35082/22
function onthread(f::F, id::Int) where {F<:Function}
    t = Task(nothing)
    @assert id in 1:Threads.nthreads() "thread $id not available!"
    Threads.@threads for i in 1:Threads.nthreads()
        if i == id
            t = @async f()
        end
    end
    return t
end

function (ts::Host)(;process_external=true, exit_when_done=false)
    tasks = []
    next_threadid = min(nthreads(), 2)
    for scheduler in ts.schedulers
        sleep(length(tasks) in (4:length(ts.schedulers) - 4)  ? 0.1 : 1.0) # TODO sleeping is a workaround for a bug in cluster.jl
        push!(tasks, onthread(next_threadid) do; scheduler(;process_external=process_external, exit_when_done=exit_when_done); end)
        next_threadid = next_threadid == nthreads() ? 1 : next_threadid + 1
    end
    for task in tasks
        wait(task)
    end
    return nothing
end

function (host::Host)(messages::Union{Array, AbstractMsg};process_external=true, exit_when_done=false)
    if messages isa AbstractMsg
        messages = [messages]
    end
    for message in messages
        deliver!(host.schedulers[1], message)
    end
    host(;process_external=process_external,exit_when_done=exit_when_done)
    return nothing
end

function Circo.shutdown!(host::Host)
    for scheduler in host.schedulers
        CircoCore.shutdown!(scheduler)
    end
end
