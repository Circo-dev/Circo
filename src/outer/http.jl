# SPDX-License-Identifier: MPL-2.0

import HTTP
using Logging

HttpRequestId = UInt64

struct HttpResponse
    requestid::HttpRequestId
    status::Int16
    headers::Vector{Pair{String,String}}
    body::Vector{UInt8}
end

struct HttpRequest
    id::HttpRequestId
    raw::HTTP.Messages.Request
end

struct RequestHandler
    request::HttpRequest
    response_chn::Channel{HttpResponse}
end

mutable struct HttpActor{TCore} <: Actor{TCore}
    requests::Dict{HttpRequestId, RequestHandler}
    core::TCore
    HttpActor(core) = new{typeof(core)}(Dict(), core)
end

mutable struct HttpService <: Plugin
    actor
    socket
    HttpService(;options...) = new()
end

Plugins.symbol(plugin::HttpService) = :http

function Plugins.setup!(http::HttpService, scheduler)
end

function Circo.schedule_start(http::HttpService, scheduler)
    http.actor = HttpActor(emptycore(scheduler.service))# TODO should run earlier but can run only after PostOffice setup!
    schedule!(scheduler, http.actor)
    registername(scheduler.service, "http", http.actor)

    listenport = 8080 + port(postcode(scheduler)) - CircoCore.PORT_RANGE[1]
    ipaddr = Sockets.IPv4(0) # TODO config
    try
        http.socket = Sockets.listen(Sockets.InetAddr(ipaddr, listenport))
        @info "Http listening on $(ipaddr):$(listenport)"
    catch e
        @warn "Http unable to listen on $(ipaddr):$(listenport)", e
    end
    @show actoraddr = addr(http.actor)
    @async HTTP.listen(ipaddr, listenport; server=http.socket) do raw_http
        response_chn = Channel{HttpResponse}(2)
        send(scheduler, actoraddr, RequestHandler(HttpRequest(rand(HttpRequestId), raw_http.message), response_chn))
        @show response = take!(response_chn)
        HTTP.setstatus(raw_http, response.status)
        for header in response.headers
            HTTP.setheader(raw_http, header)
        end
        startwrite(raw_http)
        write(raw_http, response.body)
        return nothing
    end
end

function Circo.schedule_stop(service::HttpService, scheduler)
    isdefined(service, :socket) && close(service.socket)
end

function Circo.onmessage(me::HttpActor, msg::RequestHandler, service)
    @show msg
    me.requests[msg.request.id] = msg
    send(service, me, addr(me), HttpResponse(msg.request.id, 200, ["testheader" => "42"], Vector{UInt8}("Hello Leo!") ))
end

function Circo.onmessage(me::HttpActor, msg::HttpResponse, service)
    handler = me.requests[msg.requestid]
    delete!(me.requests, msg.requestid)
    @async begin
        sleep(2)
        put!(handler.response_chn, msg)
    end
end