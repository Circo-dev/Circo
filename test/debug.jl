module DebugTest

using Test
using Circo

const SAMPLE_COUNT = 1000

mutable struct StatsTester <: Actor{Any}
    core
    StatsTester() = new()
end

struct Start end

struct Sample{TData}
    respondto::Addr
    data::TData
end

struct Ack end

function Circo.onmessage(me::StatsTester, msg::Start, service)
    for i = 1:SAMPLE_COUNT
        send(service, me, addr(me), Sample{Int}(addr(me), i))
    end
end

function Circo.onmessage(me::StatsTester, msg::Sample, service)
    send(service, me, addr(me), Ack())
end

ctx = CircoContext(;userpluginsfn=() -> [Debug.MsgStats])

@testset "Debug" begin
    tester = StatsTester()
    scheduler = Scheduler(ctx, [tester])
    stats = scheduler.plugins[:msgstats]
    send(scheduler, addr(tester), Start())
    scheduler(;remote = false, exit = true)
    @show stats
    @test stats.typefrequencies[Ack] == SAMPLE_COUNT
end

end
