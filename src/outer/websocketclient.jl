# SPDX-License-Identifier: MPL-2.0
module WebsocketClient

export WebSocketCallerActor, WebSocketMessage, WebSocketClose, WebSocketOpen, WebSocketSend, WebSocketResponse

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
    source              #sender Actor Addr
end

struct WebSocketOpen <: WebSocketMessage
    source              #sender Actor Addr
end

struct WebSocketResponse
    request::WebSocketMessage
    response
end

mutable struct WebSocketCallerActor <: Actor{Any}
    core::Any
    url
    port
    messageChannel::Channel{}

    WebSocketCallerActor(core, url, port) = new(core, url, port, Channel{}(2))
end

function Circo.onmessage(me::WebSocketCallerActor, openmsg::WebSocketOpen, service)
    @async WebSockets.open("ws://$(me.url):$(me.port)"; verbose=true) do ws

        @debug "Client Websocket connection established!"
        Circo.send(service, me, openmsg.source, WebSocketResponse(openmsg, "Websocket connection established!"))

        isWebSocketClosed = false
        while !isWebSocketClosed
            msg = take!(me.messageChannel)

            @debug "WebsocketTestCaller sending message $(msg))"
            (isWebSocketClosed, response) = processMessage(me, ws, msg)
            
            # TODO marshalling?
            response = String(response)
            Circo.send(service, me, msg.source, WebSocketResponse(msg, response))
        end
        # unnecessary
        # close(ws)
    end
end 

function processMessage(me, ws, msg) 
    if WebSocket.isopen(ws)
        error("Unknown message type received! Got : $(typeof(msg))")
    else
        return (true, missing)
    end
end
processMessage(me, ws, ::WebSocketOpen) = error("Got WebSocketOpen message from an opened websocket!")
processMessage(me, ws, ::WebSocketClose) = (true, "Websocket connection closed")

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
    put!(me.messageChannel, msg)
end


end #module