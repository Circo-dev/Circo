# SPDX-License-Identifier: MPL-2.0
using Test
using Circo, Circo.Migration, Circo.Cluster
import Circo:onmessage

function Circo.Migration.onmigrate(me::Main.Migrant, service)
    @debug "Successfully migrated to $me"
    send(service, me, me.stayeraddress, Main.MigrateDone(addr(me)))
end

function onmessage(me::Main.Migrant, message::Main.SimpleRequest, service)
    send(service, me, message.responseto, Main.SimpleResponse())
end

function onmessage(me::Main.Migrant, message::Main.Results, service)
    die(service, me; exit=true)
end

function onmessage(me::Main.ResultsHolder, message::Main.Results, service)
    println("Got results $message")
    me.results = message
    die(service, me; exit=true)
end

function startsource(targetpostcode, resultsholder_address)
    source = "try cd(\"test\") catch e end;include(\"migrate/migrate-source.jl\");migratetoremote(\"$targetpostcode\", \"$resultsholder_address\")"
    println(source)
    run(pipeline(Cmd(["julia", "--project", "-e", source]);stdout=stdout,stderr=stderr);wait=false)
end

@testset "Migration" begin
    resultsholder = Main.ResultsHolder()
    ctx = CircoContext(userpluginsfn = () -> [MigrationService, ClusterService])
    scheduler = Scheduler(ctx, [resultsholder])
    scheduler(;remote=false) # to spawn the zygote
    startsource(postcode(scheduler),addr(resultsholder))
    scheduler(;remote=true)
    println("Resultsholder Exited")
    Circo.shutdown!(scheduler)
    stayer = resultsholder.results.stayer
    @test stayer.responsereceived == 1
    @test isdefined(stayer, :newaddress_recepientmoved)
    @test stayer.newaddress_recepientmoved == stayer.newaddress_selfreport
end
