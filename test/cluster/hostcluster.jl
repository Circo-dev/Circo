module HostClusterTest

using Test, Printf
using Circo
import Circo:onspawn, onmessage, onmigrate

const CLUSTER_SIZE = 30

ctx = CircoContext(;profile=Circo.Profiles.ClusterProfile())

@testset "HostCluster" begin
    @testset "Host cluster with internal root" begin
        host = Host(ctx, CLUSTER_SIZE)
        hosttask = @async host()
        sleep(CLUSTER_SIZE * 0.1 + 9.0)
        for i in 1:CLUSTER_SIZE
            scheduler = host.schedulers[i]
            helperaddr = scheduler.plugins[:cluster].helper
            helperactor = getactorbyid(scheduler, box(helperaddr))
            @test length(helperactor.peers) == CLUSTER_SIZE
        end
        shutdown!(host)
    end
end
end
