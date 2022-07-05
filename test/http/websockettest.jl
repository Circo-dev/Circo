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

mutable struct WebSocketTestActor <: Actor{Any}
    core
    receivedmessages::AbstractArray
    expectedmessages::AbstractArray
    websocketcaller
    websocketid::UInt32
    message

    WebSocketTestActor(core, expectedmessages) = new(core, [], expectedmessages)
end

function Circo.onmessage(me::WebSocketTestActor, msg::StartTestMsg, service)
    me.websocketcaller = getname(service, "websocketclient")
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

processmessage(::WebSocketTestActor, ::WebSocketResponse, ::WebSocketSend, service) = nothing

function processmessage(me::WebSocketTestActor, ::WebSocketResponse, ::WebSocketClose, service)
    @test size(me.receivedmessages) == size(me.expectedmessages)

    for i in 1:size(me.receivedmessages, 1)
        @test me.receivedmessages[i].response == me.expectedmessages[i]
    end

    die(service, me)
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

function serverSideVerification(testServer::TestServer, expectedMessages)
    actual = testServer.serverVerificationData
    @test timedwait(()-> testServer.waitForServerClose == true, 10.0) === :ok

    @test actual.websocketservercloses == true
    @test actual.messagereceived == true

    @info "actuall received msgs" actual.receivedmessages
    @info "expected received msgs" expectedMessages 

    for index in 1:size(actual.messagereceived, 1) 
        @test actual.receivedmessages[index] == expectedMessages[index]
    end
    
    @test size(actual.receivedmessages) == size(expectedMessages)
end

function closeWithTest(testServer::TestServer)
    close(testServer.tcpserver)
    @test timedwait(()-> testServer.servertask.state === :done, 5.0) === :ok
end

function verifyWebSocketClientActor(scheduler)
    websocketcalleraddr = getname(scheduler.service, "websocketclient")
    websocketcaller = getactorbyid(scheduler, websocketcalleraddr.box)
    @test isempty(websocketcaller.messageChannels)
end

@testset "WebSockets" begin
    msgdata = "Random message"
    url = "127.0.0.1"

    @testset "Testing sending message not from f(ws)" begin
        port = UInt16(8086)

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

        put!(messageChannel, msgdata)

        serverSideVerification(testServer, [
            "Client send message!"
            , "Client : $(msgdata)"
        ])

        closeWithTest(testServer)
    end

    @testset "Testing with Circo actor" begin
        port = UInt16(8086)

        testServer = createWebsocketServer(url, port)
        
        ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [WebSocketClient])
        testActor = WebSocketTestActor(emptycore(ctx)
            , [
                "Websocket connection established!"
                , "Server send this : $(msgdata)"
                , "Websocket connection closed"
            ]
        )

        scheduler = Scheduler(ctx, [testActor])
        scheduler(;remote=false, exit=true) # to spawn the zygote

        send(scheduler, testActor, StartTestMsg(msgdata, "$(url):$(port)"))

        scheduler(;remote=true, exit=true)

        serverSideVerification(testServer, [
            msgdata
        ])

        verifyWebSocketClientActor(scheduler)

        closeWithTest(testServer)
        Circo.shutdown!(scheduler)
    end
    
    @testset "Testing with multiple connection" begin
        portOne = UInt16(8086)
        portTwo = UInt16(8087)

        testServerOne = createWebsocketServer(url, portOne)
        testServerTwo = createWebsocketServer(url, portTwo)

        msgdataTwo = "Different message" 

        ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [WebSocketClient])
        testActorOne = WebSocketTestActor(emptycore(ctx)
            , [
                "Websocket connection established!"
                , "Server send this : $(msgdata)"
                , "Websocket connection closed"
            ]
        )
        testActorTwo = WebSocketTestActor(emptycore(ctx)
            , [
                "Websocket connection established!"
                , "Server send this : $(msgdataTwo)"
                , "Websocket connection closed"
            ]
        )

        scheduler = Scheduler(ctx, [testActorOne, testActorTwo])
        scheduler(;remote=false, exit=true) # to spawn the zygote

        send(scheduler, testActorOne, StartTestMsg(msgdata, "$(url):$(portOne)"))
        send(scheduler, testActorTwo, StartTestMsg(msgdataTwo, "$(url):$(portTwo)"))

        scheduler(;remote=true, exit=true)

        serverSideVerification(testServerOne, [
            msgdata
        ])
        serverSideVerification(testServerTwo, [
            msgdataTwo
        ])

        verifyWebSocketClientActor(scheduler)

        closeWithTest(testServerOne)
        closeWithTest(testServerTwo)
        Circo.shutdown!(scheduler)
    end
end
