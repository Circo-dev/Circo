# SPDX-License-Identifier: MPL-2.0
module HostTest

using Test, Printf
using Circo, Circo.Migration
import Circo:onspawn, onmessage, onmigrate

mutable struct PingPonger{TCore} <: Actor{TCore}
    peer::Union{Addr, Nothing}
    target_postcode::Union{PostCode, Nothing}
    pings_sent::Int64
    pongs_got::Int64
    core::TCore
    PingPonger(peer, core) = new{typeof(core)}(peer, nothing, 0, 0, core)
    PingPonger(peer, target_postcode, core) = new{typeof(core)}(peer, target_postcode, 0, 0, core)
end

struct Ping end
struct Pong end

struct CreatePeer
    target_postcode::Union{PostCode, Nothing}
end

function onspawn(me::PingPonger, service)
    if !isnothing(me.target_postcode)
        if isnothing(plugin(service, :migration))
            error("Migration plugin not installed")
        end
        @debug "Migrating to $(me.target_postcode)"
        migrate(service, me, me.target_postcode)
    end
end

function onmigrate(me::PingPonger, service)
    @debug "Migrated!!!"
end

function sendping(service, me::PingPonger)
    send(service, me, me.peer, Ping())
    me.pings_sent += 1
end

function sendpong(service, me::PingPonger)
    send(service, me, me.peer, Pong())
end

function onmessage(me::PingPonger, message::CreatePeer, service)
    peer = PingPonger(addr(me), message.target_postcode, emptycore(service))
    me.peer =  spawn(service, peer)
    sendping(service, me)
end

function onmessage(me::PingPonger, ::Ping, service)
    sendpong(service, me)
end

function onmessage(me::PingPonger, ::Pong, service)
    me.pongs_got += 1
    sendping(service, me)
end

function onmessage(me::PingPonger, ::Debug.Stop, service)
    send(service, me, me.peer, Debug.Stop(42))
    die(service, me)
end

function onmessage(me::PingPonger, message::RecipientMoved, service)
    @debug "Peer moved"
    if me.peer == message.oldaddress
        me.peer = message.newaddress
    else
        throw("Unknown peer in RecipientMoved")
    end
    send(service, me, me.peer, message.originalmessage)
end

ctx = CircoContext(; target_module=@__MODULE__, profile=Circo.Profiles.ClusterProfile())
@testset "Host" begin
     @testset "Empty host creation and run" begin
         host = Host(ctx, 3)
         host(;remote=false, exit=true)
         @test length(host.schedulers) == 3
         for i in 1:3
             @test length(host.schedulers[i].plugins[:host].peercache) == 2
         end
         shutdown!(host)
     end

    @testset "Inter-thread Ping-Pong inside Host" begin
        pingers = [PingPonger(nothing, emptycore(ctx)) for i=1:250]
        host = Host(ctx, 2; zygote=pingers)
        for pinger in pingers
            send(host, addr(pinger), CreatePeer(postcode(host.schedulers[end])))
        end
        hosttask = @async host()
        @info "Sleeping to allow ping-pong to start."
        sleep(30.0) # TODO use conditions
        for pinger in pingers
            @test pinger.pings_sent > 1
            @test pinger.pongs_got > 1
        end

        @info "Measuring inter-thread ping-pong performance (10 secs)"
        startpingcounts = [pinger.pings_sent for pinger in pingers]
        startts = Base.time_ns()
        sleep(10.0)
        rounds_made = sum([pingers[i].pings_sent - startpingcounts[i] for i=1:length(pingers)])
        wall_time_used = Base.time_ns() - startts
        @test pingers[1].pings_sent > 1e2
        @test pingers[1].pongs_got > 1e2
        shutdown!(host)
        sleep(0.1)
        endpingcount = pingers[1].pings_sent
        @test pingers[1].pongs_got in [pingers[1].pings_sent, pingers[1].pings_sent - 1]
        sleep(0.1)
        @test endpingcount === pingers[1].pings_sent
        @printf "Inter-thread ping-pong performance (in a max throughput setting, %d pingers): %f rounds/sec\n" length(pingers) (rounds_made / wall_time_used * 1e9)
    end

    @testset "In-thread Ping-Pong inside Host" begin
        pingers = [PingPonger(nothing, emptycore(ctx)) for i=1:1]
        host = Host(ctx, 1; zygote=pingers)
        for pinger in pingers
            send(host, addr(pinger), CreatePeer(nothing))
        end
        hosttask = @async host(; remote = false, exit = true)

        @info "Sleeping to allow ping-pong to start."
        sleep(15.0)
        for pinger in pingers
            @test pinger.pings_sent > 1e3
            @test pinger.pongs_got > 1e3
        end

        @info "Measuring in-thread ping-pong performance (10 secs)"
        startpingcounts = [pinger.pings_sent for pinger in pingers]
        startts = Base.time_ns()
        sleep(10.0)
        rounds_made = sum([pingers[i].pings_sent - startpingcounts[i] for i=1:length(pingers)])
        wall_time_used = Base.time_ns() - startts
        for pinger in pingers
            @test pinger.pings_sent > 1e3
            @test pinger.pongs_got > 1e3
        end
        shutdown!(host)
        sleep(0.001)
        endpingcounts = [pinger.pings_sent for pinger in pingers]
        sleep(0.1)
        for i = 1:length(pingers)
            @test pingers[i].pongs_got in [pingers[i].pings_sent, pingers[i].pings_sent - 1]
            @test endpingcounts[i] === pingers[i].pings_sent
        end
        @printf "In-thread ping-pong performance: %f rounds/sec\n" (rounds_made / wall_time_used * 1e9)
    end

end

end
