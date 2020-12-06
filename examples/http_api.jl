# SPDX-License-Identifier: MPL-2.0

mutable struct API{TCore} <: Actor{TCore}
    msg_count::Int
    reset_ts::UInt64
    core::TCore
    API(core) = new{typeof(core)}(0, time_ns(), core)
end

function Circo.onspawn(me::API, service)
    @async begin # Workaround for init timing issue
        http = getname(service, "http")
        isnothing(http) && error("No http service found")
        send(service, me, http, Circo.PrefixRoute("/api", addr(me)))
    end
    @async begin
        while true
            sleep(1)
            if (me.msg_count > 0)
                println("Served $(me.msg_count) requests during the last second")
                me.msg_count = 0
            end
        end
    end
end

function Circo.onmessage(me::API, msg::Circo.HttpRequest, service)
    send(service, me, msg.respondto, Circo.HttpResponse(msg.id, 200, [], Vector{UInt8}("Response from the API for $(msg.id)")))
    me.msg_count += 1
end

zygote(ctx) = [API(emptycore(ctx))]
plugins(;options...) = [Debug.MsgStats(;options...), HttpService(;options...)]
profile(;options...) = Circo.Profiles.ClusterProfile(;options...)

