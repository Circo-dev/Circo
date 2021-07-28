# SPDX-License-Identifier: MPL-2.0

# Global, per-cluster singleton Identity registry
module IdRegistry

using Plugins
using CircoCore, Circo, Circo.Cluster, Circo.DistributedIdentities, Circo.Transactions, Circo.DistributedIdentities.Reference

export IdRegistryService, RegisterIdentity, IdentityRegistered, AlreadyRegistered

const REGISTRY_NAME = "global_registry"

mutable struct IdRegistryService <: Plugin
    IdRegistryService(;opts...) = new()
end
Plugins.symbol(::IdRegistryService) = :idregistry

__init__() = Plugins.register(IdRegistryService)

Circo.Cluster.cluster_initialized(me::IdRegistryService, sdl, cluster) = begin
    roots = deepcopy(Cluster.roots(cluster))
    if isempty(roots)
        host = plugin(sdl, :host)
        if isnothing(host) || host.hostroot == postcode(sdl)
            @warn "First node in cluster, starting global identity registry"
            registry_root = IdRegistryPeer()
            spawn(sdl, registry_root)
            ref = spawn(sdl, IdRef(registry_root, emptycore(sdl)))
            registername(sdl, REGISTRY_NAME, ref)
            return
        else
            push!(roots, host.hostroot)
        end
    end
    spawn(sdl, RegistryRefAcquirer(roots))
end

mutable struct IdRegistryPeer <: Actor{Any}
    registered_ids::Dict{String, DistributedIdentities.DistIdId} # Synchronized
    refs::Dict{DistributedIdentities.DistIdId, Addr} # Each registry actor has its own ref. # TODO migrate together with the refs
    eventdispatcher
    @distid_field
    core
    IdRegistryPeer() = new(Dict(), Dict())
end
DistributedIdentities.identity_style(::Type{IdRegistryPeer}) = DenseDistributedIdentity()
Transactions.consistency_style(::Type{IdRegistryPeer}) = Inconsistency() # TODO implement multi-stage commit

struct RegisterIdentity
    respondto::Addr
    key::String
    id::DistributedIdentities.DistIdId
    peers::Vector{Addr}
end
struct IdentityRegistered
    key::String
    id::DistributedIdentities.DistIdId
    peers::Vector{Addr}
end
struct AlreadyRegistered
    id::DistributedIdentities.DistIdId
    key::String
end

struct RegistryWrite <: Write # TODO subtyping allows write recursion, but do we really need it?
    key::String
    id::DistributedIdentities.DistIdId
    peers::Vector{Addr}
end

function Transactions.apply!(me::IdRegistryPeer, write::RegistryWrite, service)
    if isregistered(me, write.key)
        throw(AlreadyRegistered(write.id, write.key))
    end
    ref = spawn(service, IdRef(write.id, deepcopy(write.peers), emptycore(service)))
    me.registered_ids[write.key] = write.id
    me.refs[write.id] = ref
end

Circo.onmessage(me::IdRegistryPeer, msg::RegisterIdentity, service) = begin
    if msg.key == REGISTRY_NAME
        return send(service, me, msg.respondto, AlreadyRegistered(msg.id, msg.key))
    end
    try
        commit!(me, RegistryWrite(msg.key, msg.id, msg.peers), service)
        send(service, me, msg.respondto, IdentityRegistered(msg.key, msg.id, msg.peers))
    catch e
        e isa AlreadyRegistered || rethrow(e)
        send(service, me, msg.respondto, e)
    end
end

function isregistered(me::IdRegistryPeer, name)
    return haskey(me.registered_ids, name)
end

struct RegistryQuery
    respondto::Addr
    key::String
end
struct RegistryResponse
    key::String
    ref::IdRef
end
struct NotFound
    key::String
end

# @msg RegistryQuery => IdRegistryPeer begin
#     id = get(me.registered_ids, msg.key, nothing)
#     isnothing(id) && return NotFound(msg.key)
# end

Circo.onmessage(me::IdRegistryPeer, msg::RegistryQuery, service) = begin
    id = get(me.registered_ids, msg.key, nothing)
    if isnothing(id)
        if msg.key == REGISTRY_NAME # Send a ref to ourself
            send(service, me, msg.respondto, RegistryResponse(msg.key, IdRef(distid(me), deepcopy(peers(me)), emptycore(service))))
        end
        return send(service, me, msg.respondto, NotFound(msg.key))
    end
    myref = get(me.refs, id, nothing)
    if isnothing(myref)
        @error "Ref not found for id $id"
        return
    end
    newref = IdRef(myref.id, deepcopy(myref.peers), emptycore(service))
    send(service, me, msg.respondto, RegistryResponse(msg.key, newref))
end


mutable struct RegistryRefAcquirer <: Actor{Any}
    roots::Vector{PostCode}
    ref::Union{Addr, Nothing}
    queries_sent::Int
    core
    RegistryRefAcquirer(roots) = new(roots, nothing, 0)
end

Circo.onspawn(me::RegistryRefAcquirer, service) = begin
    send_namequery(me, service)
end

function send_namequery(me::RegistryRefAcquirer, service)
    if me.queries_sent >= 10
        error("Unable to acquire reference to the global identity registry.")
    end
    send(service, Addr(rand(me.roots), 0), NameQuery(REGISTRY_NAME))
    me.queries_sent += 1
end

Circo.onmessage(me::RegistryRefAcquirer, msg::NameResponse, service) = begin
    if isnothing(msg.handler)
        send_namequery(me, service)
    else
        send(service, msg.handler, RegistryQuery(me, REGISTRY_NAME))
    end
end

Circo.onmessage(me::RegistryRefAcquirer, msg::RegistryResponse, service) = begin
    ref = spawn(service, msg.ref)
    registername(service, REGISTRY_NAME, ref)
end

Circo.onmessage(me::RegistryRefAcquirer, msg::Timeout, service) = begin
   send_namequery(me, service) 
end


end # module