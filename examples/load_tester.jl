# SPDX-License-Identifier: MPL-2.0

module LoadTester

export TestCase, Worker, TaskedWorker, TaskDone

using Circo

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

function Circo.onspawn(me::TestSuite, service)
    @info "$me scheduled and starting."
    for case in me.cases
        push!(me.runs, spawn(service, TestCaseRun(case)))
    end
end

function Circo.onspawn(me::TestCaseRun, service)
    @info "$me starting."
    for i=1:me.case.count
        bhv = me.case.behavior
        constructor = bhv isa UnionAll ? bhv{CircoCore.coretype(me)} : bhv
        push!(me.workers, spawn(service, constructor(addr(me), me.case, i, emptycore(service))))
    end
    @info "$(me.case.count) worker started."
end

function Circo.onmessage(me::TestCaseRun, msg::TaskDone, service)
    if me.running
        send(service, me, me.workers[msg.worker_id], StartATask())
    end
end

abstract type TaskedWorker{TCore} <: Worker{TCore} end

function Circo.onspawn(me::TaskedWorker, service)
    start_a_task(me, service)
end

function start_a_task(me::TaskedWorker, service)
    task = select_task(me)
    isnothing(task) && return nothing
    send(service, me, addr(me), task)
end

function select_task(me::TaskedWorker)
    return nothing
end

function Circo.onmessage(me::TaskedWorker, msg::StartATask, service)
    start_a_task(me, service)
end

end # module

using Circo, .LoadTester, HTTP

mutable struct HttpWorker{TCore} <: TaskedWorker{TCore}
    manager::Addr
    case::TestCase
    id::Int
    core::TCore
end

struct SampleTask end

function LoadTester.select_task(me::HttpWorker)
    return SampleTask()
end

function Circo.onmessage(me::HttpWorker, task::SampleTask, service)
    @async begin
        HTTP.request("GET", "http://localhost:8080/api")
        send(service, me, me.manager, TaskDone(task, me.id))
    end
end

zygote(ctx) = LoadTester.TestSuite([TestCase(HttpWorker, 1_000)])
