function need_upstream_friend(me::ClusterActor)
    return length(me.upstream_friends) < TARGET_FRIEND_COUNT
end

function credit_friend(me::ClusterActor, friend_addr::Addr, service)
    friend = get(me.upstream_friends, friend_addr, nothing)
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
end

struct FriendRequest
    requestor::Addr
end

function getanewfriend(me::ClusterActor, service)
    length(me.peers) > 0 || return
    while true
        peer = rand(me.peers.cache)[2]
        if peer.addr != addr(me)
            send(service, me, peer.addr, FriendRequest(addr(me)))
            return nothing
        end
    end
end

struct UnfriendRequest
    requestor::Addr
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

struct FriendResponse
    responder::Addr
    accepted::Bool
end

function Circo.onmessage(me::ClusterActor, msg::FriendRequest, service)
    friendsalready = msg.requestor in me.downstream_friends
    accepted = !friendsalready && length(me.downstream_friends) < MAX_DOWNSTREAM_FRIENDS
    if accepted
        push!(me.downstream_friends, msg.requestor)
        if !haskey(me.upstream_friends, msg.requestor) # TODO: Friendships start as symmetric for now
            send(service, me, msg.requestor, FriendRequest(addr(me)))
        end
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
    send(service, me, msg.responder, PeersRequest(addr(me)))
end

function Circo.onmessage(me::ClusterActor, msg::UnfriendRequest, service)
    pop!(me.downstream_friends, msg.requestor)
    return nothing
end

function send_downstream(service, me::ClusterActor, msg)
    for friend in me.downstream_friends
        send(service, me, friend, deepcopy(msg))
    end
    return nothing
end

