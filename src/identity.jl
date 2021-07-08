# Experimental
module DistributedIdentity

export DistId

using ..Circo

const PING_INTERVAL = 0.6 # TODO -> adaptive
const DEAD_THRESHOLD = 4 * PING_INTERVAL # Peer is considered dead if failed to answer that many pings
const VOTE_FOR_KILL_THRESHOLD = 2 * PING_INTERVAL # When a vote to kill a peer was started, not answering that many pings 
const NO_NEW_VOTING_AFTER_VOTED = PING_INTERVAL # When voted for killing a peer, don't start another vote

struct KillVote
    target::Addr
    kill::Bool
    voter::Addr
    timestamp::Float64
    KillVote(target, kill, voter) = new(target, kill, voter, time())
end

mutable struct Peer
    addr::Addr
    lastseen::Float64
    mylastvote::Union{KillVote, Nothing}
    killvotes::Union{Vector{KillVote}, Nothing}
    Peer(addr, _time = time()) = new(addr, _time, nothing, nothing)
end

const DistIdId = UInt128

mutable struct DistId <: Actor{Any}
    id::DistIdId
    peers::Dict{Addr,Peer}
    target_size::Int
    core::Any
    DistId(id, peers=Addr[]; target_size=4) = new(id, Dict(map(p_addr -> p_addr => Peer(p_addr), peers)), target_size)
end

struct Hello
    respondto::Addr
end
struct Bello
    respondto::Addr
end

struct Ping
    respondto::Addr
end
struct Pong
    respondto::Addr
end

Circo.onspawn(me::DistId, service) = begin
    @debug "$(box(me)): Spawned."
    if length(me.peers) < me.target_size - 1
        spawnpeer_ifneeded(me, service)
    end
    sendtopeers(service, me, Hello(addr(me)))
    settimeout(service, me, PING_INTERVAL * (randn() * 0.02 + 1))
end

function spawnpeer_ifneeded(me::DistId, service)
    if length(me.peers) < me.target_size
        spawn(service, DistId(me.id, [keys(me.peers)..., addr(me)]; target_size = me.target_size))
    end
end

Circo.onmessage(me::DistId, msg::Hello, service) = begin
    peer = get!(me.peers, msg.respondto) do 
        Peer(msg.respondto)
    end
    peer.lastseen = time()
    #@debug "$(box(me)): New peer (Now $(length(me.peers)) peers): $(msg.respondto)."
    send(service, me, peer.addr, Bello(addr(me)))
end

Circo.onmessage(me::DistId, msg::Bello, service) = begin
    peer = get!(me.peers, msg.respondto) do 
        Peer(msg.respondto)
    end
    peer.lastseen = time()
end

Circo.onmessage(me::DistId, msg::Ping, service) = begin
    peer = get(me.peers, msg.respondto, nothing)
    isnothing(peer) && return
    peer.lastseen = time()
    send(service, me, peer.addr, Pong(addr(me)))
end

Circo.onmessage(me::DistId, msg::Pong, service) = begin
    peer = get(me.peers, msg.respondto, nothing)
    isnothing(peer) && return
    peer.lastseen = time()
end

Circo.onmessage(me::DistId, ::Timeout, service) = begin
    ping_threshold = time() - PING_INTERVAL
    nonresp_threshold = time() - DEAD_THRESHOLD
    for peer in values(me.peers)
        if peer.lastseen < nonresp_threshold
            nonresponding_peer_found(me, peer, service)
        elseif peer.lastseen < ping_threshold
            send(service, me, peer.addr, Ping(addr(me)))
        end 
    end
    settimeout(service, me, PING_INTERVAL)
end

struct NonResponding
    respondto::Addr
    nonresponding::Addr
    timestamp::Float64
end

function sendtopeers(service, me, msg; excludes = nothing)
    for peer in values(me.peers)
        if isnothing(excludes) || !(peer in excludes)
            send(service, me, peer, msg)
        end
    end
end

function nonresponding_peer_found(me, nonresp_peer, service)
    timestamp = time()
    # Voted to kill it recently?
    if !isnothing(nonresp_peer.mylastvote) &&
         nonresp_peer.mylastvote.timestamp > timestamp - NO_NEW_VOTING_AFTER_VOTED &&
         nonresp_peer.mylastvote.kill == true
        return 
    end
    #@debug "$(box(me)): Non-responding peer found: $(addr(nonresp_peer))"
    if isnothing(nonresp_peer.killvotes)
        nonresp_peer.killvotes = []
    end

    # My vote
    nonresp_peer.mylastvote = KillVote(addr(nonresp_peer), true, me)
    push!(nonresp_peer.killvotes, nonresp_peer.mylastvote)

    # Start voting
    sendtopeers(service, me,
        NonResponding(addr(me), nonresp_peer.addr, timestamp);
        excludes = [nonresp_peer])
end

Circo.onmessage(me::DistId, msg::NonResponding, service) = begin
    nonresp_peer = get(me.peers, msg.nonresponding, nothing)
    isnothing(nonresp_peer) && return
    iamforkill = nonresp_peer.lastseen < time() - VOTE_FOR_KILL_THRESHOLD
    if iamforkill
        killvotes = nonresp_peer.killvotes
        if !isnothing(killvotes) && killvotes[1].voter == addr(me) # I already have started another vote.
            if box(me) < box(msg.respondto)   # Am I stronger?
                iamforkill = false
            else
                cancel_voting(me, nonresp_peer)
            end
        end
    end
    #@debug "$(box(me)): Voting with $iamforkill for killing $(msg.nonresponding)"
    nonresp_peer.mylastvote = KillVote(msg.nonresponding, iamforkill, addr(me))
    send(service, me, msg.respondto, nonresp_peer.mylastvote)
end

Circo.onmessage(me::DistId, msg::KillVote, service) = begin
    target = get(me.peers, msg.target, nothing)
    if isnothing(target) # Late vote, already killed
        #@debug "$(box(me)): Late vote: $msg"
        return
    end
    if isnothing(target.killvotes) # Vote on canceled voting
        #@debug "$(box(me)): Vote on canceled voting: $msg"
        return
    end
    if isnothing(findfirst(v -> v.voter == msg.voter, target.killvotes)) # not a duplicate vote
        push!(target.killvotes, msg)
        if length(target.killvotes) >= length(me.peers) / 2
            check_killvotes(me, target, service)
        end
    else
        @debug "$(box(me)): Dropping duplicate vote $msg"
    end
end

function check_killvotes(me, target, service)
    votes = target.killvotes
    forkill_votecount = count(vote -> vote.kill, votes)
    threshold = (length(me.peers) - 1) / 2
    voteresult = forkill_votecount > threshold
    @debug "$(box(me)): Kill voting results for $(box(addr(target))): $forkill_votecount / $(length(votes)) (peers: $(length(me.peers))). Will kill: $voteresult"
    if voteresult
        kill_and_spawn_other(me, target, service)
    elseif length(votes) - forkill_votecount > threshold # Too many no
        cancel_voting(me, target)
    end
end

function cancel_voting(me, target)
    #@debug "$(box(me)): Canceling voting for $(box(addr(target)))"
    target.killvotes = nothing
end

struct Killed
    target::Addr
end

struct Die end

function kill_and_spawn_other(me, target, service)
    send(service, me, target, Die())
    delete!(me.peers, addr(target))
    sendtopeers(service, me, Killed(target))
    spawnpeer_ifneeded(me, service)
end

Circo.onmessage(me::DistId, msg::Killed, service) = begin
    send(service, me, msg.target, Die())
    delete!(me.peers, msg.target)
end

Circo.onmessage(me::DistId, msg::Die, service) = begin
    @debug "$(box(me)): Dying on request."
    die(service, me)
end

end # module