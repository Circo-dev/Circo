module LangTest

using Test
using Circo

@actor struct Orchestrator
    tester::Addr
    Orchestrator() = new()
end

@actor struct LangTester
    created::Bool
    got::Array{Any}
    becamed::Bool
    LangTester() = new(false, [], false)
    LangTester(created, got, becamed) = new(created, got, becamed)
end

struct TestMsg
    value
end

@onspawn Orchestrator begin
    testeractor = LangTester()
    me.tester = @spawn testeractor
    @test testeractor.created == true

    @send TestMsg(:start) => me.tester
    @die
end

@onspawn LangTester begin
    @test me.created == false
    me.created = true
end

@onmessage TestMsg => LangTester begin
    push!(me.got, msg.value)
    if msg.value == :start
        @test me.becamed == false
        @become LangTester(me.created, me.got, true)
        @send TestMsg(:exit) => me
    elseif msg.value == :exit
        @test me.becamed == true
        @test me.got == [:start, :exit]
        @die
    end
end

@testset "Language" begin
    orchestrator = Orchestrator()
    ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [])
    scheduler = Scheduler(ctx, [orchestrator])
    scheduler(;remote=false)
    Circo.shutdown!(scheduler)
end

end # module
