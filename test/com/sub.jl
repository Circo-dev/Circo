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
            <sub-tester name="t2" subto="../t1/"></sub-tester>
            <sub-tester name="t3" subto="..">
                <sub-tester name="t31" subto="../.."></sub-tester>
                <sub-tester name="t32" subto="../t31"></sub-tester>
            </sub-tester>
        </sub-tester>
    """)
    root = instantiate(prog)

    sdl = Scheduler(CircoContext(target_module=@__MODULE__))
    vitalize(prog, sdl)
    sdl(;exit=true, remote=false)
    send(sdl, root, Fire(TestEvent(1)))
    sdl(;exit=true, remote=false)
    @test length(eventlog) == 3
    @test eventlog[1] == (TestEvent(1), prog.childnodes[1].instance)
    @test eventlog[2] == (TestEvent(1), prog.childnodes[3].instance)
    @test eventlog[3] == (TestEvent(1), prog.childnodes[3].childnodes[1].instance)
end

end # module
