using Circo
using LinearAlgebra

mutable struct MsgStats <: Plugin
    typefrequencies::IdDict{Type, Int}
    total_count::Int
    local_count::Int
    helper::Actor
    MsgStats(;options...) = new(IdDict(), 0, 0)
end

Circo.symbol(::MsgStats) = :msgstats

mutable struct MsgStatsHelper <: Actor{Any}
    stats::MsgStats
    fixedpos
    core
    MsgStatsHelper(stats) = new(stats)
end

struct ResetStats
    a::UInt8
    ResetStats(a) = new(a)
    ResetStats() = new(42)
end
registermsg(ResetStats, ui=true)

function Circo.monitorextra(me::MsgStatsHelper)
    me.core.pos = me.fixedpos
    return (
        total_count = me.stats.total_count,
        local_rate = me.stats.local_count / me.stats.total_count,
        (Symbol(k) => v for (k,v) in me.stats.typefrequencies)...
    )
end

Circo.monitorprojection(::Type{MsgStatsHelper}) = JS("{
    geometry: new THREE.BoxBufferGeometry(10, 10, 10)
}")

Circo.schedule_start(stats::MsgStats, scheduler) = begin
    stats.helper = MsgStatsHelper(stats)
    spawn(scheduler, stats.helper)
    stats.helper.fixedpos = pos(scheduler) == nullpos ? nullpos : pos(scheduler) - (pos(scheduler) * (1 / norm(pos(scheduler))) * 15.0)
    stats.helper.core.pos = stats.helper.fixedpos
end

@inline function Circo.localdelivery(stats::MsgStats, scheduler, msg::Circo.AbstractMsg{T}, targetactor) where T
    stats.typefrequencies[T] = get!(stats.typefrequencies, T, 0) + 1
    stats.total_count += 1
    if postcode(msg.sender) == postcode(msg.target)
        stats.local_count += 1
    end
    return false
end

Circo.onmessage(me::MsgStatsHelper, msg::ResetStats, service) = begin
    empty!(me.stats.typefrequencies)
    me.stats.local_count = 0
    me.stats.total_count = 0
    me.core.pos = me.fixedpos
end

# function Base.show(io::IO, stats::MsgStats)
#     Base.show(io, stats.typefrequencies)
# end
