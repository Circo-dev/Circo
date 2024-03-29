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

ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [Debug.MsgStats])

@testset "Debug" begin
    tester = StatsTester()
    scheduler = Scheduler(ctx, [tester])
    stats = scheduler.plugins[:msgstats]
    scheduler(;remote = false) # to spawn the zygote
    send(scheduler, addr(tester), Start())
    scheduler(;remote = false)
    @show stats
    @test stats.typefrequencies[Ack] == SAMPLE_COUNT
end

end
