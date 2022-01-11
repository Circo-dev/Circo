# SPDX-License-Identifier: MPL-2.0
module IdRegistryTest

using Test
using Circo, Circo.CircoCore, Circo.DistributedIdentities, Circo.Debug, Circo.DistributedIdentities.Reference
using Circo.IdRegistry

include("../helper/testactors.jl");
import .TestActors: Puppet, msgcount, msgs

mutable struct DistIdForRegistryTest <: Actor{Any}
    @distid_field
    eventdispatcher
    core
    DistIdForRegistryTest() = new()
    DistIdForRegistryTest(distid) = new(distid)
end
DistributedIdentities.identity_style(::Type{DistIdForRegistryTest}) = DenseDistributedIdentity()

const IDREG_TEST_KEY = "key.sub"

@testset "Identity Registry" begin
    ctx = CircoContext(target_module=@__MODULE__, profile=Circo.Profiles.ClusterProfile())
    distid_root = DistIdForRegistryTest()
    tester = Puppet()
    sdl = Scheduler(ctx, [distid_root, tester])
    sdl(;exit=true, remote=false)

    # Register
    registry = getname(sdl.service, IdRegistry.REGISTRY_NAME)
    @test !isnothing(registry)
    send(tester, registry, RegisterIdentity(addr(tester), IDREG_TEST_KEY, ReferencePeer(distid_root, emptycore(sdl))))
    sdl(;exit=true, remote=false)
    @test msgcount(tester, IdentityRegistered) == 1
    @test msgcount(tester, AlreadyRegistered) == 0

    # AlreadyRegistered when registering the same key again
    send(tester, registry, RegisterIdentity(addr(tester), IDREG_TEST_KEY, ReferencePeer(distid_root, emptycore(sdl))))
    sdl(;exit=true, remote=false)
    @test msgcount(tester, IdentityRegistered) == 1
    @test msgcount(tester, AlreadyRegistered) == 1

    # Registry request
    send(tester, registry, RegistryQuery(addr(tester), IDREG_TEST_KEY))
    sdl(;exit=true, remote=false)
    @test msgcount(tester, RegistryResponse) == 1
    @show msgs(tester, RegistryResponse)
    ref = msgs(tester, RegistryResponse)[1].ref
    @test ref isa ReferencePeer
    @test ref.id == distid(distid_root)

    # TODO test that early registry requests get postponed and served correctly
end

end # module
