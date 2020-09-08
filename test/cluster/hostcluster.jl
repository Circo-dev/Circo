module HostClusterTest

using Test, Printf
using Circo
import Circo:onschedule, onmessage, onmigrate

const CLUSTER_SIZE = 30

@testset "HostCluster" begin
    @testset "Host cluster with internal root" begin
        host = Host(CLUSTER_SIZE;profile=Circo.Profiles.ClusterProfile())
        hosttask = @async host()
        sleep(CLUSTER_SIZE * 0.2 + 9.0)
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
