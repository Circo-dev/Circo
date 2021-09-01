module InfotonOpt

using ..Circo, ..Circo.Cluster, Circo.Monitor, Circo.Migration
using Plugins
using LinearAlgebra

export Infoton

# -  -
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
Plugins.symbol(::Optimizer) = :infoton_optimizer

abstract type CustomOptimizer <: Optimizer end # for user-defined optimizers

# - Default optimizer plugin - 

const I = 1.0
const TARGET_DISTANCE = 8.0
const LOAD_ALPHA = 1e-3
const MIGRATION_LOAD_THRESHOLD = 18

mutable struct OptimizerImpl <: Optimizer
    scheduler_load::Float32
    accepts_migrants::Bool
    migration::Migration.MigrationService
    OptimizerImpl(migration;options...) = new(0.0f1, true, migration)
end

Plugins.deps(::Type{<:Optimizer}) = [Migration.MigrationService]
__init__() = Plugins.register(OptimizerImpl)

Plugins.customfield(::Optimizer, ::Type{AbstractMsg}) = Plugins.FieldSpec("infoton", Infoton, infotoninit)
infotoninit() = Infoton()
infotoninit(sender::Actor, target, body, scheduler; energy = 1.0f0) = begin
    return Infoton(pos(sender), energy)
end
infotoninit(sender::Addr, target, body, scheduler; energy = 1.0f0) = Infoton() # Sourcepos not known, better to use zero energy

# - Measure scheduler load -

@inline CircoCore.actor_activity_sparse256(optimizer::Optimizer, scheduler, actor::Actor) = begin
    update_load!(optimizer, scheduler)
end

function update_load!(optimizer::Optimizer, scheduler)
    optimizer.scheduler_load = 
        LOAD_ALPHA * length(scheduler.msgqueue) +
        (1.0f0 - LOAD_ALPHA) * optimizer.scheduler_load
    SWITCH_TOLERANCE = 1.1f0
    if optimizer.accepts_migrants
        if optimizer.scheduler_load > MIGRATION_LOAD_THRESHOLD * SWITCH_TOLERANCE
            accepts_migrants(optimizer, false)
        end
    else 
        if optimizer.scheduler_load < MIGRATION_LOAD_THRESHOLD / SWITCH_TOLERANCE
            accepts_migrants(optimizer, true)
        end
    end
end

@inline function CircoCore.idle(optimizer::Optimizer, scheduler)
    if optimizer.scheduler_load < 1f-3
        optimizer.scheduler_load = 0.0f1
    else
        update_load!(optimizer, scheduler)
    end
end

function accepts_migrants(optimizer::Optimizer, accepts_them::Bool)
    optimizer.accepts_migrants = accepts_them
    Migration.accepts_migrants(optimizer.migration, accepts_them)
end

# - Apply Infotons -

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
