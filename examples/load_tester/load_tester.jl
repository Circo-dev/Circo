# SPDX-License-Identifier: MPL-2.0

module LoadTester

export TestCase, Worker, TaskedWorker, TaskDone

using Circo, Circo.Migration, Circo.InfotonOpt
using LinearAlgebra

struct TestCase
    behavior::Type{<:Actor}
    count::Int
end

"""
    abstract type Worker{TCore} <: Actor{TCore}

User-defined worker that runs work tasks and sends back `TaskDone` reports
"""
abstract type Worker{TCore} <: Actor{TCore} end

struct TaskDone
    task
    worker_id::Int
end

struct StartATask end

mutable struct TestCaseRun <: Actor{Any}
    case::TestCase
    workers::Vector{Addr}
    running::Bool
    core::Any
    TestCaseRun(case) = new(case, [], true)
end

mutable struct TestSuite <: Actor{Any}
    cases::Vector{TestCase}
    runs::Vector{Addr}
    core::Any
    TestSuite(testcases) = new(testcases, [])
end

Base.show(io::IO, me::TestSuite) = print(io, "TestSuite with test cases [" * join(me.cases, ", ") * "]")

function Circo.onmessage(me::TestSuite, ::OnSpawn, service)
    @info "$me scheduled and starting."
    for case in me.cases
        push!(me.runs, spawn(service, TestCaseRun(case)))
    end
end

function Circo.onmessage(me::TestCaseRun, ::OnSpawn, service)
    @info "$me starting."
    for i=1:me.case.count
        bhv = me.case.behavior
        constructor = bhv isa UnionAll ? bhv{CircoCore.coretype(me)} : bhv
        push!(me.workers, spawn(service, constructor(addr(me), me.case, i, emptycore(service))))
    end
    @info "Started $(me.case.count) workers."
end

function Circo.onmessage(me::TestCaseRun, msg::TaskDone, service)
    if me.running
        send(service, me, me.workers[msg.worker_id], StartATask())
    end
end

function Circo.onmessage(me::TestCaseRun, message::RecipientMoved, service)
    idx = findfirst(a -> a == message.oldaddress, me.workers)
    if !isnothing(idx)
        me.workers[idx] = message.newaddress
    end
    send(service, me, message.newaddress, message.originalmessage)
end

function Circo.onmessage(me::Worker, message::RecipientMoved, service)
    send(service, me, message.newaddress, message.originalmessage)
end

abstract type TaskedWorker{TCore} <: Worker{TCore} end

function Circo.onmessage(me::TaskedWorker, ::OnSpawn, service)
    start_a_task(me, service)
end

function start_a_task(me::TaskedWorker, service)
    task = select_task(me)
    isnothing(task) && return nothing
    send(service, me, addr(me), task)
end

function select_task(me::TaskedWorker)
    _tasks = tasks(me)
    if isnothing(_tasks) || length(_tasks) == 0
        @warn "No tasks defined for $(typeof(me))"
        return nothing
    end
    return rand(_tasks)
end

tasks(me::TaskedWorker) = []

function Circo.onmessage(me::TaskedWorker, msg::StartATask, service)
    start_a_task(me, service)
end

Circo.monitorextra(me::Worker)  = (
    mng = box(me.manager),
)

const I = .20
const TARGET_DISTANCE = 80.0
const SCHEDULER_TARGET_LOAD = 50
const SCHEDULER_LOAD_FORCE_STRENGTH = 1e-6

@inline @fastmath function InfotonOpt.scheduler_infoton(scheduler, actor::Union{TaskedWorker})
    dist = norm(scheduler.pos - actor.core.pos)
    loaddiff = Float64(SCHEDULER_TARGET_LOAD - length(scheduler.msgqueue))
    (loaddiff == 0.0 || dist == 0.0) && return Infoton(scheduler.pos, 0.0)
    energy = sign(loaddiff) * log(abs(loaddiff)) * SCHEDULER_LOAD_FORCE_STRENGTH
    !isnan(energy) || error("Scheduler infoton energy is NaN")
    return Infoton(scheduler.pos, energy)
end

@inline Circo.Migration.check_migration(me::Union{Worker,TestCaseRun}, alternatives::MigrationAlternatives, service) = begin
    nearest = Circo.Migration.find_nearest(pos(me), alternatives)
    if isnothing(nearest) return nothing end
    if box(nearest.addr) === box(addr(me)) return nothing end
    if norm(pos(me) - pos(nearest)) < (1.0 - 1e-2) * norm(pos(me) - pos(service))
        if me isa Worker
            me.migration_target = postcode(nearest)
        else
            Circo.Migration.migrate(service, me, postcode(nearest))
        end
    end
    return nothing
end

@inline @fastmath InfotonOpt.apply_infoton(space::Space, targetactor::Actor, infoton::Infoton) = begin
    diff = infoton.sourcepos - targetactor.core.pos
    difflen = norm(diff)
    difflen == 0 && return nothing
    energy = infoton.energy
    !isnan(energy) || error("Incoming infoton energy is NaN")
    if energy > 0 && difflen < TARGET_DISTANCE
        return nothing # Comment out this line to preserve (absolute) energy. This version seems to work better.
        #energy = -energy
    end
    stepvect = diff / difflen * energy * I
    all(x -> !isnan(x), stepvect) || error("stepvect $stepvect contains NaN")
    targetactor.core.pos += stepvect
    return nothing
end

end # module
