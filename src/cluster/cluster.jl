# SPDX-License-Identifier: MPL-2.0
module Cluster

export NodeInfo, Peers, PeerAdded, PeerRemoved, PeerUpdated, ClusterService, PeersRequest, PeersResponse

using ..Circo, ..CircoCore.Registry, ..Circo.Monitor
using Plugins
using Logging

function cluster_initialized end
cluster_initialized(::Plugin, sdl, cluster) = nothing
cluster_initialized_hook = Plugins.create_lifecyclehook(cluster_initialized)

const NAME = "cluster"
const MAX_JOINREQUEST_COUNT = 10
const MAX_DOWNSTREAM_FRIENDS = 15
const TARGET_FRIEND_COUNT = 5
const MIN_FRIEND_COUNT = 3

abstract type ClusterService <: Plugin end
mutable struct ClusterServiceImpl <: ClusterService
    roots::Array{PostCode}
    helper::Actor
    ClusterServiceImpl(; roots=[], _...) = new(roots)
end
Plugins.symbol(::ClusterService) = :cluster
__init__() = Plugins.register(ClusterServiceImpl)

roots(c::ClusterService) = c.roots

Circo.schedule_start(cluster::ClusterServiceImpl, scheduler) = begin
    cluster.helper = ClusterActor(emptycore(scheduler.service); roots=cluster.roots)
    spawn(scheduler.service, cluster.helper)
    Circo.call_lifecycle_hook(scheduler, cluster_initialized_hook, cluster)
end

Circo.schedule_stop(cluster::ClusterServiceImpl, scheduler) = begin
    send_leaving(cluster.helper, scheduler.service)
end

mutable struct NodeInfo
    extrainfo::Dict{Symbol,Any}
    name::String
    addr::Addr
    pos::Pos
    NodeInfo(name) = new(Dict(), name)
    NodeInfo() = new(Dict())
end
Circo.pos(i::NodeInfo) = i.pos
Circo.addr(i::NodeInfo) = i.addr
Circo.postcode(i::NodeInfo) = postcode(addr(i))

struct Peers
    cache::Dict{Addr,NodeInfo}
    Peers() = new(Dict())
    Peers(peersarray) = new(Dict([peer.addr => peer for peer in peersarray]))
end
Base.getindex(peers::Peers, addr) = peers.cache[addr]
Base.setindex!(peers::Peers, peer, addr) = peers.cache[addr] = peer
Base.delete!(peers::Peers, addr) = delete!(peers.cache, addr)
Base.get(peers::Peers, k, def) = get(peers.cache, k, def)
Base.values(peers::Peers) = values(peers.cache)
Base.length(peers::Peers) = length(peers.cache)

mutable struct Friend
    addr::Addr
    score::UInt
    Friend(info) = new(info, 0)
end
Base.isless(a::Friend,b::Friend) = Base.isless(a.score, b.score)

mutable struct ClusterActor{TCore} <: Actor{TCore}
    myinfo::NodeInfo
    roots::Array{PostCode}
    joined::Bool
    joinrequestcount::UInt16
    peers::Peers
    upstream_friends::Dict{Addr,Friend}
    downstream_friends::Set{Addr}
    peerupdate_count::UInt # stats only
    eventdispatcher::Addr
    core::TCore
    ClusterActor(myinfo::NodeInfo, roots, core) = new{typeof(core)}(myinfo, roots, false, 0, Peers(), Dict(), Set(), 0, Addr(), core)
end
ClusterActor(myinfo::NodeInfo, core) = ClusterActor(myinfo, [], core)
ClusterActor(core;roots=[]) = ClusterActor(NodeInfo("unnamed"), roots, core)

Circo.traits(::Type{<:ClusterActor}) = (EventSource,)

Circo.monitorprojection(::Type{<:ClusterActor}) = JS("projections.nonimportant")

struct RequestJoin end

function Circo.onmessage(me::ClusterActor, ::OnSpawn, service)
    me.myinfo.addr = addr(me)
    me.myinfo.pos = pos(service)
    try
        registername(service, NAME, me)
    catch e
        @warn "Cannot register $NAME: $e"
    end
    send(service, me, me, RequestJoin())
end

include("peers.jl")
include("friends.jl")

end # module
