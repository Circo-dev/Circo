# SPDX-License-Identifier: LGPL-3.0-only
include("typeregistry.jl")

using HTTP, Logging, MsgPack
import Sockets

const MASTERPOSTCODE = "Master"

struct RegistrationRequest
    actoraddr::Addr
end
struct Registered
    actoraddr::Addr
    accepted::Bool
end

println("Please ignore the following warning about method redefinition:")
MsgPack.msgpack_type(::Type) = MsgPack.StructType() # TODO this drops the warning "incremental compilation may be fatally broken for this module"

MsgPack.msgpack_type(::Type{ActorId}) = MsgPack.StringType()
MsgPack.to_msgpack(::MsgPack.StringType, id::ActorId) = string(id, base=16)
MsgPack.from_msgpack(::Type{ActorId}, str::AbstractString) = parse(ActorId, str;base=16)

MsgPack.construct(::Type{Msg{TBody}}, args...) where TBody = begin
    Msg{TBody}(args[1], args[2], args[3], Infoton(nullpos))
end

mutable struct WebsocketService <: Plugin
    actor_connections::Dict{ActorId, IO}
    typeregistry::TypeRegistry
    socket
    WebsocketService(;options = NamedTuple()) = new(Dict(), TypeRegistry())
end

Plugins.symbol(plugin::WebsocketService) = :websocket

function Circo.schedule_start(service::WebsocketService, scheduler)
    listenport = 2497 + port(postcode(scheduler)) - CircoCore.PORT_RANGE[1] # CIWS
    ipaddr = Sockets.IPv4(0) # TODO config
    try
        service.socket = Sockets.listen(Sockets.InetAddr(ipaddr, listenport))
        @info "Web Socket listening on $(ipaddr):$(listenport)"
    catch e
        @warn "Unable to listen on $(ipaddr):$(listenport)", e
    end
    @async HTTP.listen(ipaddr, listenport; server=service.socket) do http
        if HTTP.WebSockets.is_upgrade(http.message)
            HTTP.WebSockets.upgrade(http; binary=true) do ws
                @info "Got WS connection", ws
                handle_connection(service, ws, scheduler)
            end
        end
    end
end

function Circo.schedule_stop(service::WebsocketService, scheduler)
    #@info "TODO: stop websocket tasks"
    isdefined(service, :socket) && close(service.socket)
end

function sendws(msg::Msg, ws)
    try
        write(ws, marshal(msg))
    catch e
        @error "Unable to write to websocket. Target: $(target(msg)) Message type: $(typeof(body(msg)))" exception=(e, catch_backtrace())
    end
end

function handlemsg(service::WebsocketService, msg::Msg{RegistrationRequest}, ws, scheduler)
    actorid = box(body(msg).actoraddr)
    service.actor_connections[actorid] = ws
    newaddr = Addr(postcode(scheduler), actorid)
    response = Msg(target(msg), sender(msg), Registered(newaddr, true), Infoton(nullpos))
    sendws(response, ws)
    return nothing
end

function handlemsg(service::WebsocketService, query::Msg{NameQuery}, ws, scheduler)
    namehandler = getname(scheduler.registry, body(query).name)
    if isnothing(namehandler)
        @info "No handler for $(body(query))"
    end
    sendws(Msg(target(query),
            sender(query),
            NameResponse(body(query), namehandler, body(query).token),
            Infoton(nullpos)
            ), ws)
    return nothing
end

function handlemsg(service::WebsocketService, msg::Msg, ws, scheduler)
    if postcode(target(msg)) === MASTERPOSTCODE
        newaddr = Addr(postcode(scheduler), box(msg.target))
        msg = Msg(sender(msg), newaddr, body(msg), Infoton(nullpos))
    end
    deliver!(scheduler, msg)
    return nothing
end

handlemsg(service::WebsocketService, msg, ws, scheduler) = nothing

function readtypename_safely(buf)
    try
        io = IOBuffer(buf)
        return readline(io)
    catch e
        return "Unknown type: exception while reading type name: $e"
    end
end

function handle_connection(service::WebsocketService, ws, scheduler)
    @debug "ws handle_connection on thread $(Threads.threadid())"
    buf = nothing
    msg = nothing
    try
        while !eof(ws)
            try
                buf = readavailable(ws)
            catch e
                @debug "Websocket closed: $e"
                return
            end
            msg = unmarshal(service.typeregistry, buf)
            handlemsg(service, msg, ws, scheduler)
        end
    catch e
        if e isa MethodError && e.f == convert
            @info "Field of type $(e.args[1]) was not found while unmarshaling type $(readtypename_safely(buf))"
            @debug "Erroneous websocket frame: ", buf
        else
            @error "Exception while handling websocket frame" exception=(e, catch_backtrace())
        end
    end
    @debug "Websocket closed", ws
end

function marshal(data)
    buf = IOBuffer()
    println(buf, typeof(data))
    write(buf, pack(data))
    seek(buf, 0)
    return buf
end

function unmarshal(registry::TypeRegistry, buf)
    length(buf) > 0 || return nothing
    typename = ""
    try
        io = IOBuffer(buf)
        typename = readline(io)
        type = gettype(registry,typename)
        return unpack(io, type)
    catch e
        if e isa UndefVarError
             @warn "Type $typename is not known"
        else
            rethrow(e)
        end
    end
    return nothing
end


function Plugins.shutdown!(service::WebsocketService, scheduler)
end

function Circo.localroutes(ws_plugin::WebsocketService, scheduler::AbstractActorScheduler, msg::AbstractMsg)::Bool
    ws = get(ws_plugin.actor_connections, box(target(msg)), nothing)
    if !isnothing(ws)
        sendws(msg, ws)
        return true
    end
    return false
end
