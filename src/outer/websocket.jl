# SPDX-License-Identifier: MPL-2.0
module WebSocket

export WebsocketService

using ..Circo
using Circo.InfotonOpt # TODO eliminate
using Plugins
using HTTP, Logging, MsgPack
using CircoCore.Registry
import Sockets

include("typeregistry.jl")

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

abstract type WebsocketService <: Plugin end
mutable struct WebsocketServiceImpl <: WebsocketService
    actor_connections::Dict{ActorId, IO}
    typeregistry::TypeRegistry
    msg_type_name::String
    socket
    WebsocketServiceImpl(;options...) = new(Dict(), TypeRegistry())
end
Plugins.symbol(plugin::WebsocketServiceImpl) = :websocket
__init__() = Plugins.register(WebsocketServiceImpl)

Circo.prepare(::WebsocketServiceImpl, ctx) = begin
    MsgType = ctx.msg_type
    defaulted_fields = map(type -> :($type()), MsgType.body.types[4:end]) # Assuming 3 filled-in fields
    eval(:(
        MsgPack.construct(::Type{$(MsgType){TBody}}, sender::Addr, target::Addr, body, args...) where TBody = begin
            $(Expr(:call, :($(MsgType){TBody}), :(sender), :(target), :(body), defaulted_fields...))
        end
    ))
    return nothing
end

Circo.schedule_start(service::WebsocketServiceImpl, scheduler::AbstractScheduler{TMsg}) where {TMsg} = begin # TODO during setup!, after PostOffice initialized
    service.msg_type_name = string(TMsg)
    listenport = 2497 + port(postcode(scheduler)) - CircoCore.PORT_RANGE[1] # CIWS
    ipaddr = Sockets.IPv4(0) # TODO config
    try
        service.socket = Sockets.listen(Sockets.InetAddr(ipaddr, listenport))
        @info "Web Socket listening on $(ipaddr):$(listenport)"
    catch e
        @warn "Web Socker unable to listen on $(ipaddr):$(listenport)", e
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

function Circo.schedule_stop(service::WebsocketServiceImpl, scheduler)
    isdefined(service, :socket) && close(service.socket)
end

function _sendws(ws_plugin::WebsocketServiceImpl, msg::AbstractMsg, actorid::ActorId, ws)
    try
        write(ws, marshal(msg))
    catch e
        @debug "Unable to write to websocket, removing registration of actor $(actorid). Target: $(target(msg)) Message type: $(typeof(body(msg)))" exception=(e, catch_backtrace())
        delete!(ws_plugin.actor_connections, actorid)
        try close(ws) catch end
    end
end

function handlemsg(service::WebsocketServiceImpl, msg::AbstractMsg{RegistrationRequest}, ws, scheduler::AbstractScheduler{TMsg}) where {TMsg}
    actorid = box(body(msg).actoraddr)
    service.actor_connections[actorid] = ws
    newaddr = Addr(postcode(scheduler), actorid)
    response = TMsg(target(msg), sender(msg), Registered(newaddr, true), Infoton(nullpos))
    _sendws(service, response, actorid, ws)
    return nothing
end

function handlemsg(service::WebsocketServiceImpl, query::AbstractMsg{CircoCore.Registry.NameQuery}, ws, scheduler::AbstractScheduler{TMsg}) where {TMsg}
    registry = get(scheduler.plugins, :registry, nothing)
    if isnothing(registry)
        @info "No registry plugin installed, dropping $query"
        return nothing
    end
    namehandler = getname(registry, body(query).name)
    if isnothing(namehandler)
        @info "No handler for $(body(query))"
    end
    _sendws(service,
            TMsg(target(query),
                sender(query),
                NameResponse(body(query), namehandler, body(query).token),
                Infoton(nullpos)
            ),
            box(sender(query)),
            ws)
    return nothing
end

function handlemsg(service::WebsocketServiceImpl, msg::AbstractMsg, ws, scheduler::AbstractScheduler{TMsg}) where {TMsg}
    if postcode(target(msg)) === MASTERPOSTCODE
        newaddr = Addr(postcode(scheduler), box(msg.target))
        msg = TMsg(sender(msg), newaddr, body(msg), Infoton(nullpos))
    end
    Circo.deliver!(scheduler, msg)
    return nothing
end

handlemsg(service::WebsocketServiceImpl, msg, ws, scheduler) = nothing

function readtypename_safely(buf)
    try
        io = IOBuffer(buf)
        return readline(io)
    catch e
        return "Unknown type: exception while reading type name: $e"
    end
end

function handle_connection(service::WebsocketServiceImpl, ws, scheduler)
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
            msg = unmarshal(service, buf)
            handlemsg(service, msg, ws, scheduler)
        end
    catch e
        if e isa MethodError && e.f == convert
            @info "Field of type $(e.args[1]) was not found while unmarshaling type '$(readtypename_safely(buf))'"
            @debug "Erroneous websocket frame: ", buf
        elseif e isa IOError
            @debug "Error reading websocket", ws
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

function unmarshal(service::WebsocketServiceImpl, buf)
    length(buf) > 0 || return nothing
    typename = ""
    try
        io = IOBuffer(buf)
        typename = service.msg_type_name * readline(io)
        type = gettype(service.typeregistry, typename)
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

Plugins.shutdown!(service::WebsocketServiceImpl, scheduler) = nothing

Circo.localroutes(ws_plugin::WebsocketServiceImpl, scheduler, msg::AbstractMsg)::Bool = begin
    ws = get(ws_plugin.actor_connections, box(target(msg)), nothing)
    if !isnothing(ws)
        _sendws(ws_plugin, msg, box(target(msg)), ws)
        return true
    end
    return false
end

end # module
