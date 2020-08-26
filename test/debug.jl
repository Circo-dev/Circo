module DebugTest

using Test
using Circo

const SAMPLE_COUNT = 1000

mutable struct StatsTester <: AbstractActor
    core::CoreState
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

@testset "Debug" begin
    tester = StatsTester()
    stats = Debug.MsgStats()
    scheduler = ActorScheduler([tester];plugins=[stats, CircoCore.core_plugins()...])
    scheduler(Msg(tester, addr(tester), Start()))
    @show stats
    @test stats.typefrequencies[Ack] == SAMPLE_COUNT #scheduler.plugins[:msgstats]
end

end
