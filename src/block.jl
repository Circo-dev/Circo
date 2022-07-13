module Block

using Plugins, DataStructures
using ..Circo

export block, wake, BlockService

struct BlockedActor
    actor::Actor
    wakeon::Type
    waketest::Function
    wakecb::Function
    process_readonly::Type
    messages::Deque{AbstractMsg}
    BlockedActor(actor::Actor, wakeon::Type, waketest::Function, wakecb::Function, process_readonly::Type) = new(actor, wakeon, waketest, wakecb, process_readonly, Deque{AbstractMsg}())
end

"""
    BlockService <: Plugin

The Block Service allows actors to stop processing messages and wait for a specific signal message.

Messages arriving while the actor is blocked will be queued and delivered later.
The wakeup signal is defined by a type and optionally an `msg -> Bool` predicate function:
if an incoming message is an instance of the given type and the predicate function returns true,
the actor will wake up. It is also possible to specify another message type that
will still be delivered without waking up the actor (called `process_readonly`).

For avoiding performance hit on non-blocked actors, blocked ones are considered as _NOT_ scheduled.
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
    if body(msg) isa blockedactor.wakeon && blockedactor.waketest(msg)
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

function block(wakecb::Function, service, me::Actor, wakeon::Type;
                    waketest = msg -> true,
                    process_readonly = Nothing)
    block(service, me, wakeon; waketest = waketest, process_readonly = process_readonly, wakecb = wakecb)
end

function block(service, me::Actor, wakeon::Type;
                    waketest = msg -> true,
                    process_readonly = Nothing,
                    wakecb = nocb)
    bs = plugin(service, :block)
    isnothing(bs) && error("Block plugin not loaded!")
    bs::BlockService # TODO this breaks extensibility, check if performance gain is worth it (same as in MultiTask)
    sdl = service.scheduler
    block(bs, sdl, me, wakeon; waketest = waketest, process_readonly = process_readonly, wakecb = wakecb)
end

nocb(_...) = false

defaultwaketest(msg) = true

function block(bs::BlockService, sdl, actor::Actor, wakeon::Type;
                    waketest = defaultwaketest,
                    process_readonly = Nothing,
                    wakecb = nocb)
    @debug "Blocking actor $(addr(actor)) on $(wakeon) $(waketest == defaultwaketest ? "" : "with waketest $(waketest)")"
    bs.blockedactors[box(actor)] = BlockedActor(actor, wakeon, waketest, wakecb, process_readonly)
    unschedule!(sdl, actor)
end

# Return the result of wakecb(msg...), or false if the actor is not blocked
function wake(bs::BlockService, sdl, actor::Actor, msg...)
    blockedactor = pop!(bs.blockedactors, box(actor), nothing)
    if isnothing(blockedactor)
        @info "Attempt to wake non-blocked actor $(addr(actor)). msg: $msg"
        return false
    end
    schedule!(sdl, actor)
    @debug "Delivering $(length(blockedactor.messages)) delayed messages to $(addr(actor))"
    for delayed_msg in blockedactor.messages
        CircoCore.deliver!(sdl, delayed_msg)
    end
    return blockedactor.wakecb(msg...)
end

function wake(service, me::Actor)
    bs = plugin(service, :block)
    isnothing(bs) && error("Block plugin not loaded!")
    bs::BlockService
    sdl = service.scheduler
    wake(bs, sdl, me)
end

end # module
