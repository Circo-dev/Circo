# SPDX-License-Identifier: MPL-2.0
using Test
using CircoCore, Circo, Circo.DistributedIdentities, Circo.Debug
using Circo.IdRegistry

mutable struct DistIdForRegistryTest <: Actor{Any}
    @distid_field
    eventdispatcher
    core
    DistIdForRegistryTest() = new()
    DistIdForRegistryTest(distid) = new(distid)
end
DistributedIdentities.identity_style(::Type{DistIdForRegistryTest}) = DenseDistributedIdentity()

mutable struct RegistryTester <: Actor{Any}
    gotregistered_count::Int
    got_already_count::Int
    core
    RegistryTester() = new(0, 0)
end

Circo.onmessage(me::RegistryTester, msg::IdentityRegistered, service) = me.gotregistered_count += 1
Circo.onmessage(me::RegistryTester, msg::AlreadyRegistered, service) = me.got_already_count += 1

@testset "Identity Registry" begin
    ctx = CircoContext(;profile=Circo.Profiles.ClusterProfile())
    distid_root = DistIdForRegistryTest()
    tester = RegistryTester()
    sdl = Scheduler(ctx, [distid_root, tester])
    sdl(;exit=true, remote=false)

    # Register
    @show registry = getname(sdl.service, IdRegistry.REGISTRY_NAME)
    send(sdl, registry, RegisterIdentity(addr(tester), "key.sub", distid(distid_root), peers(distid_root)))
    sdl(;exit=true, remote=false)
    @test tester.gotregistered_count == 1
    @test tester.got_already_count == 0

    # AlreadyRegistered when registering the same key again
    send(sdl, registry, RegisterIdentity(addr(tester), "key.sub", distid(distid_root), peers(distid_root)))
    sdl(;exit=true, remote=false)
    @test tester.gotregistered_count == 1
    @test tester.got_already_count == 1
end