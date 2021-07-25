# SPDX-License-Identifier: MPL-2.0
module Reference

using ....Circo
using Circo.Migration
import ..DistributedIdentities: DistIdId, Peer, PeerAdded, PeerRemoved, addrs

export IdRef

mutable struct IdRef{TCore} <: Actor{TCore}
    id::DistIdId
    peer_addrs::Vector{Addr}
    core::TCore
    IdRef(id, distid, core) = new{typeof(core)}(id, addrs(distid), core)
end

Circo.onspawn(me::IdRef, service) = begin
    for peer_addr in me.peer_addrs # TODO: only connect to a subset
        connect_peer(me, peer_addr, service)
    end
end

function connect_peer(me::IdRef, peer_addr, service)
    send(service, me, peer_addr, Subscribe{PeerAdded}(me))
    send(service, me, peer_addr, Subscribe{PeerRemoved}(me))
end

Circo.onmessage(me::IdRef, msg::PeerAdded, service) = begin
    msg.distid == me.id || return
    idx = findfirst(a -> a == msg.addr, me.peer_addrs)
    if isnothing(idx)
        push!(me.peer_addrs, msg.addr)
        connect_peer(me, msg.addr, service)
    end
end

Circo.onmessage(me::IdRef, msg::PeerRemoved, service) = begin
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

end # module