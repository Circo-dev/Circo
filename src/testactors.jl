module TestActors

export Puppet, msgcount, msgs

using Circo

mutable struct Puppet <: Actor{Any}
    msgs::IdDict{DataType, Vector{Any}}
    handlers::IdDict{Any, Any}
    service
    core
    Puppet(handlerpairs...) = new(IdDict(), IdDict(handlerpairs...))
end

Circo.onmessage(me::Puppet, ::OnSpawn, service) = begin
    me.service = service # For simpler API. We know what we are doing. Are we?
    callhandler(me, :spawn, service)
end

function callhandler(me, key, args...)
    handler = get(me.handlers, key, nothing)
    if !isnothing(handler)
        handler(me, args...)
    end
end

Circo.onmessage(me::Puppet, msg, service) = begin
    msgvect = get!(me.msgs, typeof(msg)) do
        return []
    end
    push!(msgvect, msg)
    callhandler(me, typeof(msg), msg, service)
end

msgs(me::Puppet, msgtype::DataType) = get(me.msgs, msgtype, [])

function msgcount(me::Puppet, msgtype::DataType)
    return length(msgs(me, msgtype))
end

Circo.send(me::Puppet, target::Addr, msg) = begin
    send(me.service, me, target, msg)
end
Circo.send(me::Puppet, target::Actor, msg) = send(me, addr(target), msg)

end # module
