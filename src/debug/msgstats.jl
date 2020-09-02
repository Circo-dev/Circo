using Plugins
using Circo
using LinearAlgebra

mutable struct MsgStats <: Plugin
    typefrequencies::IdDict{Any, Int}
    helper::Addr
    MsgStats(;options...) = begin
        return new(IdDict())
    end
end

mutable struct MsgStatsHelper <: AbstractActor
    stats::MsgStats
    core::CoreState
    MsgStatsHelper(stats;options...) = new(stats)
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

Plugins.symbol(::MsgStats) = :msgstats

Plugins.setup!(stats::MsgStats, scheduler) = begin
    helper = MsgStatsHelper(stats)
    stats.helper = spawn(scheduler, helper)
    newpos = pos(scheduler) == nullpos ? nullpos : pos(scheduler) - (pos(scheduler) * (1 / norm(pos(scheduler))) * 15.0)
    helper.core.pos = newpos
end

@inline function Circo.localdelivery(stats::MsgStats, scheduler, msg::Circo.Msg{T}, targetactor) where T
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
