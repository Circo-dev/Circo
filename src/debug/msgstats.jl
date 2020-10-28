using Circo
using LinearAlgebra

mutable struct MsgStats <: Plugin
    typefrequencies::IdDict{Type, Int}
    helper::Actor
    MsgStats(;options...) = new(IdDict())
end

Circo.symbol(::MsgStats) = :msgstats

mutable struct MsgStatsHelper <: Actor{Any}
    stats::MsgStats
    core
    MsgStatsHelper(stats) = new(stats)
end

struct ResetStats
    a::UInt8
    ResetStats(a) = new(a)
    ResetStats() = new(42)
end
registermsg(ResetStats, ui=true)

Circo.monitorextra(actor::MsgStatsHelper) = (
    (; (Symbol(k) => v for (k,v) in actor.stats.typefrequencies)...)
)

Circo.monitorprojection(::Type{MsgStatsHelper}) = JS("{
    geometry: new THREE.BoxBufferGeometry(10, 10, 10)
}")

Circo.schedule_start(stats::MsgStats, scheduler) = begin
    stats.helper = MsgStatsHelper(stats)
    spawn(scheduler, stats.helper)
    stats.helper.core.pos = pos(scheduler) == nullpos ? nullpos : pos(scheduler) - (pos(scheduler) * (1 / norm(pos(scheduler))) * 15.0)
end

@inline function Circo.localdelivery(stats::MsgStats, scheduler, msg::Circo.AbstractMsg{T}, targetactor) where T
    current = get(stats.typefrequencies, T, nothing)
    if isnothing(current)
        stats.typefrequencies[T] = 1
        return false
    end
    stats.typefrequencies[T] = current + 1
    return false
end

Circo.onmessage(me::MsgStatsHelper, msg::ResetStats, service) = begin
    empty!(me.stats.typefrequencies)
end

# function Base.show(io::IO, stats::MsgStats)
#     Base.show(io, stats.typefrequencies)
# end
