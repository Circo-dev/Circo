# SPDX-License-Identifier: MPL-2.0
module Reference

using ....Circo
using Circo.Migration
import ..DistributedIdentities: DistIdId, Peer, PeerJoined, PeerLeaved, addrs, peers, distid, DistributedIdentity

export IdRef, ref

mutable struct IdRef{TCore} <: Actor{TCore}
    id::DistIdId
    peer_addrs::Vector{Addr}
    core::TCore
    IdRef(distributed_id_peer::Actor, core) = new{typeof(core)}(distid(distributed_id_peer), addrs(distributed_id_peer), core)
    IdRef(id, peers::Vector{Addr}, core) = new{typeof(core)}(id, peers, core)
end

Circo.DistributedIdentities.peers(me::IdRef) = me.peer_addrs
Circo.DistributedIdentities.distid(me::IdRef) = me.id
Circo.monitorprojection(::Type{<:IdRef}) = Circo.Monitor.JS("projections.nonimportant")

Circo.onmessage(me::IdRef, ::OnSpawn, service) = begin
    for peer_addr in me.peer_addrs # TODO: only connect to a subset
        connect_peer(me, peer_addr, service)
    end
end

function connect_peer(me::IdRef, peer_addr, service)
    send(service, me, peer_addr, Subscribe(PeerJoined, me))
    send(service, me, peer_addr, Subscribe(PeerLeaved, me))
end

Circo.onmessage(me::IdRef, msg::PeerJoined, service) = begin
    msg.distid == me.id || return
    idx = findfirst(a -> a == msg.addr, me.peer_addrs)
    if isnothing(idx)
        push!(me.peer_addrs, msg.addr)
        connect_peer(me, msg.addr, service)
    end
end

Circo.onmessage(me::IdRef, msg::PeerLeaved, service) = begin
    msg.distid == me.id || return
    idx = findfirst(a -> a == msg.addr, me.peer_addrs)
    if !isnothing(idx)
        splice!(me.peer_addrs, idx)
    end
end

Circo.onmessage(me::IdRef, msg, service) = begin
    send(service, me, rand(me.peer_addrs), msg) # TODO routing
end

Circo.onmessage(me::IdRef, msg::RecipientMoved, service) = begin
    replace!(me.peer_addrs, msg.oldaddress => msg.newaddress)
    send(service, me, message.newaddress, message.originalmessage)
end

function ref(service, me)
    return IdRef(distid(me), deepcopy(peers(me)), emptycore(service))
end

end # module
