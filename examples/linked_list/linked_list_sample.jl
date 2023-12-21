# SPDX-License-Identifier: MPL-2.0

# This Circo sample creates a linked list of actors holding float values,
# and calculates the sum of them over and over again.
# It demonstrates Infoton optimization, Circo's novel approach to solve the
# data locality problem

include("linked_list.jl")

#include("../utils/loggerconfig.jl")

module LinkedListSample

const LIST_LENGTH = 1000
const PARALLELISM = 200 # Number of parallel Reduce operations (firstly started in a single batch, but later they smooth out)

const SCHEDULER_TARGET_ACTORCOUNT = 180.0 # Schedulers will push away their actors if they have more than this
const AUTO_START = false


using Circo, Circo.Debug, Circo.Monitor, Circo.Migration, Circo.InfotonOpt, Dates, Random, LinearAlgebra

# Test coordinator: Creates the list and sends the reduce operations to it to calculate the sum
mutable struct Coordinator{TCore} <: Actor{TCore}
  itemcount::Int
  runidx::Int
  isrunning::Bool
  avgreducetime::Float64
  lastreducets::UInt64
  list::Addr
  core::TCore
  Coordinator(core) = new{typeof(core)}(0, 0, false, 0.0, 0, Addr(), core)
end

boxof(addr) = !isnothing(addr) ? addr.box : nothing # Helper

# Implement Circo.monitorextra() to publish part of an actor's state
Circo.monitorextra(me::Coordinator)  = (
    itemcount = me.itemcount,
    avgreducetime = me.avgreducetime,
    list = boxof(me.list)
)
Circo.monitorprojection(::Type{<:Coordinator}) = JS("{
    geometry: new THREE.SphereBufferGeometry(25, 7, 7),
    color: 0xcb3c33
}")


@inline @fastmath function Circo.InfotonOpt.scheduler_infoton(scheduler, actor::Actor)
    energy = (SCHEDULER_TARGET_ACTORCOUNT - scheduler.actorcount) * 4e-2
    return Infoton(scheduler.pos, energy)
end

@inline Circo.Migration.check_migration(me::Coordinator, alternatives::MigrationAlternatives, service) = begin
    migrate_to_nearest(me, alternatives, service, 0.01)
end

end