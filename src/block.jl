module Blocking

using Plugins, DataStructures
using ..Circo

export block, wake, BlockService

struct BlockedActor
    actor::Actor
    wakeon::Type
    wakecb::Function
    process_readonly::Type
    messages::Deque{AbstractMsg}
    BlockedActor(actor::Actor, wakeon::Type, wakecb::Function, process_readonly::Type) = new(actor, wakeon, wakecb, process_readonly, Deque{AbstractMsg}())
end

"""
    BlockService <: Plugin

The Block Service allows actors to stop processing messages and wait for a specific signal message.

Messages arriving while the actor is blocked will be queued and delived later.
The wakeup signal is defined by a type: if an incoming message is an instance of it,
the actor will wake up. It is also possible to specify another message type that
will still be delivered without waking up the actor (called `process_readonly`).

In this implementation the actor is considered as _NOT_ scheduled while blocked.
"""
mutable struct BlockService <: Plugin
    blockedactors::CircoCore.ActorStore{BlockedActor}
    BlockService(;options...) = new(CircoCore.ActorStore{BlockedActor}())
end
Plugins.symbol(::BlockService) = :block

__init__() = Plugins.register(BlockService)

Circo.localroutes(bs::BlockService, sdl, msg::AbstractMsg)::Bool = begin
    blockedactor = get(bs.blockedactors, box(target(msg)), nothing)
    isnothing(blockedactor) && return false
    if body(msg) isa blockedactor.wakeon
        wakeresult = wake(bs, sdl, blockedactor.actor, body(msg))
        return wakeresult == true ||
            sdl.hooks.localdelivery(sdl, msg, blockedactor.actor)
    end
    if body(msg) isa blockedactor.process_readonly
        return sdl.hooks.localdelivery(sdl, msg, blockedactor.actor)
    end
    push!(blockedactor.messages, msg)
    return true
end

nocb(_...) = false

function block(bs::BlockService, sdl, actor::Actor, wakeon::Type; process_readonly = Nothing, wakecb = nocb)
    bs.blockedactors[box(actor)] = BlockedActor(actor, wakeon, wakecb, process_readonly)
    unschedule!(sdl, actor)
end

"""
Returns the result of wakecb(msg...), or false if the actor is not blocked
"""
function wake(bs::BlockService, sdl, actor::Actor, msg...)
    blockedactor = pop!(bs.blockedactors, box(actor), nothing)
    if isnothing(blockedactor)
        @info "Attempt to wake non-blocked actor $(addr(actor)). msg: $msg"
        return false
    end
    schedule!(sdl, actor)
    wakeresult = blockedactor.wakecb(msg...)
    for delayed_msg in blockedactor.messages
        CircoCore.deliver!(sdl, delayed_msg)
    end
    return wakeresult
end

function block(service, me::Actor, wakeon::Type; process_readonly = Nothing, wakecb = nocb)
    bs = plugin(service, :block)
    isnothing(bs) && error("Block plugin not loaded!")
    bs::BlockService
    sdl = service.scheduler
    block(bs, sdl, me, wakeon; process_readonly = process_readonly, wakecb = wakecb)
end

function block(wakecb::Function, service, me::Actor, wakeon::Type; process_readonly = Nothing)
    block(service, me, wakeon; process_readonly = process_readonly, wakecb = wakecb)
end

function wake(service, me::Actor)
    bs = plugin(service, :block)
    isnothing(bs) && error("Block plugin not loaded!")
    bs::BlockService
    sdl = service.scheduler
    wake(bs, sdl, me)
end

end # module