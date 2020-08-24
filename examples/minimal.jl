# SPDX-License-Identifier: LGPL-3.0-only
# Sample circo.jl showing a minimal CircoCore application

module CircoSample

using CircoCore
import CircoCore: onmessage, onschedule

mutable struct SampleActor <: AbstractActor
    core::CoreState
    SampleActor() = new()
end

struct SampleMessage
    message::String
end

function onschedule(me::SampleActor, service)
    cluster = getname(service, "cluster")
    println("SampleActor scheduled on cluster: $cluster Sending a message to myself.")
    send(service, me, addr(me), SampleMessage("This is a message from $(addr(me))"))
end

function onmessage(me::SampleActor, message::SampleMessage, service)
    println("Got SampleMessage: '$(message.message)'")
end

end #module

zygote() = CircoSample.SampleActor()
