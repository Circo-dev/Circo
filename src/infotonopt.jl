module InfotonOpt

using ..Circo, ..Circo.Cluster, Circo.Monitor
using Plugins
using LinearAlgebra

export Infoton

const I = 1.0
const TARGET_DISTANCE = 8.0

"""
    Infoton(sourcepos::Pos, energy::Real = 1)

Create an Infoton that carries `abs(energy)` amount of energy and has the sign `sign(energy)`.

The infoton mediates the force that awakens between communicating actors. When arriving at its
target actor, the infoton pulls/pushes the actor toward/away from its source, depending on its
sign (positive pulls).

The exact details of how the Infoton should act at its target is actively researched.
Please check or overload [`apply_infoton`](@ref).
"""
struct Infoton
    sourcepos::Pos
    energy::Float32
    Infoton(sourcepos::Pos, energy::Real = 1.0f0) = new(sourcepos, Float32(energy))
end
Infoton() = Infoton(nullpos, 0.0f0)

abstract type Optimizer <: Plugin end
mutable struct OptimizerImpl <: Optimizer
    OptimizerImpl(;options...) = new()
end

__init__() = Plugins.register(OptimizerImpl)

abstract type CustomOptimizer <: Optimizer end # for user-defined optimizers

infotoninit() = Infoton()
infotoninit(sender::Actor, target, body, scheduler; energy = 1.0f0) = begin
    return Infoton(pos(sender), energy)
end
infotoninit(sender::Addr, target, body, scheduler; energy = 1.0f0) = Infoton() # Sourcepos not known, better to use zero energy

Plugins.customfield(::Optimizer, ::Type{AbstractMsg}) = Plugins.FieldSpec("infoton", Infoton, infotoninit)

@inline Circo.localdelivery(optimizer::Optimizer, scheduler, msg, targetactor) = begin
    apply_infoton(optimizer, targetactor, msg.infoton)
    apply_infoton(optimizer, targetactor, scheduler_infoton(optimizer, scheduler, targetactor)) # TODO: SparseActivity?
    return false
end

"""
    apply_infoton(optimizer::Optimizer, targetactor::Actor, infoton::Infoton)

An infoton acting on an actor.

Please check the source and the examples for more info.
"""
@inline @fastmath function apply_infoton(optimizer::Optimizer, targetactor::Actor, infoton::Infoton)
    diff = infoton.sourcepos - targetactor.core.pos
    difflen = norm(diff)
    energy = infoton.energy
    if energy > 0 && difflen < TARGET_DISTANCE #|| energy < 0 && difflen > TARGET_DISTANCE / 2
        return nothing
        energy = -energy
    end
    targetactor.core.pos += diff / difflen * energy * I
    return nothing
end

@inline @fastmath function scheduler_infoton(optimizer::Optimizer, scheduler, actor::Actor)
    diff = scheduler.pos - actor.core.pos
    distfromtarget = 2000 - norm(diff) # TODO configuration +easy redefinition from applications (including turning it off completely?)
    energy = sign(distfromtarget) * distfromtarget * distfromtarget * -2e-6
    return Infoton(scheduler.pos, energy)
end

end # module
