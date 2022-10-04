# SPDX-License-Identifier: MPL-2.0
module WebsocketClient

export WebSocketClient
export WebSocketCallerActor
export WebSocketMessage, WebSocketClose, WebSocketOpen, WebSocketSend
export CloseEvent, MessageEvent, ErrorEvent, OpenEvent

using HTTP, HTTP.WebSockets
using Sockets
using ..Circo, ..Circo.Marshal
using Plugins
using Logging
using Random

abstract type WebSocketMessage 
end

struct WebSocketSend <: WebSocketMessage
    data::Vector{UInt8}
    # origin
    # lastEventId 
    source              #sender Actor Addr
    ports               #websocket client actor addr

    websocketid::UInt32

    WebSocketSend(data, source, ports, websocketId) = new(data, source, ports, websocketId)
    WebSocketSend(data::String, source, ports, websocketId) = new(Vector{UInt8}(data), source, ports, websocketId)

end

struct WebSocketClose <: WebSocketMessage
    source              #sender Actor Addr

    websocketid::UInt32
end

struct WebSocketOpen <: WebSocketMessage
    token::Token
    source              #sender Actor Addr
    url                 #should contain protocol and port if needed

    WebSocketOpen(source, url) = new(Token(), source, url)
end

struct CloseEvent
    websocketid::UInt32
    status::Int
    response::AbstractVector{UInt8}         # message

    CloseEvent(websocketId, status, response) = new(websocketId, 1000, response)
    CloseEvent(websocketId, status, response::String) = new(websocketId, status,  Vector{UInt8}(response))
end

struct MessageEvent
    websocketid::UInt32
    response::AbstractVector{UInt8}

    MessageEvent(websocketId, response) = new(websocketId, response)
    MessageEvent(websocketId, response::String) = new(websocketId, Vector{UInt8}(response))
end

struct ErrorEvent
    websocketid::UInt32
    response::AbstractVector{UInt8}

    ErrorEvent(websocketId, response) = new(websocketId, response)
    ErrorEvent(websocketId, response::String) = new(websocketId, Vector{UInt8}(response))
end

struct OpenEvent
    token::Token
    websocketid::UInt32
    response::AbstractVector{UInt8}

    OpenEvent(token, websocketId, response) = new(token, websocketId, response)
    OpenEvent(token, websocketId, response::String) = new(token, websocketId, Vector{UInt8}(response))
end
responsetype(::Type{<:WebSocketOpen}) = OpenEvent


websocket_id(msg::WebSocketOpen) = missing
websocket_id(msg::WebSocketSend) = UInt64(msg.websocketid)
websocket_id(msg::WebSocketClose) = UInt64(msg.websocketid)


mutable struct WebSocketCallerActor <: Actor{Any}
    messageChannels::Dict{UInt64, WebSocket}
    core::Any

    WebSocketCallerActor() = new(Dict{UInt32, WebSocket}())
end

abstract type WebSocketClient <: Plugin end
Plugins.symbol(plugin::WebSocketClient) = :websocketclient

mutable struct WebSocketClientImpl <: WebSocketClient
    helper::WebSocketCallerActor
    WebSocketClientImpl(;options...) = new()
end

__init__() = begin 
    Plugins.register(WebSocketClientImpl)
end


function Circo.schedule_start(websocket::WebSocketClientImpl, scheduler)
    websocket.helper = WebSocketCallerActor()
    spawn(scheduler.service, websocket.helper)
    registername(scheduler.service, "websocketclient", websocket.helper)

    address = addr(websocket.helper)
    @debug "WebSocketCallerActor.addr : $address"
end

function Circo.onmessage(me::WebSocketCallerActor, openmsg::WebSocketOpen, service)    

    connectiontask = @async WebSockets.open("$(openmsg.url)"; verbose=false) do ws
        websocket_id = rand(UInt32)
        get!(me.messageChannels, websocket_id, ws)
        
        @debug "Client Websocket connection established!"
        Circo.send(service, me, openmsg.source, OpenEvent(openmsg.token, websocket_id, "Websocket connection established!"))

        closeeventsent = false
        try 
            for raw_message in ws
                @debug "Client got from server rawMessage" String(raw_message)
                Circo.send(service, me, openmsg.source, MessageEvent(websocket_id, raw_message))
            end
        catch e
            @warn "Exception" e
            if typeof(e) == HTTP.WebSockets.WebSocketError
                if typeof(e.message) == HTTP.WebSockets.CloseFrameBody
                    Circo.send(service, me, openmsg.source, CloseEvent(websocket_id, e.message.status, e.message.message))
                    closeeventsent = true
                else
                    Circo.send(service, me, openmsg.source, ErrorEvent(websocket_id, e.message))
                end
            end
        finally
            if !closeeventsent
                Circo.send(service, me, openmsg.source, CloseEvent(websocket_id, 1000, "Websocket connection closed"))
            end
            delete!(me.messageChannels, websocket_id)
        end
        # unnecessary
        # close(ws)
    end

    if istaskfailed(connectiontask)
        websocket_errorcode = connectiontask.result.error.message.status
        @warn "Error occured when establishing websocket connection! Errorcode : $(websocket_errorcode)"
        Circo.send(service, me, openmsg.source, ErrorEvent(websocket_id, websocket_errorcode))
    end
end 

sending_websocket_message(ws, msg) = WebSocket.isopen(ws) && error("Unknown message type received! Got : $(typeof(msg))")
sending_websocket_message(ws, ::WebSocketOpen) = error("Got WebSocketOpen message from an opened websocket!")
sending_websocket_message(ws, ::WebSocketClose) = HTTP.close(ws)
sending_websocket_message(ws, wsmessage::WebSocketSend) = HTTP.send(ws, wsmessage.data)

function Circo.onmessage(me::WebSocketCallerActor, wsmessage::WebSocketMessage, service)
    ws = get(me.messageChannels, websocket_id(wsmessage), missing)
    if ws === missing
        Circo.send(service, me, wsmessage.source, ErrorEvent(websocket_id, "Got unknown websocket id"))
    else 
        sending_websocket_message(ws, wsmessage)
    end
end


end #module
