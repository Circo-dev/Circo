module SubTest
using Test
using Circo, Circo.COM

struct TestEvent <: Event
    value
end

mutable struct SubTester <: Actor{Any}
    eventdispatcher
    children
    attrs
    core
    SubTester() = new()
end
define("sub-tester", SubTester)

Circo.onspawn(me::SubTester, srv) = begin
    me.eventdispatcher = spawn(srv, EventDispatcher(emptycore(srv)))
end

Circo.COM.onvitalize(me::SubTester, srv) = begin
    if haskey(me.attrs, "subto")
        sub(srv, me, me.attrs["subto"], TestEvent)
    end
end

const eventlog = []

Circo.onmessage(me::SubTester, msg::TestEvent, srv) = begin
    push!(eventlog, (msg, me))
end

struct Fire
    event
end

Circo.onmessage(me::Actor, msg::Fire, srv) = begin
    fire(srv, me, msg.event)    
end

@testset "sub basics" begin
    prog = fromasml("""
        <sub-tester name="root">
            <sub-tester name="t1" subto="../"></sub-tester>
            <sub-tester name="t2" subto="../t3/"></sub-tester>
            <sub-tester name="t3" subto="..">
                <sub-tester name="t31" subto="../.."></sub-tester>
                <sub-tester name="t32" subto="../t31"></sub-tester>
                <sub-tester name="t33" subto="[parent]"></sub-tester>
                <sub-tester name="t34" subto="[parent]/[parent]"></sub-tester>
            </sub-tester>
        </sub-tester>
    """)
    root = instantiate(prog)

    sdl = Scheduler(CircoContext(target_module=@__MODULE__))
    vitalize(prog, sdl)
    sdl(;exit=true, remote=false)
    send(sdl, root, Fire(TestEvent(1)))
    sdl(;exit=true, remote=false)
    @test length(eventlog) == 4
    @test eventlog[1] == (TestEvent(1), prog.childnodes[1].instance)
    @test eventlog[2] == (TestEvent(1), prog.childnodes[3].instance)
    @test eventlog[3] == (TestEvent(1), prog.childnodes[3].childnodes[1].instance)
    @test eventlog[4] == (TestEvent(1), prog.childnodes[3].childnodes[4].instance)

    send(sdl, prog.childnodes[3].instance, Fire(TestEvent(2)))
    sdl(;exit=true, remote=false)
    @test length(eventlog) == 6
    @test eventlog[5] == (TestEvent(2), prog.childnodes[3].childnodes[3].instance)
    @test eventlog[6] == (TestEvent(2), prog.childnodes[2].instance)
end

end # module
