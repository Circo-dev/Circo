# SPDX-License-Identifier: MPL-2.0

# Global, per-cluster singleton Identity registry
module IdRegistry

using CircoCore, Circo, Circo.DistributedIdentities, Circo.Transactions

mutable struct IdentityRegistry <: Actor{Any}
    registered_ids::Dict{String, DistributedIdentities.DistIdId} # Synchronized
    refs::Dict{DistributedIdentities.DistIdId, IdRef} # Each registry actor has its own ref
    eventdispatcher
    @distid_field
    core
    IdentityRegistry() = new(Dict(), Dict())
end
DistributedIdentities.identity_style(::Type{IdentityRegistry}) = DenseDistributedIdentity()
Transactions.consistency_style(::Type{IdentityRegistry}) = Inconsistency() # TODO implement multi-stage commit

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
    key::String
end

Circo.onmessage(me::IdentityRegistry, msg::RegisterIdentity, service) = begin
    if isregistered(me, msg.key)
        return send(service, me, msg.respondto, AlreadyRegistered(msg.key))
    end
    me.registered_ids[msg.key] = IdRef(msg.id, msg.peers, emptycore(service))
    commit!(me, [
        #Write(msg.key, )
    ], service)
end

function isregistered(me::IdentityRegistry, name)
    return haskey(me.registered_ids, name)
end

end # module