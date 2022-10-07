module TestActors

export Puppet, EventPuppet, msgcount, msgs

using Circo

mutable struct Puppet <: Actor{Any}
    msgs::IdDict{DataType, Vector{Any}}
    handlers::IdDict{Any, Any}
    registeredname::Union{String, Nothing}

    service
    core
    Puppet(handlerpairs...; registeredname = nothing) = new(IdDict(), IdDict(handlerpairs...), registeredname)
end

mutable struct EventPuppet <: Actor{Any}
    msgs::IdDict{DataType, Vector{Any}}
    handlers::IdDict{Any, Any}
    registeredname::Union{String, Nothing}

    service
    eventdispatcher
    core

    EventPuppet(handlerpairs...; registeredname = nothing) = new(IdDict(), IdDict(handlerpairs...), registeredname)
end
Circo.traits(::Type{EventPuppet}) = (EventSource,)

Circo.onmessage(me::Union{Puppet, EventPuppet}, ::OnSpawn, service) = begin
    me.service = service # For simpler API. We know what we are doing. Are we?
    if !isnothing(me.registeredname)
        registername(me.service, me.registeredname, me)
    end
    callhandler(me, :spawn, service)
end

function callhandler(me, key, args...)
    handler = get(me.handlers, key, nothing)
    if !isnothing(handler)
        handler(me, args...)
    end
end

Circo.onmessage(me::Union{Puppet, EventPuppet}, msg, service) = begin
    msgvect = get!(me.msgs, typeof(msg)) do
        return []
    end
    push!(msgvect, msg)
    callhandler(me, typeof(msg), msg, service)
end

msgs(me::Union{Puppet, EventPuppet}, msgtype::DataType) = get(me.msgs, msgtype, [])

function msgcount(me::Union{Puppet, EventPuppet}, msgtype::DataType)
    return length(msgs(me, msgtype))
end

Circo.send(me::Union{Puppet, EventPuppet}, target::Addr, msg) = send(me.service, me, target, msg)
Circo.send(me::Union{Puppet, EventPuppet}, target::Actor, msg) = send(me, addr(target), msg)

end # module
