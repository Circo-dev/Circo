# SPDX-License-Identifier: MPL-2.0

# Simple search tree for testing cluster functions and for analyzing infoton optimization strategies

module SearchTreeTest

using Circo, DataStructures, LinearAlgebra

# Infoton optimization parameters
const TARGET_DISTANCE = 150.0
const I = 1.0

# Tree parameters
const ITEM_COUNT = 1_000_000
const ITEMS_PER_LEAF = 1000
const SIBLINGINFO_FREQ = 2 #0..255
const SIBLINGINFO_ENERGY = -1.0
const FULLSPEED_PARALLELISM = 1000
const SCHEDULER_TARGET_ACTORCOUNT = 700.0

# View parameters
const RED_AFTER = ITEMS_PER_LEAF * 0.95 - 1
const NODESCALE_FACTOR = 1 / ITEMS_PER_LEAF / 2

# Test Coordinator that fills the tree and sends Search requests to it
mutable struct Coordinator{TCoreState} <: Actor{TCoreState}
    runmode::UInt8
    size::Int64
    resultcount::UInt64
    lastreportts::UInt64
    root::Addr
    core::TCoreState
    Coordinator(core) = new{typeof(core)}(STOP, 0, 0, 0, nulladdr, core)
end

# Implement monitorextra() to publish part of an actor's state on the UI
Circo.monitorextra(me::Coordinator)  = (
    runmode=me.runmode,
    size = me.size,
    root =!isnothing(me.root) ? me.root.box : nothing
)

# Non-standard Debug messages handled by the Coordinator (See also module Circo.Debug)
struct RunSlow a::UInt8 end# TODO fix MsgPack to allow empty structs
registermsg(RunSlow; ui=true)

struct RunMedium a::UInt8 end# TODO Create UI to allow parametrized messages
registermsg(RunMedium; ui=true)

const STOP = 0
const STEP = 1
const SLOW = 20
const MEDIUM = 98
const FULLSPEED = 100

# Binary search tree that holds a set of TValue values in the leaves (max size of a leaf is ITEMS_PER_LEAF)
mutable struct TreeNode{TValue, TCoreState} <: Actor{TCoreState}
    values::SortedSet{TValue}
    size::Int64
    left::Union{Addr, Nothing}
    right::Union{Addr, Nothing}
    sibling::Union{Addr, Nothing}
    splitvalue::Union{TValue, Nothing}
    core::TCoreState
    TreeNode(values, core) = new{eltype(values), typeof(core)}(SortedSet(values), length(values), nothing, nothing, nothing, nothing, core)
end
Circo.monitorextra(me::TreeNode) =
(left = isnothing(me.left) ? nothing : me.left.box,
 right = isnothing(me.right) ? nothing : me.right.box,
 sibling = isnothing(me.sibling) ? nothing : me.sibling.box,
 splitval = me.splitvalue,
 size = me.size)

 Circo.monitorprojection(::Type{<:TreeNode}) = JS("{
    geometry: new THREE.TetrahedronBufferGeometry(10, 2),
    scale: function(actor) {
        if (actor.extra.left) {
            return { x: 0.4 , y: 0.5, z: 0.4 }
        } else {
            return { x: 0.2 + actor.extra.size * $NODESCALE_FACTOR , y: 0.2 + actor.extra.size * $NODESCALE_FACTOR, z: 0.2 + actor.extra.size * $NODESCALE_FACTOR }
        }
    },
    color: function(actor) {
        return actor.extra.size < $RED_AFTER ? 0x389826 : (actor.extra.left ? 0x9558b2 : 0xcb3c33)
    }
}")

# --- Infoton optimization. We overwrite the default behaviors to allow easy experimentation

# Schedulers pull/push their actors based on the number of actors they schedule
# SCHEDULER_TARGET_ACTOURCOUNT configures the target actorcount.
@inline function actorcount_scheduler_infoton(scheduler, actor::Actor)
    dist = norm(scheduler.pos - actor.core.pos)
    dist === 0.0 && return Infoton(scheduler.pos, 0.0)
    energy = (SCHEDULER_TARGET_ACTORCOUNT - scheduler.actorcount) * 2e-4  # disabled: "/ dist" would mean that force degrades linearly with distance.
    return Infoton(scheduler.pos, energy)
end

Circo.scheduler_infoton(scheduler, actor::Actor) = actorcount_scheduler_infoton(scheduler, actor)

@inline Circo.check_migration(me::Union{TreeNode, Coordinator}, alternatives::MigrationAlternatives, service) = begin
    if length(alternatives) < 5 && rand(UInt8) == 0
        @debug "Only $(length(alternatives)) alternatives at $(box(me)) : $alternatives"
    end
    # if rand(UInt16) == 0
    #     target = rand(alternatives.peers)
    #     me.core.pos = target.pos + Pos(1.0, 1.0, 1.0)
    #     @info "Random migration from $(addr(me)) to $target"
    #     migrate(service, me, postcode(target))
    #     return nothing
    # end
    migrate_to_nearest(me, alternatives, service)
    return nothing
end

@inline Circo.apply_infoton(targetactor::Actor, infoton::Infoton) = begin
    diff = infoton.sourcepos - targetactor.core.pos
    difflen = norm(diff)
    energy = infoton.energy
    if energy > 0 && difflen < TARGET_DISTANCE# || energy < 0 && difflen > TARGET_DISTANCE * 20
        return nothing # Comment out this line to preserve (absolute) energy. This version seems to work better.
        energy = -energy
    end
    targetactor.core.pos += diff / difflen * energy * I
    return nothing
end

# --- End of Infoton optimization

# Tree-messages
struct Add{TValue}
    value::TValue
end

struct Search{TValue}
    value::TValue
    searcher::Addr
end

struct SearchResult{TValue}
    value::TValue
    found::Bool
end

struct SetSibling # TODO UnionAll Addr, default Setter and Getter, no more boilerplate like this. See #14
    value::Addr
end

struct SiblingInfo
    size::UInt64
end

genvalue() = rand(UInt32)
nearpos(pos::Pos=nullpos, maxdistance=10.0) = pos + Pos(rand() * maxdistance, rand() * maxdistance, rand() * maxdistance)

function Circo.onspawn(me::Coordinator, service)
    @debug "onspawn: $me"
    me.core.pos = nearpos(nullpos, 100.0)
    me.root = createnode(Array{UInt32}(undef, 0), service, nearpos(me.core.pos))
    if me.runmode !== STOP
        startround(me, service)
    end
end

function createnode(nodevalues, service, pos=nothing)
    node = TreeNode(nodevalues, emptycore(service))
    retval = spawn(service, node)
    if !isnothing(pos)
        node.core.pos = pos
    end
    return retval
end

# Starts one or more search rounds. A round means a single search for a random value, the result returning to
# to the coordinator. If the tree is not filled fully (as configured by ITEM_COUNT), then a new value
# may also be inserted with some probability
function startround(me::Coordinator, service, parallel = 1)
    if me.size < ITEM_COUNT && rand() <  0.2 + me.size / ITEM_COUNT * 0.8
        send(service, me, me.root, Add(genvalue()))
        me.size += 1
    end
    me.runmode == STOP && return nothing
    if me.runmode == STEP
        me.runmode = STOP
        return nothing
    end
    if (me.runmode != FULLSPEED && rand() > 0.01 * me.runmode)
        sleep(0.001)
    end
    for i in 1:parallel
        send(service, me, me.root, Search(genvalue(), addr(me)))
    end
end

function Circo.onmessage(me::Coordinator, message::SearchResult, service)
    me.core.pos = Pos(0, 0, 0)
    me.resultcount += 1
    if time_ns() > me.lastreportts + 10_000_000_000
        @info("Searches/sec since last report: $(round(me.resultcount * 1e9 / (time_ns() - me.lastreportts)))")
        me.resultcount = 0
        me.lastreportts = time_ns()
    end
    startround(me, service)
end

# When a message comes back as RecipientMoved, the locally stored address of the moved actor has to be updated
# and the message forwarded manually
function Circo.onmessage(me::Coordinator, message::RecipientMoved, service) # TODO a default implementation like this
    if !isnothing(me.root) && box(me.root) === box(message.oldaddress)
        me.root = message.newaddress
    else
        @info "unhandled, forwarding: $message"
    end
    send(service, me, message.newaddress, message.originalmessage)
end

function Circo.onmessage(me::Coordinator, message::Debug.Stop, service)
    me.runmode = STOP
end

function Circo.onmessage(me::Coordinator, message::RunMedium, service)
    oldmode = me.runmode
    me.runmode = MEDIUM
    oldmode == STOP && startround(me, service, 80)
end

function Circo.onmessage(me::Coordinator, message::RunSlow, service)
    oldmode = me.runmode
    me.runmode = SLOW
    oldmode == STOP && startround(me, service)
end

function Circo.onmessage(me::Coordinator, message::Debug.Run, service)
    oldmode = me.runmode
    me.runmode = FULLSPEED
    oldmode == STOP && startround(me, service, FULLSPEED_PARALLELISM)
end

function Circo.onmessage(me::Coordinator, message::Debug.Step, service)
    oldmode = me.runmode
    me.runmode = STEP
    oldmode == STOP && startround(me, service)
end

# Splits a leaf by halving it and pushing the parts to the left and righ children
# TODO do it without that much copying
function split(me::TreeNode, service)
    leftvalues = typeof(me.values)()
    rightvalues = typeof(me.values)()
    idx = 1
    splitat = length(me.values) / 2
    split = false
    for value in me.values
        if split
            push!(rightvalues, value)
        else
            push!(leftvalues, value)
            if idx >= splitat
                me.splitvalue = value
                split = true
            end
        end
        idx += 1
    end
    left = TreeNode(leftvalues, emptycore(service))
    right = TreeNode(rightvalues, emptycore(service))
    me.left = spawn(service, left)
    me.right = spawn(service, right)
    left.core.pos = nearpos(me.core.pos)
    right.core.pos = nearpos(me.core.pos)
    send(service, me, me.left, SetSibling(me.right))
    send(service, me, me.right, SetSibling(me.left))
    empty!(me.values)
end

function Circo.onmessage(me::TreeNode, message::Add, service)
    me.size += 1
    if isnothing(me.splitvalue)
        push!(me.values, message.value)
        if length(me.values) > ITEMS_PER_LEAF
            split(me, service)
        end
    else
        if message.value > me.splitvalue
            send(service, me, me.right, message)
        else
            send(service, me, me.left, message)
        end
    end
end

function Circo.onmessage(me::TreeNode, message::RecipientMoved, service) # TODO a default implementation like this
    oldbox = box(message.oldaddress)
    if !isnothing(me.left) && box(me.left) === oldbox
        me.left = message.newaddress
    elseif !isnothing(me.right) && box(me.right) === oldbox
        me.right = message.newaddress
    elseif !isnothing(me.sibling) && box(me.sibling) == oldbox
        me.sibling = message.newaddress
    end
    send(service, me, message.newaddress, message.originalmessage)
end

function Circo.onmessage(me::TreeNode, message::Search, service)
    if isnothing(me.splitvalue)
        if message.value in me.values
            send(service, me, message.searcher, SearchResult(message.value, true))
        else
            send(service, me, message.searcher, SearchResult(message.value, false))
        end
    else
        child = message.value > me.splitvalue ? me.right : me.left
        send(service, me, child, message)
    end
    if SIBLINGINFO_FREQ > 0 && !isnothing(me.sibling) && rand(UInt8) < SIBLINGINFO_FREQ
        send(service, me, me.sibling, SiblingInfo(me.size), SIBLINGINFO_ENERGY) # To push the sibling away
    end
end

function Circo.onmessage(me::TreeNode, message::SetSibling, service)
    me.sibling = message.value
end

# No need to handle the message for the infoton to work
#function onmessage(me::TreeNode, message::SiblingInfo, service) end

end

zygote(ctx) = [SearchTreeTest.Coordinator(emptycore(ctx)) for i = 1:1]
plugins(;options...) = [Debug.MsgStats(;options...)]
profile(;options...) = Circo.Profiles.ClusterProfile(;options...)
