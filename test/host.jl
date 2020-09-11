# SPDX-License-Identifier: LGPL-3.0-only
module HostTest

using Test, Printf
using Circo
import Circo:onschedule, onmessage, onmigrate

mutable struct PingPonger <: AbstractActor
    peer::Union{Addr, Nothing}
    target_postcode::Union{PostCode, Nothing}
    pings_sent::Int64
    pongs_got::Int64
    core::CoreState
    PingPonger(peer) = new(peer, nothing, 0, 0)
    PingPonger(peer, target_postcode) = new(peer, target_postcode, 0, 0)
end

struct Ping end
struct Pong end

struct CreatePeer
    target_postcode::Union{PostCode, Nothing}
end

function onschedule(me::PingPonger, service)
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
    peer = PingPonger(addr(me), message.target_postcode)
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

@testset "Host" begin
    @testset "Empty host creation and run" begin
        host = Host(3)
        @test length(host.schedulers) == 3
        for i in 1:3
            @test length(host.schedulers[i].plugins[:host].peers) == 2
        end
        host(;exit_when_done=true)
        shutdown!(host)
    end

    @testset "Inter-thread Ping-Pong inside Host" begin
        pingers = [PingPonger(nothing) for i=1:25]
        host = Host(2; zygote=pingers, profile=Circo.Profiles.ClusterProfile())
        msgs = [Msg(addr(pinger), CreatePeer(postcode(host.schedulers[end]))) for pinger in pingers]
        hosttask = @async host(msgs)
        @info "Sleeping to allow ping-pong to start."
        sleep(10.0)
        for pinger in pingers
            @test pinger.pings_sent > 1
            @test pinger.pongs_got > 1
        end

        @info "Measuring inter-thread ping-pong performance"
        startpingcounts = [pinger.pings_sent for pinger in pingers]
        startts = Base.time_ns()
        sleep(3.0)
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
        @printf "Inter-thread ping-pong performance: %f rounds/sec\n" (rounds_made / wall_time_used * 1e9)
    end

    @testset "In-thread Ping-Pong inside Host" begin
        pingers = [PingPonger(nothing) for i=1:3]
        host = Host(1; zygote=pingers)

        msgs = [Msg(addr(pinger), CreatePeer(nothing)) for pinger in pingers]
        hosttask = @async host(msgs; process_external = false, exit_when_done = true)

        @info "Sleeping to allow ping-pong to start."
        sleep(8.0)
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
