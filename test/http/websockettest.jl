using Test
using HTTP
using HTTP.IOExtras, HTTP.Sockets, HTTP.WebSockets
using Sockets
using Circo, Circo.Marshal
using Logging

import Circo:onmessage, onspawn

abstract type WebsocketMessage 
end

struct WebsocketSend <: WebsocketMessage
    data
    # origin
    # lastEventId 
    source              #sender Actor Addr
    ports               #websocket client actor addr
end

struct WebsocketClose <: WebsocketMessage
end

struct WebsocketOpen <: WebsocketMessage
end

mutable struct VerificationData
    messagereceived::Bool
    websocketservercloses::Bool
    receivedmessages

    VerificationData() = new(false, false, [])
end

mutable struct WebsocketTestCaller <: Actor{Any}
    core::Any
    url
    port
    messageChannel::Channel{}

    WebsocketTestCaller(core, url, port) = new(core, url, port, Channel{}(2))
end

function Circo.onmessage(me::WebsocketTestCaller, openmsg::WebsocketOpen, service)
    @debug "Message arrived $(typeof(openmsg))"
    @async WebSockets.open("ws://$(me.url):$(me.port)"; verbose=true) do ws
        iswebsocketclosed = false
        while !iswebsocketclosed
            msg = take!(me.messageChannel)

            @info "WebsocketTestCaller sending message $(msg))"
            iswebsocketclosed = processMessage(ws, msg)
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
processMessage(ws, ::WebsocketOpen) = error("Got WebsocketOpen message from an opened websocket!")
processMessage(ws, ::WebsocketClose) = false

function processMessage(ws, msg::WebsocketSend)
    #TODO marshalling
    @debug "WebsocketTestCaller sending message $(msg.data)"
    write(ws, msg.data)
    return true
end


function Circo.onmessage(me::WebsocketTestCaller, msg::WebsocketMessage, service)
    @debug "Message arrived $(typeof(msg))"
    put!(me.messageChannel, msg)
end

function createWebsocketServer(verificationData, url, port, tcpserver, waitForServerCloseChannel)
    @async WebSockets.listen(url, port; server=tcpserver, verbose=true) do ws
        @test ws.request isa HTTP.Request
        while !eof(ws)
            data = String(readavailable(ws))
            @debug "Server got this : $data"
            write(ws, "Server got this : $data")
            
            verificationData.messagereceived = true
            push!(verificationData.receivedmessages, data)
        end
        @debug "Server start to close"
        verificationData.websocketservercloses = true
        put!(waitForServerCloseChannel, true)
    end
end

function verification(actuall::VerificationData, expectedMessages)
    @test actuall.websocketservercloses == true
    @test actuall.messagereceived == true

    for index in 1:size(actuall.messagereceived, 1) 
        @test actuall.receivedmessages[index] == expectedMessages[index]
    end
    
    @test size(actuall.receivedmessages) == size(expectedMessages)
end

@testset "WebSockets" begin

    @testset "Testing sending message not from f(ws)" begin
        verificationData = VerificationData()

        port=UInt16(8086)
        tcpserver = listen(port)
        url = "127.0.0.1"

        messageChannel = Channel{}(2)
        waitForServerClose = Channel{}(2)

        servertask = createWebsocketServer(verificationData, url, port, tcpserver, waitForServerClose)

        @async WebSockets.open("ws://$(url):$(port)"; verbose=true) do ws
            write(ws, "Client send message!")
            msg = readavailable(ws)
            @debug "Client side" , String(msg)

            @debug "Client wait for external message"
            msg = take!(messageChannel)
            write(ws, "Client : $msg")

            @debug "Client closing"
        end

        msg = "Client send something"
        put!(messageChannel, "Client send something")

        @test take!(waitForServerClose)
        verification(verificationData, [
            "Client send message!"
            , "Client : $(msg)"
            , "" 
        ])

        close(tcpserver)
        @test timedwait(()->servertask.state === :failed, 5.0) === :ok
        @test_throws Exception wait(servertask)
    end

    @testset "Testing with Circo actor" begin
        verificationData = VerificationData()

        port=UInt16(8086)
        tcpserver = listen(port)
        url = "127.0.0.1"

        waitForServerClose = Channel{}(2)

        servertask = createWebsocketServer(verificationData, url, port, tcpserver, waitForServerClose)

        ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [])
        testCaller = WebsocketTestCaller(emptycore(ctx), url, port)

        scheduler = Scheduler(ctx, [testCaller])
        scheduler(;remote=false, exit=true) # to spawn the zygote


        openmsg = WebsocketOpen()
        msgdata = "Random message"
        sendmsg = WebsocketSend(msgdata, addr(testCaller), missing)
        closeMsg = WebsocketClose()

        Circo.send(scheduler, testCaller, openmsg)
        Circo.send(scheduler, testCaller, sendmsg)
        Circo.send(scheduler, testCaller, closeMsg)

        scheduler(;remote=false, exit=true)

        @test take!(waitForServerClose)

        verification(verificationData, [
            msgdata
            , "" 
        ])

        close(tcpserver)
        @test timedwait(()->servertask.state === :failed, 5.0) === :ok
        @test_throws Exception wait(servertask)

        Circo.shutdown!(scheduler)
    end
end
