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
    data
    # origin
    # lastEventId 
    source              #sender Actor Addr
    ports               #websocket client actor addr

    websocketid::UInt32
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
    response
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
                @info "Client got from server rawMessage" rawMessage
                #TODO marshalling?
                receivedMessage = String(rawMessage)
                Circo.send(service, me, openmsg.source, WebSocketReceive(MessageEvent(), websocketId, receivedMessage))
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
sendingWebSocketMessage( ws, ::WebSocketClose) = HTTP.close(ws)

function sendingWebSocketMessage(ws, msg::WebSocketSend)
    @debug "WebsocketTestCaller sending message $(msg.data)"
    HTTP.send(ws, msg.data)
end

function Circo.onmessage(me::WebSocketCallerActor, msg::WebSocketMessage, service)
    # TODO currently without this logging line, the code won't work. Must reitarete on this problema after changeing msg.data type. 
    @info "Message arrived $(typeof(msg))" msg.data    
    ws = get(me.messageChannels, websocketId(msg), missing)
    # TODO handle missing

    sendingWebSocketMessage(ws, msg)
end


end #module