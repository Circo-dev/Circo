module LeadGroupTest
using Test
using Circo

# SPDX-License-Identifier: MPL-2.0
using Test
using Circo, Circo.DistributedIdentities, Circo.LeadGroup

mutable struct LeadGroupTestPeer <: LeadGroupPeer{Any}
    arr::Vector{Float64}
    eventdispatcher::Addr
    @distid_field
    @leadgroup_field
    core
    LeadGroupTestPeer() = new([])
end
Circo.traits(::Type{LeadGroupTestPeer}) = (EventSource,)

electedpeers = LeadGroupTestPeer[]

LeadGroup.onelected(me::LeadGroupPeer, service) = begin
    push!(electedpeers, me)
end

@testset "LeadGroup basics" begin
    ctx = CircoContext(target_module=@__MODULE__,
                         profile=Circo.Profiles.ClusterProfile(),
                         userpluginsfn=(;_...)->[DistIdService])
    tester = LeadGroupTestPeer()
    sdl = Scheduler(ctx, [tester])
    sdl(;remote=false)
    @test length(electedpeers) > 0
end

end # module
