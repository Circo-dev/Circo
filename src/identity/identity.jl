# SPDX-License-Identifier: MPL-2.0
module DistributedIdentities

# Experimental and incomplete
# TODO
#   - Spread in space
#   - Fix overspwawning when multiple instance dies
#   - Provide hooks
#   - Implement sparse identity

export DistIdService,
    @distid_field, DistributedIdentity, DenseDistributedIdentity,
    distid, peers

using Dates
using Plugins
using ..Circo

const DistIdId = UInt128

const PING_INTERVAL = 2 # TODO -> adaptive
const MISSING_THRESHOLD = 4 * PING_INTERVAL # Peer is considered missing (kill voting will be started) if failed to answer that many pings
const VOTE_FOR_KILL_THRESHOLD = 2 * PING_INTERVAL # Not answering for this long is enough for a kill vote
const NO_NEW_VOTING_AFTER_VOTED = PING_INTERVAL # When voted for kill a peer, don't start another vote

const START_CHECK_AFTER = 20 # Do not check for missing actors immediately after spawn to allow compilation/initialization

struct DistributedIdentityException <: Exception
    distid::Union{DistIdId, Nothing}
    message::String
    DistributedIdentityException(id::DistIdId, msg) = new(id, msg)
    DistributedIdentityException(idactor, msg) = new(isdefined(idactor, :distid) ? idactor.distid.id : nothing, msg)
end

function showerror(io::IO, e::DistributedIdentityException)
    !isnothing(e.distid) && print(io, e.distid, ": ")
    print(io, message)
end

function dbg_hdr(me)
    return "$(Dates.now()) 0x$(string(box(me), base=16)):"
end

abstract type IdentityStyle end
struct ActorIdentity <: IdentityStyle end

abstract type DistributedIdentityStyle <: IdentityStyle end
struct DenseDistributedIdentity <: DistributedIdentityStyle end

identity_style(::Type) = ActorIdentity()

struct PeerRemoved <: Event
    distid::DistIdId
    addr::Addr
end

struct PeerAdded <: Event
    distid::DistIdId
    addr::Addr
end

abstract type DistIdService <: Plugin end
mutable struct DistIdServiceImpl <: DistIdService
    DistIdServiceImpl(;opts...) = new()
end
__init__() = Plugins.register(DistIdServiceImpl)

function onidmessage(idstyle, me, msg, service) end # Normal actors ignore id messages by default

@inline Circo.localdelivery(::DistIdServiceImpl, scheduler, msg, targetactor) = begin
    onidmessage(identity_style(typeof(targetactor)), targetactor, body(msg), scheduler.service)
    return false
end

function onidspawn(idstyle, me, service) end

Circo.actor_spawning(::DistIdServiceImpl, scheduler, actor) = begin
    onidspawn(identity_style(typeof(actor)), actor, scheduler.service)
    return false
end

"""
    function create_peer(prototype::Actor)

Will be called to create a new peer by `prototype` for its distributed identity.
"""
function create_peer(prototype::Actor, service)
    retval = deepcopy(prototype)
    retval.core = emptycore(service)
    return retval
end

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

mutable struct DistributedIdentity
    id::DistIdId
    peers::Dict{Addr,Peer}
    redundancy::Int
    eventdispatcher::Addr     
    DistributedIdentity(id = rand(DistIdId), peers=[]; redundancy=3) = new(id, Dict(map(p_addr -> p_addr => Peer(p_addr), peers)), redundancy)
end

macro distid_field()
    return quote
        distid::Circo.DistributedIdentities.DistributedIdentity
    end |> esc
end

function check_distid(me)
    if identity_style(typeof(me)) == ActorIdentity
        throw(DistributedIdentityException(nothing, "Not a distributed identity. Please overload `identity_style(::Type{$(typeof(me))})`"))
    end
    nothing
end

function peers(me)
    check_distid(me)
    return map(p -> p.addr, values(me.distid.peers))
end

function distid(me)
    check_distid(me)
    return me.distid.id
end

function addrs(me)
    return [peers(me)..., addr(me)]
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

onidspawn(::DenseDistributedIdentity, me, service) = begin
    @debug "$(dbg_hdr(me)): Spawning."
    if !isdefined(me, :distid)
        me.distid = DistributedIdentity()
    end
    me.eventdispatcher = spawn(service, EventDispatcher(emptycore(service)))
    spawnpeer_ifneeded(me, service)
    sendtopeers(service, me, Hello(addr(me)))
    for peer in values(me.distid.peers)
        peer.lastseen = time() + START_CHECK_AFTER
    end
    settimeout(service, me, PING_INTERVAL * (abs(randn()) * 0.2 + 1))
end

function spawnpeer_ifneeded(me, service)
    if length(me.distid.peers) < me.distid.redundancy - 1
        newpeer = create_peer(me, service)
        newpeer.distid = deepcopy(me.distid)
        newpeer.distid.peers[addr(me)] = Peer(addr(me))
        newpeer_addr = spawn(service, newpeer)
        fire(service, me, PeerAdded(me.distid.id, newpeer_addr))
    end
end

onidmessage(::DenseDistributedIdentity, me, msg::Hello, service) = begin
    peer = get!(me.distid.peers, msg.respondto) do
        fire(service, me, PeerAdded(me.distid.id, msg.respondto))
        Peer(msg.respondto)
    end
    peer.lastseen = time()
    #@debug "$(dbg_hdr(me)): New peer (Now $(length(me.distid.peers)) peers): $(msg.respondto)."
    send(service, me, peer.addr, Bello(addr(me)))
end

onidmessage(::DenseDistributedIdentity, me, msg::Bello, service) = begin
    peer = get!(me.distid.peers, msg.respondto) do 
        Peer(msg.respondto)
    end
    peer.lastseen = time()
end

onidmessage(::DenseDistributedIdentity, me, msg::Ping, service) = begin
    peer = get(me.distid.peers, msg.respondto, nothing)
    isnothing(peer) && return
    peer.lastseen = time()
    send(service, me, peer.addr, Pong(addr(me)))
end

onidmessage(::DenseDistributedIdentity, me, msg::Pong, service) = begin
    peer = get(me.distid.peers, msg.respondto, nothing)
    isnothing(peer) && return
    peer.lastseen = time()
end

function check_peers(me, service)
    ping_threshold = time() - PING_INTERVAL
    nonresp_threshold = time() - MISSING_THRESHOLD
    for peer in values(me.distid.peers)
        if peer.lastseen < nonresp_threshold
            nonresponding_peer_found(me, peer, service)
        elseif peer.lastseen < ping_threshold
            send(service, me, peer.addr, Ping(addr(me)))
        end 
    end
end

onidmessage(::DenseDistributedIdentity, me, ::Timeout, service) = begin
    check_peers(me, service)   
    settimeout(service, me, PING_INTERVAL)
end

struct NonResponding
    respondto::Addr
    nonresponding::Addr
    timestamp::Float64
end

function sendtopeers(service, me, msg; excludes = nothing)
    for peer in values(me.distid.peers)
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
    @debug "$(dbg_hdr(me)): Non-responding peer found: $(addr(nonresp_peer))"
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

onidmessage(::DenseDistributedIdentity, me, msg::NonResponding, service) = begin
    nonresp_peer = get(me.distid.peers, msg.nonresponding, nothing)
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
    #@debug "$(dbg_hdr(me)): Voting with $iamforkill for killing $(msg.nonresponding)"
    nonresp_peer.mylastvote = KillVote(msg.nonresponding, iamforkill, addr(me))
    send(service, me, msg.respondto, nonresp_peer.mylastvote)
end

onidmessage(::DenseDistributedIdentity, me, msg::KillVote, service) = begin
    target = get(me.distid.peers, msg.target, nothing)
    if isnothing(target) # Late vote, already killed
        #@debug "$(dbg_hdr(me)): Late vote: $msg"
        return
    end
    if isnothing(target.killvotes) # Vote on canceled voting
        #@debug "$(dbg_hdr(me)): Vote on canceled voting: $msg"
        return
    end
    if isnothing(findfirst(v -> v.voter == msg.voter, target.killvotes)) # not a duplicate vote
        push!(target.killvotes, msg)
        if length(target.killvotes) >= length(me.distid.peers) / 2
            check_killvotes(me, target, service)
        end
    else
        @debug "$(dbg_hdr(me)): Dropping duplicate vote $msg"
    end
end

function check_killvotes(me, target, service)
    votes = target.killvotes
    forkill_votecount = count(vote -> vote.kill, votes)
    threshold = (length(me.distid.peers) - 1) / 2
    voteresult = forkill_votecount > threshold
    @debug "$(dbg_hdr(me)): Kill voting results for $(box(addr(target))): $forkill_votecount / $(length(votes)) (peers: $(length(me.distid.peers))). Will kill: $voteresult"
    if voteresult
        kill_and_spawn_other(me, target, service)
    elseif length(votes) - forkill_votecount > threshold # Too many no
        cancel_voting(me, target)
    end
end

function cancel_voting(me, target)
    #@debug "$(dbg_hdr(me)): Canceling voting for $(box(addr(target)))"
    target.killvotes = nothing
end

struct Killed
    target::Addr
end

struct Die end

function kill_and_spawn_other(me, target, service)
    send(service, me, target, Die())
    delete!(me.distid.peers, addr(target))
    sendtopeers(service, me, Killed(target))
    fire(service, me, PeerRemoved(me.distid.id, target))
    spawnpeer_ifneeded(me, service)
end

onidmessage(::DenseDistributedIdentity, me, msg::Killed, service) = begin
    send(service, me, msg.target, Die())
    delete!(me.distid.peers, msg.target)
end

onidmessage(::DenseDistributedIdentity, me, msg::Die, service) = begin
    @debug "$(dbg_hdr(me)): Dying on request."
    die(service, me)
end

function commit!(me::Actor, selector::Symbol, value)

end

function commit!(callback::Function, me::Actor, selector::Symbol, value)
    
end

include("reference.jl")

end # module