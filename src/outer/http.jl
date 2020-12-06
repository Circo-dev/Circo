# SPDX-License-Identifier: MPL-2.0

import HTTP, Sockets
using Logging

HttpReqId = UInt64
struct HttpRequest
    id::HttpReqId
    respondto::Addr
    raw::HTTP.Messages.Request
end

struct HttpResponse
    reqid::HttpReqId
    status::Int16
    headers::Vector{Pair{String,String}}
    body::Vector{UInt8}
end

struct TaskedRequest
    req::HttpRequest
    response_chn::Channel{HttpResponse}
end

abstract type Route end

struct RouteResult
    handler::Addr
end

struct PrefixRoute <: Route
    prefix::String
    handler::Addr
end

function route(route::PrefixRoute, req::HttpRequest)::Union{RouteResult, Nothing}
    if startswith(req.raw.target, route.prefix)
        return RouteResult(route.handler)
    end
    return nothing
end

struct Router
    routes::Vector{Route}
    Router() = new([])
end

Base.push!(router::Router, route) = push!(router.routes, route)

function route(router::Router, req)
    for r in router.routes
        result = route(r, req)
        !isnothing(result) && return result
    end
    return nothing
end

abstract type HttpDispatcher{TCore} <: Actor{TCore} end

mutable struct _HttpDispatcher{TCore} <: HttpDispatcher{TCore}
    reqs::Dict{HttpReqId, TaskedRequest}
    router::Router
    core::TCore
    _HttpDispatcher(core) = new{typeof(core)}(Dict(), Router(), core)
end

mutable struct HttpService <: Plugin
    router::Router
    socket::Sockets.TCPServer
    dispatcher
    HttpService(;options...) = new()
end

Plugins.symbol(plugin::HttpService) = :http

function Circo.setup!(http::HttpService, scheduler)
    http.dispatcher = _HttpDispatcher(emptycore(scheduler.service))
    schedule!(scheduler, http.dispatcher)
    registername(scheduler.service, "http", http.dispatcher)
end

function Circo.schedule_start(http::HttpService, scheduler)
    listenport = 8080 + port(postcode(scheduler)) - CircoCore.PORT_RANGE[1]
    ipaddr = Sockets.IPv4(0) # TODO config
    try
        http.socket = Sockets.listen(Sockets.InetAddr(ipaddr, listenport))
        @info "Http listening on $(ipaddr):$(listenport)"
    catch e
        @warn "Http unable to listen on $(ipaddr):$(listenport)", e
    end
    dispatcher_addr = addr(http.dispatcher)
    @async HTTP.listen(ipaddr, listenport; server=http.socket) do raw_http
        response_chn = Channel{HttpResponse}(2)
        send(scheduler, dispatcher_addr, TaskedRequest(HttpRequest(rand(HttpReqId), dispatcher_addr, raw_http.message), response_chn))
        response = take!(response_chn)
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

function Circo.onmessage(me::HttpDispatcher, msg::TaskedRequest, service)
    me.reqs[msg.req.id] = msg
    routeresult = route(me.router, msg.req)
    if isnothing(routeresult)
        send(service, me, addr(me), HttpResponse(msg.req.id, 404, [], Vector{UInt8}("No route found for $(msg.req.raw.target)") ))
        return nothing
    end
    send(service, me, routeresult.handler, msg.req)
    return nothing
end

function Circo.onmessage(me::HttpDispatcher, msg::HttpResponse, service)
    tasked = get(me.reqs, msg.reqid, nothing)
    isnothing(tasked) && return nothing
    delete!(me.reqs, msg.reqid)
    put!(tasked.response_chn, msg)
    return nothing
end

function Circo.onmessage(me::HttpDispatcher, msg::Route, service)
    push!(me.router, msg)
    @info "Added route: $msg"
    return nothing
end