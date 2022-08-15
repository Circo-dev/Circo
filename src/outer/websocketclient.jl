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
    requestid::Token
    source              #sender Actor Addr
    url                 #should contain protocol and port if needed

    WebSocketOpen(source, url) = new(Token(), source, url)
end

abstract type WebSocketEvent end
struct CloseEvent <: WebSocketEvent end
struct MessageEvent <: WebSocketEvent end
struct ErrorEvent <: WebSocketEvent end
struct OpenEvent <: WebSocketEvent 
    requestid::Token

    OpenEvent(token) = new(token)
end

struct WebSocketReceive
    type::WebSocketEvent
    websocketid::UInt32
    response::AbstractVector{UInt8}

    WebSocketReceive(type, websocketId, response) = new(type, websocketId, response)
    WebSocketReceive(type, websocketId, response::String) = new(type, websocketId, Vector{UInt8}(response))
end

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

    @async WebSockets.open("$(openmsg.url)"; verbose=false) do ws
        websocket_id = rand(UInt32)
        get!(me.messageChannels, websocket_id, ws)
        
        @debug "Client Websocket connection established!"
        Circo.send(service, me, openmsg.source, WebSocketReceive(OpenEvent(openmsg.requestid), websocket_id, "Websocket connection established!"))

        try 
            for raw_message in ws
                @debug "Client got from server rawMessage" String(raw_message)
                Circo.send(service, me, openmsg.source, WebSocketReceive(MessageEvent(), websocket_id, raw_message))
            end
        catch e
            if !(e isa EOFError)
                @info "Exception in arrivals", e
            end
        finally
            Circo.send(service, me, openmsg.source, WebSocketReceive(CloseEvent(), websocket_id, "Websocket connection closed"))
            delete!(me.messageChannels, websocket_id)
        end
        # unnecessary
        # close(ws)
    end
end 

sending_websocket_message(ws, msg) = WebSocket.isopen(ws) && error("Unknown message type received! Got : $(typeof(msg))")
sending_websocket_message(ws, ::WebSocketOpen) = error("Got WebSocketOpen message from an opened websocket!")
sending_websocket_message(ws, ::WebSocketClose) = HTTP.close(ws)
sending_websocket_message(ws, wsmessage::WebSocketSend) = HTTP.send(ws, wsmessage.data)

function Circo.onmessage(me::WebSocketCallerActor, wsmessage::WebSocketMessage, service)
    ws = get(me.messageChannels, websocket_id(wsmessage), missing)
    # TODO handle missing
    sending_websocket_message(ws, wsmessage)
end


end #module
