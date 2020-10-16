# SPDX-License-Identifier: MPL-2.0
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

MsgPack.msgpack_type(::DataType) = MsgPack.StructType() # TODO use StructTypes.jl or an abstract type

MsgPack.msgpack_type(::Type{ActorId}) = MsgPack.StringType()
MsgPack.to_msgpack(::MsgPack.StringType, id::ActorId) = string(id, base=16)
MsgPack.from_msgpack(::Type{ActorId}, str::AbstractString) = parse(ActorId, str;base=16)

mutable struct WebsocketService <: Plugin
    actor_connections::Dict{ActorId, IO}
    typeregistry::TypeRegistry
    socket
    WebsocketService(;options...) = new(Dict(), TypeRegistry())
end

Plugins.symbol(plugin::WebsocketService) = :websocket

Circo.prepare(::WebsocketService, ctx) = begin
    MsgType = ctx.msg_type
    defaulted_fields = map(type -> :($type()), MsgType.body.types[4:end]) # Assuming 3 filled-in fields
    eval(:(
        MsgPack.construct(::Type{$(MsgType){TBody}}, sender::Addr, target::Addr, body, args...) where TBody = begin
            $(Expr(:call, :($(MsgType){TBody}), :(sender), :(target), :(body), defaulted_fields...))
        end
    ))
    return nothing
end

Circo.schedule_start(service::WebsocketService, scheduler) = begin # TODO during setup!, after PostOffice initialized
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
    isdefined(service, :socket) && close(service.socket)
end

function sendws(msg::AbstractMsg, ws)
    try
        write(ws, marshal(msg))
    catch e
        @error "Unable to write to websocket. Target: $(target(msg)) Message type: $(typeof(body(msg)))" exception=(e, catch_backtrace())
    end
end

function handlemsg(service::WebsocketService, msg::AbstractMsg{RegistrationRequest}, ws, scheduler)
    actorid = box(body(msg).actoraddr)
    service.actor_connections[actorid] = ws
    newaddr = Addr(postcode(scheduler), actorid)
    response = Msg(target(msg), sender(msg), Registered(newaddr, true), Infoton(nullpos))
    sendws(response, ws)
    return nothing
end

function handlemsg(service::WebsocketService, query::AbstractMsg{NameQuery}, ws, scheduler)
    registry = get(scheduler.plugins, :registry, nothing)
    if isnothing(registry)
        @info "No registry plugin installed, dropping $query"
        return nothing
    end
    namehandler = getname(registry, body(query).name)
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

function handlemsg(service::WebsocketService, msg::AbstractMsg, ws, scheduler)
    if postcode(target(msg)) === MASTERPOSTCODE
        newaddr = Addr(postcode(scheduler), box(msg.target))
        msg = Msg(sender(msg), newaddr, body(msg), Infoton(nullpos))
    end
    Circo.deliver!(scheduler, msg)
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
            @info "Field of type $(e.args[1]) was not found while unmarshaling type '$(readtypename_safely(buf))'"
            @debug "Erroneous websocket frame: ", buf
        else
            # TODO this causes segfault on 1.5.0 with multithreading
            if Threads.nthreads() == 1
                @error "Exception while handling websocket frame" exception=(e, catch_backtrace())
            else
                @error "Exception while handling websocket frame: $e"
                @error "Cannot print stack trace due to an unknown issue in Base or HTTP.jl. Rerun with JULIA_NUM_THREADS=1 to get more info"
            end
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

Plugins.shutdown!(service::WebsocketService, scheduler) = nothing

Circo.localroutes(ws_plugin::WebsocketService, scheduler, msg::AbstractMsg)::Bool = begin
    ws = get(ws_plugin.actor_connections, box(target(msg)), nothing)
    if !isnothing(ws)
        sendws(msg, ws)
        return true
    end
    return false
end
