using Test
using HTTP, HTTP.WebSockets
using Sockets
using Circo, Circo.WebsocketClient
using Logging

import Circo.send

struct StartTestMsg
end

struct VerificationMsg
end

mutable struct WebSocketTestActor <: Actor{Any}
    core
    websocketcaller::WebSocketCallerActor
    receivedmessages::AbstractArray
    expectedmessages::AbstractArray

    WebSocketTestActor(core, wscaller, expectedmessages) = new(core, wscaller, [], expectedmessages)
end

msgdata = "Random message"


function Circo.onmessage(me::WebSocketTestActor, ::StartTestMsg, service)
    openmsg = WebSocketOpen(addr(me))
    sendmsg = WebSocketSend(msgdata, addr(me), missing)
    closeMsg = WebSocketClose(addr(me))

    send(service, me, me.websocketcaller, openmsg)
    send(service, me, me.websocketcaller, sendmsg)
    send(service, me, me.websocketcaller, closeMsg)
end

function Circo.onmessage(me::WebSocketTestActor, msg::WebSocketResponse, service)
    @debug "Circo.onmessage(me::WebSocketTestActor, msg::WebSocketResponse, service)" msg.response
    push!(me.receivedmessages, msg)
end

# receivedmessages need to be tested. We got the expected messages or just somthing stupid
function Circo.onmessage(me::WebSocketTestActor, msg::VerificationMsg, service)
    @test size(me.receivedmessages, 1) == 3

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

function createWebsocketServer(verificationData, url, port, tcpserver, waitForServerCloseChannel)
    @async WebSockets.listen(url, port; server=tcpserver, verbose=true) do ws
        @test ws.request isa HTTP.Request
        for msg in ws 
            data = String(msg)
            @debug "Server got this : $data"
            HTTP.send(ws, "Server send this : $data")
            
            verificationData.messagereceived = true
            push!(verificationData.receivedmessages, data)
        end
        @debug "Server start to close"
        verificationData.websocketservercloses = true
        put!(waitForServerCloseChannel, true)
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

        @test take!(waitForServerClose)
        serverSideVerification(verificationData, [
            "Client send message!"
            , "Client : $(msg)"
        ])

        close(tcpserver)
        @test timedwait(()->servertask.state === :done, 5.0) === :ok
    end

    @testset "Testing with Circo actor" begin
        serverVerificationData = VerificationData()

        port=UInt16(8086)
        tcpserver = listen(port)
        url = "127.0.0.1"

        waitForServerClose = Channel{}(2)

        servertask = createWebsocketServer(serverVerificationData, url, port, tcpserver, waitForServerClose)

        ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [])
        websocketCaller = WebSocketCallerActor(emptycore(ctx), url, port)
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

        send(scheduler, testActor, StartTestMsg())

        scheduler(;remote=false, exit=true)

        @test take!(waitForServerClose)

        serverSideVerification(serverVerificationData, [
            msgdata
        ])

        send(scheduler, testActor, VerificationMsg())
        scheduler(;remote=false, exit=true)

        close(tcpserver)
        @test timedwait(()->servertask.state === :done, 5.0) === :ok
        Circo.shutdown!(scheduler)
    end
end
