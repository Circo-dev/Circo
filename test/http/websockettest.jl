using Test
using HTTP, HTTP.WebSockets
using Sockets
using Circo, Circo.WebsocketClient
using Logging

import Circo.send

struct StartTestMsg
    message
    url
end

struct VerificationMsg
end

mutable struct WebSocketTestActor <: Actor{Any}
    core
    websocketcaller::WebSocketCallerActor
    receivedmessages::AbstractArray
    expectedmessages::AbstractArray
    websocketid::UInt32
    message

    WebSocketTestActor(core, wscaller, expectedmessages) = new(core, wscaller, [], expectedmessages)
end

msgdata = "Random message"


function Circo.onmessage(me::WebSocketTestActor, msg::StartTestMsg, service)
    me.message = msg.message
    openmsg = WebSocketOpen(addr(me), msg.url)

    send(service, me, me.websocketcaller, openmsg)
end

function Circo.onmessage(me::WebSocketTestActor, msg::WebSocketResponse, service)
    @debug "Circo.onmessage(me::WebSocketTestActor, msg::WebSocketResponse, service)" msg.response
    push!(me.receivedmessages, msg)
    processmessage(me, msg, msg.request, service)
end

function processmessage(me::WebSocketTestActor, response::WebSocketResponse, ::WebSocketOpen, service)
    me.websocketid = UInt64(response.websocketid)
    
    sendmsg = WebSocketSend(me.message, addr(me), missing, me.websocketid)
    closeMsg = WebSocketClose(addr(me), me.websocketid)

    send(service, me, me.websocketcaller, sendmsg)
    send(service, me, me.websocketcaller, closeMsg)
end

function processmessage(me::WebSocketTestActor, response::WebSocketResponse, ::WebSocketSend, service)
end

function processmessage(me::WebSocketTestActor, response::WebSocketResponse, ::WebSocketClose, service)
    #TODO die
end

function clientSideVerification(me::WebSocketTestActor, msg::VerificationMsg)
    @test size(me.receivedmessages) == size(me.expectedmessages)

    for i in 1:size(me.receivedmessages, 1)
        @test me.receivedmessages[i].response == me.expectedmessages[i]
    end
end


mutable struct VerificationData
    messagereceived::Bool
    websocketservercloses::Bool
    receivedmessages

    VerificationData() = new(false, false, [])
end

mutable struct TestServer
    tcpserver
    servertask
    waitForServerClose
    serverVerificationData
end

function createWebsocketServer(url, port)
    tcpserver = listen(port)

    waitForServerClose = false
    
    testServer = TestServer(tcpserver, missing, waitForServerClose, VerificationData())
    testServer.servertask = createWebsocketServer(testServer, url, port)
    return testServer
end

function createWebsocketServer(testserver::TestServer, url, port)
    @async WebSockets.listen(url, port; server=testserver.tcpserver, verbose=true) do ws
        @test ws.request isa HTTP.Request
        for msg in ws 
            data = String(msg)
            @debug "Server got this : $data"
            HTTP.send(ws, "Server send this : $data")
            
            testserver.serverVerificationData.messagereceived = true
            push!(testserver.serverVerificationData.receivedmessages, data)
        end
        @debug "Server start to close"
        testserver.serverVerificationData.websocketservercloses = true
        testserver.waitForServerClose = true
    end
end

function serverSideVerification(actuall::VerificationData, expectedMessages)
    @test actuall.websocketservercloses == true
    @test actuall.messagereceived == true

    @info "actuall received msgs" actuall.receivedmessages
    @info "expected received msgs" expectedMessages 

    for index in 1:size(actuall.messagereceived, 1) 
        @test actuall.receivedmessages[index] == expectedMessages[index]
    end
    
    @test size(actuall.receivedmessages) == size(expectedMessages)
end

function waitWithChannelTake(testserver::TestServer, timeout)
    sleep(timeout)
    return testserver.waitForServerClose
end

function closeWithTest(testServer::TestServer)
    close(testServer.tcpserver)
    @test timedwait(()-> testServer.servertask.state === :done, 5.0) === :ok
end


@testset "WebSockets" begin
    @testset "Testing sending message not from f(ws)" begin
        port = UInt16(8086)
        url = "127.0.0.1"

        testServer = createWebsocketServer(url, port)
        
        messageChannel = Channel{}(2)
        
        @async WebSockets.open("ws://$(url):$(port)"; verbose=true) do ws
            HTTP.send(ws, "Client send message!")
            msg = HTTP.receive(ws)
            @debug "Client side" , String(msg)

            @debug "Client wait for external message"
            msg = take!(messageChannel)
            HTTP.send(ws, "Client : $msg")

            @debug "Client closing"
        end

        msg = "Client send something"
        put!(messageChannel, msg)

        @test waitWithChannelTake(testServer, 10.0)
        serverSideVerification(testServer.serverVerificationData, [
            "Client send message!"
            , "Client : $(msg)"
        ])

        closeWithTest(testServer)
    end

    @testset "Testing with Circo actor" begin
        port = UInt16(8086)
        url = "127.0.0.1"

        testServer = createWebsocketServer(url, port)
        
        ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [])
        websocketCaller = WebSocketCallerActor(emptycore(ctx))
        testActor = WebSocketTestActor(emptycore(ctx)
            , websocketCaller
            , [
                "Websocket connection established!"
                , "Server send this : $(msgdata)"
                , "Websocket connection closed"
            ]
        )

        scheduler = Scheduler(ctx, [websocketCaller, testActor])
        scheduler(;remote=false, exit=true) # to spawn the zygote

        send(scheduler, testActor, StartTestMsg(msgdata, "$(url):$(port)"))

        scheduler(;remote=false, exit=true)

        @test waitWithChannelTake(testServer, 10.0)

        # TODO temporary because we need to process websocket reponse messages
        scheduler(;remote=false, exit=true)

        serverSideVerification(testServer.serverVerificationData, [
            msgdata
        ])

        clientSideVerification(testActor, VerificationMsg())

        closeWithTest(testServer)
        Circo.shutdown!(scheduler)
    end
end
