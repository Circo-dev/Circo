# SPDX-License-Identifier: MPL-2.0
using Test
using Circo, Circo.CircoCore, Circo.DistributedIdentities, Circo.DistributedIdentities.Reference

const REQ_COUNT = 5

mutable struct DistIdForRefTest <: Actor{Any}
    @distid_field
    eventdispatcher::Addr
    core
    DistIdForRefTest() = new()
    DistIdForRefTest(distid) = new(distid)
end
Circo.traits(::Type{DistIdForRefTest}) = (EventSource,)
DistributedIdentities.identity_style(::Type{DistIdForRefTest}) = DenseDistributedIdentity()

struct TestReq
    id::Int
    respondto::Addr
end

struct TestResp
    id::Int
    from::Addr
end

Circo.onmessage(me::DistIdForRefTest, msg::TestReq, service) = begin
    send(service, me, msg.respondto, TestResp(msg.id, addr(me)))
end

mutable struct ReferenceTester <: Actor{Any} # TODO <: Puppet
    refaddr::Addr
    responses_from::Vector{Addr}
    core
    ReferenceTester(refaddr) = new(refaddr, [])
end

Circo.onmessage(me::ReferenceTester, ::OnSpawn, service) = begin
    resize!(me.responses_from, REQ_COUNT)
    for i=1:REQ_COUNT
        send(service, me, me.refaddr, TestReq(i, addr(me)))
    end
end

Circo.onmessage(me::ReferenceTester, msg::TestResp, service) = begin
    me.responses_from[msg.id] = msg.from
end

@testset "DistId references" begin
    ctx = CircoContext(target_module=@__MODULE__, profile=Circo.Profiles.ClusterProfile())
    testid_root = DistIdForRefTest(DistributedIdentity(42; redundancy = 3))
    sdl = Scheduler(ctx, [testid_root])
    sdl(;remote=false)
    
    testref = IdRef(testid_root, emptycore(ctx))
    spawn(sdl, testref)
    sdl(;remote=false)

    tester = ReferenceTester(addr(testref))
    spawn(sdl, tester)
    sdl(;remote=false)
    @test count(a -> a isa Addr, tester.responses_from) == REQ_COUNT

    @async sdl(;remote=true)
    sleep(20)

    for i = 1:10
        tokill = rand(keys(testid_root.distid.peers))
        @info "Killing $tokill"
        send(sdl, tokill, Circo.DistributedIdentities.Die())
        sleep(12)
        @show testref
        tester = ReferenceTester(addr(testref))
        spawn(sdl, tester)
        sleep(2)
        @test count(a -> a isa Addr, tester.responses_from) == REQ_COUNT
    end

    shutdown!(sdl)
end
