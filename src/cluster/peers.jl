function requestjoin(me::ClusterActor, service)
    if isempty(me.roots)
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

struct JoinRequest
    info::NodeInfo
end

function sendjoinrequest(me::ClusterActor, root::PostCode, service)
    me.joinrequestcount += 1
    rootaddr = Addr(root)
    if CircoCore.isbaseaddress(rootaddr)
        @debug "$(addr(me)) : Querying name 'cluster'"
        send(service, me, Addr(root), NameQuery("cluster");timeout=10.0)
    else
        @debug "Got direct root address: $root" # TODO possible only because PostCode==String, which is bad
        send(service, me, rootaddr, JoinRequest(deepcopy(me.myinfo)))
    end
end

struct ForceAddRoot
    root::PostCode
end

function Circo.onmessage(me::ClusterActor, msg::ForceAddRoot, service)
    @debug "$(addr(me)) : Got $msg"
    push!(me.roots, msg.root)
    sendjoinrequest(me, msg.root, service)
end

function setpeer(me::ClusterActor, peer::NodeInfo, service)
    me.peerupdate_count += 1
    if haskey(me.peers.cache, peer.addr)
        return false
    end
    me.peers[peer.addr] = peer
    @debug "$(addr(me)) :Peer $peer set."
    fire(service, me, PeerAdded(deepcopy(peer)))
    return true
end

struct PeerAdded <: CircoCore.Event
    peer::NodeInfo
end

struct PeerRemoved <: CircoCore.Event
    peer::NodeInfo
end

struct PeerUpdated <: CircoCore.Event
    peer::NodeInfo
    key::Symbol
    info::Any
end

struct PeerJoinedNotification
    peer::NodeInfo
    creditto::Addr
end

function registerpeer(me::ClusterActor, newpeer::NodeInfo, service)
    if setpeer(me, newpeer, service)
        @debug "$(addr(me)) : Peer registered"
        for friend in me.downstream_friends
            send(service, me, friend, PeerJoinedNotification(deepcopy(newpeer), addr(me)))
        end
        return true
    end
    return false
end

struct Joined <: CircoCore.Event
    peers::Array{NodeInfo}
end

function Circo.onmessage(me::ClusterActor, messsage::Subscribe{Joined}, service)
    if me.joined # TODO The lately sent event may contain different data. Is that a problem?
        send(service, me, messsage.subscriber, Joined(deepcopy(collect(values(me.peers))))) #TODO handle late subscription to one-off events automatically
    end
    send(service, me, me.eventdispatcher, messsage)
end

function Circo.onmessage(me::ClusterActor, msg::CircoCore.Registry.NameResponse, service)
    @debug "Got $msg"
    if msg.query.name != NAME
        @error "Got unrequested $msg"
        return nothing
    end
    root = msg.handler
    if isnothing(root)
        @debug "$(addr(me)) : Got no handler for cluster query"
        requestjoin(me, service)
    elseif root == addr(me)
        @info "Got own address as cluster"
    else
        send(service, me, root, JoinRequest(deepcopy(me.myinfo)))
    end
    return nothing
end

struct JoinResponse
    requestorinfo::NodeInfo
    responderinfo::NodeInfo
    peers::Peers
    accepted::Bool
end

function Circo.onmessage(me::ClusterActor, msg::JoinRequest, service)
    newpeer = msg.info
    if need_upstream_friend(me)
        send(service, me, newpeer.addr, FriendRequest(addr(me)))
    end
    if registerpeer(me, newpeer, service)
        @info "Got new peer $(newpeer.addr) . $(length(me.peers)) nodes in cluster."
    end
    send(service, me, newpeer.addr, JoinResponse(newpeer, deepcopy(me.myinfo), deepcopy(me.peers), true))
end

function Circo.onmessage(me::ClusterActor, msg::JoinResponse, service)
    if msg.accepted
        me.joined = true
        initpeers(me, msg.peers, service)
        send(service, me, me.eventdispatcher, Joined(deepcopy(collect(values(me.peers)))))
        @info "Joined to cluster using root node $(msg.responderinfo.addr). ($(length(msg.peers)) peers)"
    else
        requestjoin(me, service)
    end
end

function initpeers(me::ClusterActor, peers::Peers, service)
    for peer in values(peers)
        setpeer(me, peer, service)
    end
    for i in 1:min(TARGET_FRIEND_COUNT, length(peers))
        getanewfriend(me, service)
    end
end

struct PeersRequest
    respondto::Addr
end
struct PeersResponse
    peers::Peers
end

function Circo.onmessage(me::ClusterActor, msg::PeersRequest, service)
    send(service, me, msg.respondto, PeersResponse(deepcopy(me.peers)))
end

function Circo.onmessage(me::ClusterActor, msg::PeersResponse, service)
    for peer in values(msg.peers)
        setpeer(me, peer, service)
    end
end

function Circo.onmessage(me::ClusterActor, msg::PeerJoinedNotification, service)
    if registerpeer(me, msg.peer, service)
        credit_friend(me, msg.creditto, service)
        @debug "$(addr(me)): Peer joined: $(msg.peer.addr)"
    end
end

struct Leaving # TODO sent out directly, should (also) create an event.
    who::Addr
    upstream_friends::Vector{Addr}
end

function send_leaving(me::ClusterActor, service)
    notification = Leaving(addr(me), map(f -> f.addr, values(me.upstream_friends)))
    for friend in me.downstream_friends
        send(service, me, friend, notification)
    end
    return nothing
end

function removepeer(me::ClusterActor, peer::Addr)
    delete!(me.peers.cache, peer)
    delete!(me.upstream_friends, peer)
    delete!(me.downstream_friends, peer)
    return nothing
end

struct PeerLeavingNotification
    peer::NodeInfo
    creditto::Addr
end

function Circo.onmessage(me::ClusterActor, msg::Leaving, service)
    who = msg.who
    if haskey(me.peers.cache, who)
        peer  = me.peers.cache[who]
        send_downstream(service, me, PeerLeavingNotification(deepcopy(peer), addr(me)))
        removepeer(me, who)
        fire(service, me, PeerRemoved(deepcopy(peer)))
    end
    @debug "Friend $(msg.who) is left. $(length(me.peers.cache)) peers left."
end

function Circo.onmessage(me::ClusterActor, msg::PeerLeavingNotification, service)
    @debug "$(addr(me)): Got leaving notification about $(msg.peer.addr).  $(length(me.peers)) peers left."
    removepeer(me, msg.peer.addr)
end


