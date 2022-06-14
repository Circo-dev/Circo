# SPDX-License-Identifier: MPL-2.0
module Presistence

using CircoCore, ..Circo
using Circo.Marshal
using Plugins

abstract type PersistenceService <: Plugin end
mutable struct TransactionPersistence <: PersistenceService
    replay::Bool
    logdir::String
    logfile::IOStream
    TransactionPersistence(; logdir="./trlogs/", replay=true, opts...) = new(replay, logdir)
end
Plugins.symbol(::TransactionPersistence) = :persistence
__init__() = Plugins.register(TransactionPersistence)

function Circo.schedule_start(me::TransactionPersistence, sdl)
    me.logfile = open(joinpath(me.logdir, "writelog"); write=true, truncate=false)
end

function Circo.schedule_stop(me::TransactionPersistence, sdl)
    try 
        close(me.logfile)
    catch e
        @warn "Unable to close persistence log file" exception=(e, catch_backtrace())
    end
end

struct Spawn
    ts::Float64
    actor
end

Circo.actor_spawning(me::TransactionPersistence, sdl, actor) = begin
    write(me.logfile, marshal(Spawn(time(), actor)))
end

struct Death
    ts::Float64
    actorid::ActorId
end

Circo.actor_dying(me::TransactionPersistence, sdl, actor) = begin
    write(me.logfile, marshal(Death(time(), actor.id)))
end

struct StateChange
    ts::Float64
    actorid::ActorId
    write
end

Circo.actor_state_write(me::TransactionPersistence, sdl, target, write) = begin
    write(me.logfile, marshal(StateChange(time(), box(target), write)))
end

end # module
