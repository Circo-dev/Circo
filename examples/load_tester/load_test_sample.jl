using Circo, HTTP
include("load_tester.jl");  using .LoadTester

const BASE_URL = "http://stage.stereotic.com:8000/"

mutable struct User1{TCore} <: TaskedWorker{TCore}
    manager::Addr
    case::TestCase
    id::Int
    migration_target::Union{PostCode, Nothing}
    core::TCore
    User1{T}(manager, case, id, core) where T = new{T}(manager, case, id, nothing, core)
end

struct SampleTask1 end
struct SampleTask2 end

LoadTester.tasks(me::User1) = [SampleTask1(), SampleTask2()]

function Circo.onmessage(me::User1, task::SampleTask1, service)
    @async begin
        try
            HTTP.request("GET", BASE_URL; connection_limit = 30)
            sleep(0.2)
            HTTP.request("GET", "$(BASE_URL)apps/screener/index.html"; connection_limit = 30)
            sleep(0.1)
        catch e
            @info "$e"
        end
        try
            send(service, me, me.manager, TaskDone(task, me.id); energy=0.02)
            if !isnothing(me.migration_target)
                Circo.Migration.migrate(service, me, me.migration_target)
                me.migration_target = nothing
            end
        catch e
            @info "$e"
        end
    end
end

function Circo.onmessage(me::User1, task::SampleTask2, service)
    @async begin
        try
            HTTP.request("GET", "$(BASE_URL)data/history/bitcoin/chart1.json"; connection_limit = 30)
        catch e
            @info "$e"
        end
        send(service, me, me.manager, TaskDone(task, me.id); energy=0.02)
        if !isnothing(me.migration_target)
            migrate(service, me, me.migration_target)
            me.migration_target = nothing
        end
    end
end

zygote(ctx) = [LoadTester.TestSuite([TestCase(User1, 200),TestCase(User1, 100),TestCase(User1, 100),TestCase(User1, 100), TestCase(User1, 50), TestCase(User1, 10)])]
plugins(;options...) = [Debug.MsgStats]
profile(;options...) = Circo.Profiles.ClusterProfile(;options...)
