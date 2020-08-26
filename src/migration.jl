# SPDX-License-Identifier: LGPL-3.0-only
using DataStructures, LinearAlgebra
import Base.length

const DEFAULT_TOLERANCE = 1e-2

struct MigrationRequest
    actor::AbstractActor
end
struct MigrationResponse
    from::Addr
    to::Addr
    success::Bool
end

"""
    RecipientMoved{TBody}

If a message is undeliverable because the tartget actor moved to a known lcoation,
this message will be sent back to the sender. The original message will not be delivered,
but it gets included in the `RecipientMoved` message.

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
    actor::AbstractActor
    messages::Queue{AbstractMsg}
    MovingActor(actor::AbstractActor) = new(actor, Queue{AbstractMsg}())
end

mutable struct MigrationAlternatives
    peers::Array{NodeInfo}
end
Base.length(a::MigrationAlternatives) = Base.length(a.peers)

mutable struct MigrationService <: Plugin
    movingactors::Dict{ActorId,MovingActor}
    movedactors::Dict{ActorId,Addr}
    alternatives::MigrationAlternatives
    helperactor::Addr
    MigrationService(;options = NamedTuple()) = new(Dict([]),Dict([]), MigrationAlternatives([]))
end

mutable struct MigrationHelper <: AbstractActor
    service::MigrationService
    core::CoreState
    MigrationHelper(migration) = new(migration)
end

Circo.monitorprojection(::Type{MigrationHelper}) = JS("projections.nonimportant")

Plugins.symbol(::MigrationService) = :migration

function Plugins.setup!(migration::MigrationService, scheduler)
    helper = MigrationHelper(migration)
    migration.helperactor = spawn(scheduler.service, helper)
end

function Circo.onschedule(me::MigrationHelper, service)
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
    migrate(service, actor::AbstractActor, topostcode::PostCode)


"""
@inline function migrate(service::ActorService, actor::AbstractActor, topostcode::PostCode)
    return migrate!(service.scheduler, actor, topostcode)
end

function migrate!(scheduler::AbstractActorScheduler, actor::AbstractActor, topostcode::PostCode)
    if topostcode == postcode(scheduler)
        return false
    end
    migration = scheduler.plugins[:migration]
    if isnothing(migration)
        @debug "Migration plugins not loaded, skipping migrate!"
        return false
    end
    send(postoffice(scheduler), Msg(addr(scheduler),
        Addr(topostcode, 0),
        MigrationRequest(actor),
        Infoton(nullpos)))
    unschedule!(scheduler, actor)
    migration.movingactors[id(actor)] = MovingActor(actor)
    return true
end

function Circo.handle_special!(scheduler::AbstractActorScheduler, message::Msg{MigrationRequest})
    @debug "Migration request: $(message)"
    migration = scheduler.plugins[:migration]
    if isnothing(migration)
        @info "Migration Plugin not installed, dropping $message"
        return nothing
    end
    actor = body(message).actor
    actorbox = box(addr(actor))
    fromaddress = addr(actor)
    if haskey(migration.movingactors, actorbox)
        @error "TODO Handle fast back-and forth moving when the request comes earlier than the previous response"
    end
    delete!(migration.movedactors, actorbox)
    schedule!(scheduler, actor)
    onmigrate(actor, scheduler.service)
    send(scheduler.postoffice,
        Msg(actor,
        Addr(postcode(fromaddress), 0),
        MigrationResponse(fromaddress, addr(actor), true)))
    return nothing
end

function Circo.handle_special!(scheduler::AbstractActorScheduler, message::Msg{MigrationResponse})
    @debug("Migration response: at $(postcode(scheduler)): $(message)")
    migration = scheduler.plugins[:migration]
    response = body(message)
    movingactor = pop!(migration.movingactors, box(response.to))
    if response.success
        @debug "$(response.from) migrated to $(response.to) (at $(postcode(scheduler)))"
        migration.movedactors[box(response.from)] = response.to
        for message in movingactor.messages
            deliver!(scheduler, message)
        end
    else
        schedule!(scheduler, movingactor.actor) # TODO callback + tests
    end
end

function Circo.localroutes(migration::MigrationService, scheduler::AbstractActorScheduler, message::AbstractMsg)::Bool
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
            send(scheduler.postoffice, msg)
        else # Do not forward normal messages but send back a RecipientMoved
            recipientmoved = RecipientMoved(target(message), newaddress, body(message))
            @debug "Recipient Moved: $recipientmoved"
            #@debug "$(migration.movedactors)"
            send(scheduler.postoffice, Msg(
                addr(scheduler),
                sender(message),
                recipientmoved,
                Infoton(nullpos)
            ))
        end
        return true
    end
end

@inline check_migration(me::AbstractActor, alternatives::MigrationAlternatives, service) = nothing

@inline function CircoCore.actor_activity_sparse(migration::MigrationService, scheduler, actor::AbstractActor)
    check_migration(actor, migration.alternatives, scheduler.service)
end

@inline function find_nearest(sourcepos::Pos, alternatives::MigrationAlternatives)::Union{NodeInfo, Nothing}
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

@inline function migrate_to_nearest(me::AbstractActor, alternatives::MigrationAlternatives, service, tolerance=DEFAULT_TOLERANCE)
    nearest = find_nearest(pos(me), alternatives)
    if isnothing(nearest) return nothing end
    if box(nearest.addr) === box(addr(me)) return nothing end
    if norm(pos(me) - pos(nearest)) < (1.0 - tolerance) * norm(pos(me) - pos(service))
        migrate(service, me, postcode(nearest))
    end
    return nothing
end
