# SPDX-License-Identifier: MPL-2.0
using Test
using Circo, Circo.DistributedIdentities, Circo.Transactions

mutable struct SPCTester <: Actor{Any}
    arr::Vector{Float64}
    eventdispatcher
    @distid_field
    core
    SPCTester() = new([])
end
DistributedIdentities.identity_style(::Type{SPCTester}) = DenseDistributedIdentity()
Transactions.consistency_style(::Type{SPCTester}) = Inconsistency()

@testset "Single Phase Commit" begin
    ctx = CircoContext(;profile=Circo.Profiles.ClusterProfile(),userpluginsfn=(;_...)->[DistIdService])
    tester = SPCTester()
    sdl = Scheduler(ctx, [tester])
    sdl(;exit=true, remote=false)
    commit!(tester, Write(:arr, 1, 42), sdl.service)
    sdl(;exit=true, remote=false)
    @test tester.arr[1] == 42
    testers = filter(a -> a isa SPCTester, collect(values(sdl.actorcache)))
    @test length(testers) > 2
end

