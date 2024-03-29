# SPDX-License-Identifier: MPL-2.0

struct TaskedRequest
    req::HttpRequest
    response_chn::Channel{HttpResponse}
end

abstract type Route end

struct PrefixRoute <: Route
    prefix::String
    handler::Addr
end

struct RouteResult
    handler::Addr
end

function route(route::PrefixRoute, req::HttpRequest)::Union{RouteResult, Nothing}
    if startswith(req.target, route.prefix)
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
    reqs::Dict{Token, TaskedRequest}
    router::Router
    core::TCore
    _HttpDispatcher(core) = new{typeof(core)}(Dict(), Router(), core)
end

abstract type HttpServer <: Plugin end
Plugins.symbol(plugin::HttpServer) = :httpserver

mutable struct HttpServerImpl <: HttpServer
    maxrequestsizeinbyte::Number
    router::Router
    socket::Sockets.TCPServer
    dispatcher

    HttpServerImpl(;http_max_request_size = 1024*1024, options...) = new(http_max_request_size)
end

function Circo.setup!(http::HttpServerImpl, scheduler)
    http.maxrequestsizeinbyte = parse(Int, get(ENV, "HTTP_MAX_REQUEST_SIZE", string(http.maxrequestsizeinbyte)))
    @info "Allowed maximum size of a request payload : $(http.maxrequestsizeinbyte / 1024) KB"
end

function Circo.schedule_start(http::HttpServerImpl, scheduler)
    http.dispatcher = _HttpDispatcher(emptycore(scheduler.service))
    spawn(scheduler, http.dispatcher)
    registername(scheduler.service, "httpserver", http.dispatcher)

    @debug "HttpService's dispatcher address" addr(http.dispatcher)

    listenport = 8080 + port(postcode(scheduler)) - CircoCore.PORT_RANGE[1]
    ipaddr = Sockets.IPv4(0) # TODO config
    try
        http.socket = Sockets.listen(Sockets.InetAddr(ipaddr, listenport))
        @info "Http listening on $(ipaddr):$(listenport)"
    catch e
        @warn "Http unable to listen on $(ipaddr):$(listenport)", e
    end
    dispatcher_addr = addr(http.dispatcher)
    @async HTTP.serve(ipaddr, listenport; server=http.socket) do httprequest
        msglength = length(httprequest.body)

        if msglength > http.maxrequestsizeinbyte
            @warn "Payload size is too big!" msglength
            retval = HTTP.Response(
                413
                , []
                ; body = "Payload size is too big! Accepted maximum size $(http.maxrequestsizeinbyte /1024) KB"
                , request = httprequest
            )
    
            @debug "Responding with"  retval
            return retval
        end


        response_chn = Channel{HttpResponse}(2)
        request = HttpRequest(;
                respondto = dispatcher_addr
                , method = httprequest.method
                , target = httprequest.target
                , headers = httprequest.headers
                , body = httprequest.body)

        taskedRequest = TaskedRequest(request, response_chn)
        send(scheduler, dispatcher_addr, taskedRequest)

        response = take!(response_chn)

        retval = HTTP.Response(
            response.status
            , response.headers
            ; body = response.body
            , request = httprequest
        )

        @debug "Responding with"  retval
        return retval
    end
end

function Circo.schedule_stop(service::HttpServerImpl, scheduler)
    isdefined(service, :socket) && close(service.socket)
end

function Circo.onmessage(me::HttpDispatcher, msg::TaskedRequest, service)
    me.reqs[msg.req.token] = msg
    routeresult = route(me.router, msg.req)
    @debug "Circo.routeresult $routeresult"
    if isnothing(routeresult)
        send(service, me, addr(me), HttpResponse(msg.req.token, 404, [], Vector{UInt8}("No route found for $(msg.req.raw.target)") ))
        return nothing
    end
    send(service, me, routeresult.handler, msg.req)
    return nothing
end

function Circo.onmessage(me::HttpDispatcher, msg::HttpResponse, service)
    println("Circo.onmessage(me::HttpDispatcher, msg::HttpResponse, service)")
    tasked = get(me.reqs, msg.token, nothing)
    isnothing(tasked) && return nothing
    delete!(me.reqs, msg.token)
    put!(tasked.response_chn, msg)
    return nothing
end

function Circo.onmessage(me::HttpDispatcher, msg::Route, service)
    push!(me.router, msg)
    @info "Added route: $msg"
    
    # TODO create a feedback to actor
    return nothing
end
