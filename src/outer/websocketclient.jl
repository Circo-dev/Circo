# SPDX-License-Identifier: MPL-2.0
module WebsocketClient

export WebSocketCallerActor, WebSocketMessage, WebSocketClose, WebSocketOpen, WebSocketSend, WebSocketResponse

using HTTP, HTTP.WebSockets
using Sockets
using ..Circo, ..Circo.Marshal
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

struct WebSocketResponse
    request::WebSocketMessage
    websocketid::UInt32
    response
end

websocketId(msg::WebSocketOpen) = missing
websocketId(msg::WebSocketSend) = UInt64(msg.websocketid)
websocketId(msg::WebSocketClose) = UInt64(msg.websocketid)


mutable struct WebSocketCallerActor <: Actor{Any}
    core::Any
    messageChannels::Dict{UInt64, Channel}

    WebSocketCallerActor(core) = new(core, Dict{UInt32, Channel}())
end

function Circo.onmessage(me::WebSocketCallerActor, openmsg::WebSocketOpen, service)
    websocketId = rand(UInt32)
    channel = Channel{}(10)

    get!(me.messageChannels, websocketId, channel)

    @async WebSockets.open("ws://$(openmsg.url)"; verbose=true) do ws

        # @debug "Client Websocket connection established!"
        # Circo.send(service, me, openmsg.source, WebSocketResponse(openmsg, websocketId, "Websocket connection established!"))

        isWebSocketClosed = false
        while !isWebSocketClosed
            channel = get(me.messageChannels, websocketId, missing)
            msg = take!(channel)

            @debug "WebsocketTestCaller sending message $(msg))"
            (isWebSocketClosed, response) = processMessage(me, ws, msg)
            
            # TODO marshalling?
            response = String(response)
            Circo.send(service, me, msg.source, WebSocketResponse(msg, websocketId, response))
        end
        # unnecessary
        # close(ws)
    end

    # TODO after pluginasation this must go, because this way we lie about connection.
    @debug "Client WebSocket connecting!"
    Circo.send(service, me, openmsg.source, WebSocketResponse(openmsg, websocketId, "Websocket connection established!"))
end 

function processMessage(me, ws, msg) 
    if WebSocket.isopen(ws)
        error("Unknown message type received! Got : $(typeof(msg))")
    else
        return (true, missing)
    end
end
processMessage(me, ws, ::WebSocketOpen) = error("Got WebSocketOpen message from an opened websocket!")
function processMessage(me, ws, msg::WebSocketClose)
    id = websocketId(msg)
    delete!(me.messageChannels, id)
    (true, "Websocket connection closed")
end 

function processMessage(me, ws, msg::WebSocketSend)
    #TODO marshalling
    @debug "WebsocketTestCaller sending message $(msg.data)"
    HTTP.send(ws, msg.data)

    # TODO add shouldwewait flag to WebSocketSend if true -> receive,  false -> skip
    response = HTTP.receive(ws)
    return (false, response)
end


function Circo.onmessage(me::WebSocketCallerActor, msg::WebSocketMessage, service)
    @debug "Message arrived $(typeof(msg))"
    channel = get(me.messageChannels, websocketId(msg), missing)
    # TODO handle missing
    put!(channel, msg)
end


end #module