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
    # @testset "Empty host creation and run" begin
    #     host = Host(3)
    #     @test length(host.schedulers) == 3
    #     for i in 1:3
    #         @test length(host.schedulers[i].plugins[:host].peers) == 2
    #     end
    #     host(;exit_when_done=true)
    #     shutdown!(host)
    # end

    @testset "Inter-thread Ping-Pong inside Host" begin
        pinger = PingPonger(nothing)
        host = Host(2, Circo.cli.plugins; options = (zygote=[pinger],))
        hosttask = @async host(Msg(addr(pinger), CreatePeer(postcode(host.schedulers[end]))))
        @info "Sleeping to allow ping-pong to start."
        sleep(8.0)
        @test pinger.pings_sent > 10
        @test pinger.pongs_got > 10

        @info "Measuring inter-thread ping-pong performance"
        startpingcount = pinger.pings_sent
        startts = Base.time_ns()
        sleep(3.0)
        rounds_made = pinger.pings_sent - startpingcount
        wall_time_used = Base.time_ns() - startts
        @test pinger.pings_sent > 1e2
        @test pinger.pongs_got > 1e2
        shutdown!(host)
        sleep(0.1)
        endpingcount = pinger.pings_sent
        @test pinger.pongs_got in [pinger.pings_sent, pinger.pings_sent - 1]
        sleep(0.1)
        @test endpingcount === pinger.pings_sent
        @printf "Inter-thread ping-pong performance: %f rounds/sec\n" (rounds_made / wall_time_used * 1e9)
    end

    @testset "In-thread Ping-Pong inside Host" begin
        pinger = PingPonger(nothing)
        host = Host(1, Circo.cli.plugins; options = (zygote=[pinger],))

        hosttask = @async host(Msg(addr(pinger), CreatePeer(nothing)); process_external = false, exit_when_done = true)

        @info "Sleeping to allow ping-pong to start."
        sleep(8.0)
        @test pinger.pings_sent > 1e4
        @test pinger.pongs_got > 1e4

        @info "Measuring in-thread ping-pong performance (10 secs)"
        startpingcount = pinger.pings_sent
        startts = Base.time_ns()
        sleep(10.0)
        rounds_made = pinger.pings_sent - startpingcount
        wall_time_used = Base.time_ns() - startts
        @test pinger.pings_sent > 1e5
        @test pinger.pongs_got > 1e5
        shutdown!(host)
        sleep(0.001)
        endpingcount = pinger.pings_sent
        sleep(0.1)
        @test pinger.pongs_got in [pinger.pings_sent, pinger.pings_sent - 1]
        @test endpingcount === pinger.pings_sent
        @printf "In-thread ping-pong performance: %f rounds/sec\n" (rounds_made / wall_time_used * 1e9)
    end

end

end
