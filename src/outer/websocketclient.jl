# SPDX-License-Identifier: MPL-2.0
module WebsocketClient

export WebSocketCallerActor, WebSocketMessage, WebSocketClose, WebSocketOpen, WebSocketSend

using HTTP, HTTP.WebSockets
using Sockets
using ..Circo, ..Circo.Marshal
using Logging

abstract type WebSocketMessage 
end

struct WebSocketSend <: WebSocketMessage
    data
    # origin
    # lastEventId 
    source              #sender Actor Addr
    ports               #websocket client actor addr
end

struct WebSocketClose <: WebSocketMessage
end

struct WebSocketOpen <: WebSocketMessage
end

mutable struct WebSocketCallerActor <: Actor{Any}
    core::Any
    url
    port
    messageChannel::Channel{}

    WebSocketCallerActor(core, url, port) = new(core, url, port, Channel{}(2))
end

function Circo.onmessage(me::WebSocketCallerActor, openmsg::WebSocketOpen, service)
    @debug "Message arrived $(typeof(openmsg))"
    @async WebSockets.open("ws://$(me.url):$(me.port)"; verbose=true) do ws
        isWebSocketClosed = false
        while !isWebSocketClosed
            msg = take!(me.messageChannel)

            @info "WebsocketTestCaller sending message $(msg))"
            isWebSocketClosed = processMessage(ws, msg)
        end
        # unnecessary
        # close(ws)
    end
end 

function processMessage(ws, msg) 
    if WebSocket.isopen(ws)
        error("Unknown message type received! Got : $(typeof(msg))")
    else
        return true
    end
end
processMessage(ws, ::WebSocketOpen) = error("Got WebSocketOpen message from an opened websocket!")
processMessage(ws, ::WebSocketClose) = false

function processMessage(ws, msg::WebSocketSend)
    #TODO marshalling
    @debug "WebsocketTestCaller sending message $(msg.data)"
    write(ws, msg.data)
    return true
end


function Circo.onmessage(me::WebSocketCallerActor, msg::WebSocketMessage, service)
    @debug "Message arrived $(typeof(msg))"
    put!(me.messageChannel, msg)
end


end #module