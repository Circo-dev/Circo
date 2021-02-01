# SPDX-License-Identifier: MPL-2.0
module Migration

export RecipientMoved, MigrationService, migrate_to_nearest, migrate, MigrationAlternatives

using ..Circo, ..Circo.Cluster, Circo.Monitor
using Plugins
using DataStructures, LinearAlgebra
import Base.length

const AUTOMIGRATE_TOLERANCE = 1e-2

struct MigrationRequest
    actor::Actor
end
struct MigrationResponse
    from::Addr
    to::Addr
    success::Bool
end

"""
    RecipientMoved{TBody}

If a message is not delivered because the target actor moved to a known location,
this message will be sent back to the sender.

The original message gets included in the `RecipientMoved` message. Resending to the new location and updating the
address in their storage is the responsibility of the original sender.

```
struct RecipientMoved{TBody}
    oldaddress::Addr
    newaddress::Addr
    originalmessage::TBody
end
```
"""
struct RecipientMoved{TBody}
    oldaddress::Addr
    newaddress::Addr
    originalmessage::TBody
end

struct MovingActor
    actor::Actor
    messages::Queue{AbstractMsg}
    MovingActor(actor::Actor) = new(actor, Queue{AbstractMsg}())
end

mutable struct MigrationAlternatives
    peers::Array{NodeInfo}
end
Base.length(a::MigrationAlternatives) = Base.length(a.peers)

abstract type MigrationService <: Plugin end
mutable struct MigrationServiceImpl <: MigrationService
    movingactors::Dict{ActorId,MovingActor}
    movedactors::Dict{ActorId,Addr}
    alternatives::MigrationAlternatives
    helperactor::Any
    MigrationServiceImpl(;options...) = new(Dict([]),Dict([]), MigrationAlternatives([]))
end

__init__() = Plugins.register(MigrationServiceImpl)

mutable struct MigrationHelper{TCore} <: Actor{TCore}
    service::MigrationServiceImpl
    core::TCore
end

Circo.monitorprojection(::Type{<:MigrationHelper}) = JS("projections.nonimportant")

Plugins.symbol(::MigrationServiceImpl) = :migration

function Circo.schedule_start(migration::MigrationServiceImpl, scheduler)
    migration.helperactor = MigrationHelper(migration, emptycore(scheduler.service))
    spawn(scheduler.service, migration.helperactor)
end

function Circo.onspawn(me::MigrationHelper, service)
    cluster = getname(service, "cluster")
    if isnothing(cluster)
        error("Migration depends on cluster, but the name 'cluster' is not registered. Please install ClusterService before MigrationService.")
    end
    registername(service, "migration", me)
    send(service, me, cluster, Subscribe{PeerListUpdated}(addr(me)))
end

function Circo.onmessage(me::MigrationHelper, message::PeerListUpdated, service)
    me.service.alternatives = MigrationAlternatives(message.peers) # TODO filter if lengthy
end

"""
    migrate(service, actor::Actor, topostcode::PostCode)

"""
@inline function migrate(service::CircoCore.AbstractService, actor::Actor, topostcode::PostCode)
    return migrate!(service.scheduler, actor, topostcode)
end

function migrate!(scheduler, actor::Actor, topostcode::PostCode)
    if topostcode == postcode(scheduler)
        return false
    end
    migration = scheduler.plugins[:migration]
    if isnothing(migration)
        @debug "Migration plugin not loaded, skipping migrate!"
        return false
    end
    migration::MigrationServiceImpl
    unschedule!(scheduler, actor)
    migration.movingactors[box(actor)] = MovingActor(actor)
    send(scheduler.service, migration.helperactor, Addr(topostcode, 0), MigrationRequest(actor))
    return true
end

Circo.specialmsg(::MigrationServiceImpl, scheduler, message) = false
Circo.specialmsg(migration::MigrationServiceImpl, scheduler, message::AbstractMsg{MigrationRequest}) = begin
    @debug "Migration request: $(message)"
    actor = body(message).actor
    actorbox = box(actor)
    fromaddress = addr(actor)
    if haskey(migration.movingactors, actorbox)
        @info "Thread $(Threads.threadid()): $actorbox fast back-and forth moving: got MigrationRequest while waiting for a response. Accept."
    end
    delete!(migration.movedactors, actorbox)
    schedule!(scheduler, actor)
    Circo.onmigrate(actor, scheduler.service)
    send(scheduler.service, actor, Addr(postcode(fromaddress), 0), MigrationResponse(fromaddress, addr(actor), true))
    return true
end

Circo.specialmsg(migration::MigrationServiceImpl, scheduler, message::AbstractMsg{MigrationResponse}) = begin
    @debug("Migration response: at $(postcode(scheduler)): $(message)")
    response = body(message)
    movingactor = pop!(migration.movingactors, box(response.to), nothing)
    if isnothing(movingactor) # TODO check if this is safe
        @info " $(Threads.threadid()) Got MigrationResponse for $(box(response.to)), but it is not moving."
    end
    if response.success
        @debug "$(response.from) migrated to $(response.to) (at $(postcode(scheduler)))"
        migration.movedactors[box(response.from)] = response.to
        if !isnothing(movingactor) 
            for message in movingactor.messages
                CircoCore.deliver!(scheduler, message)
            end
        end
    else
        if !isnothing(movingactor) 
            schedule!(scheduler, movingactor.actor) # TODO callback + tests
        end
    end
    return nothing
end

Circo.localroutes(migration::MigrationServiceImpl, scheduler, message::AbstractMsg)::Bool = begin
    newaddress = get(migration.movedactors, box(target(message)), nothing)
    if isnothing(newaddress)
        movingactor = get(migration.movingactors, box(target(message)), nothing)
        if isnothing(movingactor)
            return false
        else
            enqueue!(movingactor.messages, message)
            #@debug "Enqueing $(typeof(message)) for $(typeof(movingactor.actor))"
            return true
        end
    else
        if body(message) isa RecipientMoved # Got a RecipientMoved, but the original sender also moved. Forward the RecipientMoved
            msg = Msg(
                addr(scheduler),
                newaddress,
                body(message),
                Infoton(nullpos)
            )
            @debug "Forwarding message $message"
            @debug "forwarding as $msg"
            send(scheduler.service, migration.helperactor, newaddress, body(message))
        else # Do not forward normal messages but send back a RecipientMoved
            recipientmoved = RecipientMoved(target(message), newaddress, body(message))
            @debug "Recipient Moved: $recipientmoved"
            #@debug "$(migration.movedactors)"
            send(scheduler.service, migration.helperactor, sender(message), recipientmoved)
        end
        return true
    end
end

@inline check_migration(me::Actor, alternatives::MigrationAlternatives, service) = nothing

@inline CircoCore.actor_activity_sparse256(migration::MigrationServiceImpl, scheduler, actor::Actor) = begin
    check_migration(actor, migration.alternatives, scheduler.service)
end

@inline @fastmath function find_nearest(sourcepos::Pos, alternatives::MigrationAlternatives)::Union{NodeInfo, Nothing}
    peers = alternatives.peers
    if length(peers) < 2
        return nothing
    end
    found = peers[1]
    mindist = norm(pos(found) - sourcepos)
    for peer in peers[2:end]
        dist = norm(pos(peer) - sourcepos)
        if dist < mindist
            mindist = dist
            found = peer
        end
    end
    return found
end

@inline @fastmath function migrate_to_nearest(me::Actor, alternatives::MigrationAlternatives, service, tolerance=AUTOMIGRATE_TOLERANCE)
    nearest = find_nearest(pos(me), alternatives)
    if isnothing(nearest) return nothing end
    if box(nearest.addr) === box(addr(me)) return nothing end
    if norm(pos(me) - pos(nearest)) < (1.0 - tolerance) * norm(pos(me) - pos(service))
        migrate(service, me, postcode(nearest))
    end
    return nothing
end
end # module