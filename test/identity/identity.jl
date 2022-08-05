# SPDX-License-Identifier: MPL-2.0
using Test
using Circo, Circo.CircoCore, Circo.DistributedIdentities, Circo.Debug

mutable struct DistIdTester <: Actor{Any}
    @distid_field
    eventdispatcher::Addr
    core
    DistIdTester() = new()
    DistIdTester(distid) = new(distid)
end
Circo.traits(::Type{DistIdTester}) = (EventSource,)
DistributedIdentities.identity_style(::Type{DistIdTester}) = DenseDistributedIdentity()


# @testset "Distributed Identity" begin
#     root = DistributedIdentity(42; target_size = 5)
#     ctx = CircoContext(target_module=@__MODULE__)
#     scheduler = Scheduler(ctx, [root])
#     scheduler(;)
#     #Circo.shutdown!(scheduler)
#     @test length(root.peers) == 5
# end

macro t()
    return quote
        global root = DistIdTester() # DistributedIdentity.DistributedIdentity(42; redundancy = 15)
        global ctx = CircoContext(target_module=@__MODULE__, profile=Circo.Profiles.ClusterProfile(),userpluginsfn=(;_...)->[Debug.MsgStats, DistIdService])
        global sdl = Scheduler(ctx, [root])
        global sdltask = @async sdl(;)
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
