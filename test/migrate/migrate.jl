# SPDX-License-Identifier: MPL-2.0
using Test
using Circo, Circo.Migration, Circo.Cluster
import Circo:onmessage

include("migrate-base.jl")

function Circo.onmigrate(me::Migrant, service)
    @debug "Successfully migrated to $me"
    send(service, me, me.stayeraddress, MigrateDone(addr(me)))
end

function onmessage(me::Migrant, message::SimpleRequest, service)
    send(service, me, message.responseto, SimpleResponse())
end

function onmessage(me::Migrant, message::Results, service)
    die(service, me)
end

function onmessage(me::ResultsHolder, message::Results, service)
    println("Got results $message")
    me.results = message
    die(service, me)
end

function startsource(targetpostcode, resultsholder_address)
    source = "try cd(\"test\") catch e end;include(\"migrate/migrate-source.jl\");migratetoremote(\"$targetpostcode\", \"$resultsholder_address\")"
    println(source)
    run(pipeline(Cmd(["julia", "--project", "-e", source]);stdout=stdout,stderr=stderr);wait=false)
end

@testset "Migration" begin
    resultsholder = ResultsHolder()
    ctx = CircoContext(userpluginsfn=() -> [MigrationService, ClusterService])
    scheduler = Scheduler(ctx, [resultsholder])
    startsource(postcode(scheduler),addr(resultsholder))
    scheduler(;exit=true)
    println("Resultsholder Exited")
    Circo.shutdown!(scheduler)
    stayer = resultsholder.results.stayer
    @test stayer.responsereceived == 1
    @test isdefined(stayer, :newaddress_recepientmoved)
    @test stayer.newaddress_recepientmoved == stayer.newaddress_selfreport
end
