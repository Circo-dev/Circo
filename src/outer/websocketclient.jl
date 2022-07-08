# SPDX-License-Identifier: MPL-2.0
module WebsocketClient

export WebSocketClient
export WebSocketEvent, CloseEvent, MessageEvent, ErrorEvent, OpenEvent
export WebSocketCallerActor, WebSocketMessage, WebSocketClose, WebSocketOpen, WebSocketSend, WebSocketReceive

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
    source              #sender Actor Addr
    url
end

abstract type WebSocketEvent end
struct CloseEvent <: WebSocketEvent end
struct MessageEvent <: WebSocketEvent end
struct ErrorEvent <: WebSocketEvent end
struct OpenEvent <: WebSocketEvent end

struct WebSocketReceive
    type::WebSocketEvent
    websocketid::UInt32
    response::AbstractVector{UInt8}

    WebSocketReceive(type, websocketId, response) = new(type, websocketId, response)
    WebSocketReceive(type, websocketId, response::String) = new(type, websocketId, Vector{UInt8}(response))
end

websocketId(msg::WebSocketOpen) = missing
websocketId(msg::WebSocketSend) = UInt64(msg.websocketid)
websocketId(msg::WebSocketClose) = UInt64(msg.websocketid)


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

    @async WebSockets.open("ws://$(openmsg.url)"; verbose=false) do ws
        websocketId = rand(UInt32)
        get!(me.messageChannels, websocketId, ws)
        
        @debug "Client Websocket connection established!"
        Circo.send(service, me, openmsg.source, WebSocketReceive(OpenEvent(), websocketId, "Websocket connection established!"))

        try 
            for rawMessage in ws
                @debug "Client got from server rawMessage" String(rawMessage)
                Circo.send(service, me, openmsg.source, WebSocketReceive(MessageEvent(), websocketId, rawMessage))
            end
        catch e
            if !(e isa EOFError)
                @info "Exception in arrivals", e
            end
        finally
            Circo.send(service, me, openmsg.source, WebSocketReceive(CloseEvent(), websocketId, "Websocket connection closed"))
            delete!(me.messageChannels, websocketId)
        end
        # unnecessary
        # close(ws)
    end
end 

sendingWebSocketMessage(ws, msg) = WebSocket.isopen(ws) && error("Unknown message type received! Got : $(typeof(msg))")
sendingWebSocketMessage(ws, ::WebSocketOpen) = error("Got WebSocketOpen message from an opened websocket!")
sendingWebSocketMessage(ws, ::WebSocketClose) = HTTP.close(ws)
sendingWebSocketMessage(ws, wsmessage::WebSocketSend) = HTTP.send(ws, wsmessage.data)

function Circo.onmessage(me::WebSocketCallerActor, wsmessage::WebSocketMessage, service)
    ws = get(me.messageChannels, websocketId(wsmessage), missing)
    # TODO handle missing
    sendingWebSocketMessage(ws, wsmessage)
end


end #module