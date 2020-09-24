using Circo
using LinearAlgebra

mutable struct MsgStats <: Plugin
    typefrequencies::IdDict{Any, Int}
    helper::AbstractActor
    MsgStats(;options...) = begin
        return new(IdDict())
    end
end

mutable struct MsgStatsHelper{TCore} <: AbstractActor{TCore}
    stats::MsgStats
    core::TCore
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

Circo.symbol(::MsgStats) = :msgstats

Circo.setup!(stats::MsgStats, scheduler) = begin
    stats.helper = MsgStatsHelper(stats, emptycore(scheduler.service))
    spawn(scheduler, stats.helper)
end

Circo.schedule_start(stats::MsgStats, scheduler) = begin
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
