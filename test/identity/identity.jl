# SPDX-License-Identifier: MPL-2.0
using Test
using CircoCore, Circo, Circo.DistributedIdentity, Circo.Debug

# @testset "Distributed Identity" begin
#     root = DistId(42; target_size = 5)
#     ctx = CircoContext()
#     scheduler = Scheduler(ctx, [root])
#     scheduler(;exit=true)
#     #Circo.shutdown!(scheduler)
#     @test length(root.peers) == 5
# end

macro t()
    return quote
        global root = DistId(42; target_size = 15)
        global ctx = CircoContext(;profile=Circo.Profiles.ClusterProfile(),userpluginsfn=(;_...)->[Debug.MsgStats])
        global sdl = Scheduler(ctx, [root])
        global sdltask = @async sdl(;exit=true)
        @async begin
            error_reported = false
            sleep(4.0)
            while sdl.state != CircoCore.stopped
                sleep(max(1.0 + randn(), 0.1))
                idactors = filter(a -> a isa DistId, collect(values(sdl.actorcache)))
                if isempty(idactors)
                    !error_reported && @error "Identity is dead!"
                    error_reported = true
                    continue
                end
                error_reported = false
                actor = rand(idactors)
                @info "Killing a random actor: $(addr(actor))"
                send(sdl, actor, Circo.DistributedIdentity.Die())
            end
            @info "Killer exiting"
        end
    end
end