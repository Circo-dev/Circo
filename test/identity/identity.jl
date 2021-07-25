# SPDX-License-Identifier: MPL-2.0
using Test
using CircoCore, Circo, Circo.DistributedIdentities, Circo.Debug

mutable struct DistIdTester <: Actor{Any}
    @distid_field
    eventdispatcher
    core
    DistIdTester() = new()
    DistIdTester(distid) = new(distid)
end
DistributedIdentities.identity_style(::Type{DistIdTester}) = DenseDistributedIdentity()


# @testset "Distributed Identity" begin
#     root = DistributedIdentity(42; target_size = 5)
#     ctx = CircoContext()
#     scheduler = Scheduler(ctx, [root])
#     scheduler(;exit=true)
#     #Circo.shutdown!(scheduler)
#     @test length(root.peers) == 5
# end

macro t()
    return quote
        global root = DistIdTester() # DistributedIdentity.DistributedIdentity(42; redundancy = 15)
        global ctx = CircoContext(;profile=Circo.Profiles.ClusterProfile(),userpluginsfn=(;_...)->[Debug.MsgStats, DistIdService])
        global sdl = Scheduler(ctx, [root])
        global sdltask = @async sdl(;exit=true)
        @async begin
            try
                error_reported = false
                #sleep(3.0)
                while sdl.state != CircoCore.stopped
                    sleep(max(11.0, 0.1))
                    idactors = filter(a -> a isa DistIdTester, collect(values(sdl.actorcache)))
                    if isempty(idactors)
                        !error_reported && @error "Identity is dead!"
                        error_reported = true
                        continue
                    end
                    error_reported = false
                    actor = rand(idactors)
                    @info "Killing a random actor: $(addr(actor))"
                    send(sdl, actor, Circo.DistributedIdentities.Die())
                end
            catch e
                @error "Exception in killer", e
            end
            @info "Killer exiting"
        end
    end
end