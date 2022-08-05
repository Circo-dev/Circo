# SPDX-License-Identifier: MPL-2.0
# Sample circo.jl showing a minimal CircoCore application

module CircoSample

using Circo

mutable struct SampleActor <: Actor{Any}
    core::Any
    SampleActor() = new()
end

struct SampleMsg
    text::String
end

function Circo.onmessage(me::SampleActor, ::OnSpawn, service)
    println("SampleActor scheduled. Sending a message to myself.")
    send(service, me, addr(me), SampleMsg("This is a message from $(addr(me))"))
end

function Circo.onmessage(me::SampleActor, msg::SampleMsg, service)
    println("Got SampleMessage: '$(msg.text)'")
end

end #module

zygote(ctx) = CircoSample.SampleActor()
