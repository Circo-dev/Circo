# SPDX-License-Identifier: MPL-2.0
using Logging

function cluster_initialized end
cluster_initialized(::Plugin, args...) = nothing
cluster_initialized_hook = Plugins.create_lifecyclehook(cluster_initialized)

const NAME = "cluster"
const MAX_JOINREQUEST_COUNT = 10
const MAX_DOWNSTREAM_FRIENDS = 25
const TARGET_FRIEND_COUNT = 5
const MIN_FRIEND_COUNT = 3

mutable struct ClusterService <: Plugin
    roots::Array{PostCode}
    helper::AbstractActor
    ClusterService(;roots=[], _...) = new(roots)
end
Plugins.symbol(::ClusterService) = :cluster
Circo.schedule_start(cluster::ClusterService, scheduler) = begin
    cluster.helper = ClusterActor(emptycore(scheduler.service);roots=cluster.roots)
    spawn(scheduler.service, cluster.helper)
    call_lifecycle_hook(scheduler, cluster_initialized_hook, cluster)
end

Circo.schedule_stop(cluster::ClusterService, scheduler) = begin
    send_leaving(cluster.helper, scheduler.service)
end

mutable struct NodeInfo
    name::String
    addr::Addr
    pos::Pos
    NodeInfo(name) = new(name)
    NodeInfo() = new()
end
Circo.pos(i::NodeInfo) = i.pos
Circo.addr(i::NodeInfo) = i.addr
Circo.postcode(i::NodeInfo) = postcode(addr(i))

struct Joined <: CircoCore.Event
    peers::Array{NodeInfo}
end

struct Leaving # TODO sent out directly, should (also) create an event.
    who::Addr
    upstream_friends::Vector{Addr}
end

struct PeerListUpdated <: CircoCore.Event
    peers::Array{NodeInfo}
end

mutable struct Friend
    addr::Addr
    score::UInt
    Friend(info) = new(info)
end
Base.isless(a::Friend,b::Friend) = Base.isless(a.score, b.score)

mutable struct ClusterActor{TCore} <: AbstractActor{TCore}
    myinfo::NodeInfo
    roots::Array{PostCode}
    joined::Bool
    joinrequestcount::UInt16
    peers::Dict{Addr,NodeInfo}
    upstream_friends::Dict{Addr,Friend}
    downstream_friends::Set{Addr}
    peerupdate_count::UInt
    servicename::String
    eventdispatcher::Addr
    core::TCore
    ClusterActor(myinfo::NodeInfo, roots, core) = new{typeof(core)}(myinfo, roots, false, 0, Dict(), Dict(), Set(), 0, NAME, Addr(), core)
end
ClusterActor(myinfo::NodeInfo, core) = ClusterActor(myinfo, [], core)
ClusterActor(core;roots=[]) = ClusterActor(NodeInfo("unnamed"), roots, core)

Circo.monitorextra(me::ClusterActor) = (myinfo=me.myinfo, peers=values(me.peers))
Circo.monitorprojection(::Type{<:ClusterActor}) = JS("projections.nonimportant")

struct JoinRequest
    info::NodeInfo
end

struct JoinResponse
    requestorinfo::NodeInfo
    responderinfo::NodeInfo
    peers::Array{NodeInfo}
    accepted::Bool
end

struct PeerJoinedNotification
    peer::NodeInfo
    creditto::Addr
end

struct PeerLeavingNotification
    peer::NodeInfo
    creditto::Addr
end

struct PeerListRequest
    respondto::Addr
end

struct PeerListResponse
    peers::Array{NodeInfo}
end

struct FriendRequest
    requestor::Addr
end

struct FriendResponse
    responder::Addr
    accepted::Bool
end

struct UnfriendRequest
    requestor::Addr
end

struct ForceAddRoot
    root::PostCode
end

function requestjoin(me::ClusterActor, service)
    if !isempty(me.servicename)
        registername(service, NAME, me)
    end
    if length(me.roots) == 0
        registerpeer(me, me.myinfo, service)
        return
    end
    if me.joinrequestcount >= MAX_JOINREQUEST_COUNT
        error("Cannot join: $(me.joinrequestcount) unsuccesful attempt.")
    end
    root = rand(me.roots)
    @debug "$(addr(me)) : Requesting join to $root"
    sendjoinrequest(me, root, service)
end

function sendjoinrequest(me::ClusterActor, root::PostCode, service)
    me.joinrequestcount += 1
    rootaddr = Addr(root)
    if CircoCore.isbaseaddress(rootaddr)
        @debug "$(addr(me)) : Querying name 'cluster'"
        send(service, me, Addr(root), NameQuery("cluster");timeout=10.0)
    else
        @debug "Got direct root address: $root" # TODO possible only because PostCode==String, which is bad
        send(service, me, rootaddr, JoinRequest(me.myinfo))
    end
end

function Circo.onmessage(me::ClusterActor, msg::ForceAddRoot, service)
    @debug "$(addr(me)) : Got $msg"
    push!(me.roots, msg.root)
    sendjoinrequest(me, msg.root, service)
end

function Circo.onspawn(me::ClusterActor, service)
    me.myinfo.addr = addr(me)
    me.myinfo.pos = pos(service)
    me.eventdispatcher = spawn(service, EventDispatcher(emptycore(service)))
    requestjoin(me, service)
end

function setpeer(me::ClusterActor, peer::NodeInfo)
    me.peerupdate_count += 1
    if haskey(me.peers, peer.addr) # TODO update?
        return false
    end
    me.peers[peer.addr] = peer
    @debug "$(addr(me)) :Peer $peer set."
    return true
end

function registerpeer(me::ClusterActor, newpeer::NodeInfo, service)
    if setpeer(me, newpeer)
        @debug "$(addr(me)) : PeerList updated"
        fire(service, me, PeerListUpdated(collect(values(me.peers))))
        for friend in me.downstream_friends
            send(service, me, friend, PeerJoinedNotification(newpeer, addr(me)))
        end
        return true
    end
    return false
end

function Circo.onmessage(me::ClusterActor, messsage::Subscribe{Joined}, service)
    if me.joined # TODO The lately sent event may contain different data. Is that a problem?
        send(service, me, messsage.subscriber, Joined(collect(values(me.peers)))) #TODO handle late subscription to one-off events automatically
    end
    send(service, me, me.eventdispatcher, messsage)
end

function Circo.onmessage(me::ClusterActor, messsage::Subscribe{PeerListUpdated}, service)
    if length(me.peers) > 0
        send(service, me, messsage.subscriber, PeerListUpdated(collect(values(me.peers)))) # TODO State-change events may need a better (automatic) mechanism for handling initial state
    end
    send(service, me, me.eventdispatcher, messsage)
end

function Circo.onmessage(me::ClusterActor, msg::NameResponse, service)
    @debug "Got $msg"
    if msg.query.name != "cluster"
        @error "Got unrequested $msg"
    end
    root = msg.handler
    if isnothing(root)
        @debug "$(addr(me)) : Got no handler for cluster query"
        requestjoin(me, service)
    elseif root == addr(me)
        @info "Got own address as cluster"
    else
        send(service, me, root, JoinRequest(me.myinfo))
    end
end

function Circo.onmessage(me::ClusterActor, msg::JoinRequest, service)
    newpeer = msg.info
    if (length(me.upstream_friends) < TARGET_FRIEND_COUNT)
        send(service, me, newpeer.addr, FriendRequest(addr(me)))
    end
    if registerpeer(me, newpeer, service)
        @info "Got new peer $(newpeer.addr) . $(length(me.peers)) nodes in cluster."
    end
    send(service, me, newpeer.addr, JoinResponse(newpeer, me.myinfo, collect(values(me.peers)), true))
end

function Circo.onmessage(me::ClusterActor, msg::JoinResponse, service)
    if msg.accepted
        me.joined = true
        initpeers(me, msg.peers, service)
        send(service, me, me.eventdispatcher, Joined(collect(values(me.peers))))
        @info "Joined to cluster using root node $(msg.responderinfo.addr). ($(length(msg.peers)) peers)"
    else
        requestjoin(me, service)
    end
end

function initpeers(me::ClusterActor, peers::Array{NodeInfo}, service)
    for peer in peers
        setpeer(me, peer)
    end
    fire(service, me, PeerListUpdated(collect(values(me.peers))))
    for i in 1:min(TARGET_FRIEND_COUNT, length(peers))
        getanewfriend(me, service)
    end
end

function Circo.onmessage(me::ClusterActor, msg::PeerListRequest, service)
    send(service, me, msg.respondto, PeerListResponse(collect(values(me.peers))))
end

function Circo.onmessage(me::ClusterActor, msg::PeerListResponse, service)
    for peer in msg.peers
        setpeer(me, peer)
    end
end

function Circo.onmessage(me::ClusterActor, msg::PeerJoinedNotification, service)
    if registerpeer(me, msg.peer, service)
        friend = get(me.upstream_friends, msg.creditto, nothing)
        isnothing(friend) && return
        friend.score += 1
        if friend.score == 100
            replaceafriend(me, service)
            for f in values(me.upstream_friends)
                f.score = 0
            end
        elseif friend.score % 10 == 0
            if length(me.upstream_friends) < MIN_FRIEND_COUNT
                getanewfriend(me, service)
            end
        end
        @debug "$(addr(me)): Peer joined: $(msg.peer.addr)"
    end
end

function getanewfriend(me::ClusterActor, service)
    length(me.peers) > 0 || return
    while true
        peer = rand(me.peers)[2]
        if peer.addr != addr(me)
            send(service, me, peer.addr, FriendRequest(addr(me)))
            return nothing
        end
    end
end

function dropafriend(me::ClusterActor, service)
    length(me.upstream_friends) > MIN_FRIEND_COUNT || return
    weakestfriend = minimum(values(me.upstream_friends))
    if weakestfriend.score > 0
        return
    end
    @debug "Dropping friend $(weakestfriend)"
    send(service, me, weakestfriend.addr, UnfriendRequest(addr(me)))
    delete!(me.upstream_friends, weakestfriend.addr)
end

function replaceafriend(me::ClusterActor, service)
    dropafriend(me, service)
    if length(me.upstream_friends) < MIN_FRIEND_COUNT
        getanewfriend(me, service)
    end
end

function Circo.onmessage(me::ClusterActor, msg::FriendRequest, service)
    friendsalready = msg.requestor in me.downstream_friends
    accepted = !friendsalready && length(me.downstream_friends) < MAX_DOWNSTREAM_FRIENDS
    if accepted
        push!(me.downstream_friends, msg.requestor)
    end
    send(service, me, msg.requestor, FriendResponse(addr(me), accepted))
end

function Circo.onmessage(me::ClusterActor, msg::FriendResponse, service)
    if msg.accepted
        me.upstream_friends[msg.responder] = Friend(msg.responder)
    end
    # Ask for the current peer list to get concurrently joined peers (Some may still be missing,
    # so only regular status updates will lead to convergence when join concurrency is high.)
    # TODO should try to get another friend instead of sending this if our friend request was denied
    send(service, me, msg.responder, PeerListRequest(addr(me)))
end

function Circo.onmessage(me::ClusterActor, msg::UnfriendRequest, service)
    pop!(me.downstream_friends, msg.requestor)
end

function send_leaving(me::ClusterActor, service)
    notification = Leaving(addr(me), map(f -> f.addr, values(me.upstream_friends)))
    for friend in me.downstream_friends
        send(service, me, friend, notification)
    end
end

function removepeer(me::ClusterActor, peer::Addr)
    delete!(me.peers, peer)
    delete!(me.upstream_friends, peer)
    delete!(me.downstream_friends, peer)
end

function Circo.onmessage(me::ClusterActor, msg::Leaving, service)
    who = msg.who
    if haskey(me.peers, who)
        nodeinfo  = me.peers[who]
        for friend in me.downstream_friends
            send(service, me, friend, PeerLeavingNotification(nodeinfo, addr(me)))
        end
    end
    removepeer(me, who)
    @debug "Friend $(msg.who) is left. $(length(me.peers)) peers left."
end

function Circo.onmessage(me::ClusterActor, msg::PeerLeavingNotification, service)
    @debug "$(addr(me)): Got leaving notification about $(msg.peer.addr).  $(length(me.peers)) peers left."
    removepeer(me, msg.peer.addr)
end

# TODO: update peers
#@inline function CircoCore.actor_activity_sparse256(cluster::ClusterService, scheduler, actor::AbstractActor)
#   if rand(UInt8) == 0
#
#    end
#end
