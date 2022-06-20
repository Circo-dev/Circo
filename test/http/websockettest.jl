using Test
using HTTP
using HTTP.IOExtras, HTTP.Sockets, HTTP.WebSockets
using Sockets
using Circo, Circo.Marshal
using Logging

import Circo:onmessage, onspawn

struct WebsocketMessage 
    data
    # origin
    # lastEventId 
    source              #sender Actor Addr
    ports               #websocket client actor addr
end

struct WebsocketClose
end

struct WebsocketOpen
end

mutable struct WebsocketTestCaller <: Actor{Any}
    core::Any
    url
    port
    messageChannel::Channel{}

    WebsocketTestCaller(core, url, port) = new(core, url, port, Channel{}(2))
end

function Circo.onmessage(me::WebsocketTestCaller, msg::WebsocketOpen, service)
    @debug "Creating WebsocketTestCaller"
    @async WebSockets.open("ws://$(me.url):$(me.port)"; verbose=true) do ws
        while true
            msg = take!(me.messageChannel)

            # TODO use multi dispact and Base.isopen method
            if msg isa WebsocketClose
                break
            elseif msg isa WebsocketMessage
                #TODO marshalling
                @debug "WebsocketTestCaller sending message $(msg.data)"
                write(ws, msg.data)
            end
        end
        # unnecessary
        # close(ws)
    end
end 

function Circo.onmessage(me::WebsocketTestCaller, msg::WebsocketMessage, service)
    @debug "Message arrived $(typeof(msg))"
    put!(me.messageChannel, msg)
end

function Circo.onmessage(me::WebsocketTestCaller, msg::WebsocketClose, service)
    @debug "Message arrived $(typeof(msg))"
    put!(me.messageChannel, msg)
end


function createWebsocketServer(url, port, tcpserver, waitForServerCloseChannel)
    @async WebSockets.listen(url, port; server=tcpserver, verbose=true) do ws
        @test ws.request isa HTTP.Request
        while !eof(ws)
            data = readavailable(ws)
            @debug "Server got this : $(String(data))"
            write(ws, "Server got this : ", String(data))
        end
        @debug "Server start to close"
        put!(waitForServerCloseChannel, true)
    end
end

@testset "WebSockets" begin

    @testset "Testing sending message not from f(ws)" begin
        port=UInt16(8086)
        tcpserver = listen(port)
        url = "127.0.0.1"

        messageChannel = Channel{}(2)
        waitForServerClose = Channel{}(2)

        servertask = createWebsocketServer(url, port, tcpserver, waitForServerClose)

        @async WebSockets.open("ws://$(url):$(port)"; verbose=true) do ws
            write(ws, "Client send message!")
            msg = readavailable(ws)
            @debug "Client side" , String(msg)

            @debug "Client wait for external message"
            msg = take!(messageChannel)
            write(ws, "Client : $msg")

            @debug "Client closing"
        end

        put!(messageChannel, "Client send something")

        @test take!(waitForServerClose)

        close(tcpserver)
        @test timedwait(()->servertask.state === :failed, 5.0) === :ok
        @test_throws Exception wait(servertask)
    end

    @testset "Testing with Circo actor" begin
        port=UInt16(8086)
        tcpserver = listen(port)
        url = "127.0.0.1"

        waitForServerClose = Channel{}(2)

        servertask =  createWebsocketServer(url, port, tcpserver, waitForServerClose)

        ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [])
        testCaller = WebsocketTestCaller(emptycore(ctx), url, port)

        scheduler = Scheduler(ctx, [testCaller])
        scheduler(;remote=false, exit=true) # to spawn the zygote


        openmsg = WebsocketOpen()
        message = WebsocketMessage("Random message", addr(testCaller), missing)
        closeMsg = WebsocketClose()

        Circo.send(scheduler, testCaller, openmsg)
        Circo.send(scheduler, testCaller, message)
        Circo.send(scheduler, testCaller, closeMsg)

        scheduler(;remote=false, exit=true)

        @test take!(waitForServerClose)

        close(tcpserver)
        @test timedwait(()->servertask.state === :failed, 5.0) === :ok
        @test_throws Exception wait(servertask)

        Circo.shutdown!(scheduler)
    end
end
