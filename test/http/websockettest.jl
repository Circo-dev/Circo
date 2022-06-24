using Test
using HTTP, HTTP.WebSockets
using Sockets
using Circo, Circo.WebsocketClient
using Logging

mutable struct VerificationData
    messagereceived::Bool
    websocketservercloses::Bool
    receivedmessages

    VerificationData() = new(false, false, [])
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
        testCaller = WebSocketCallerActor(emptycore(ctx), url, port)

        scheduler = Scheduler(ctx, [testCaller])
        scheduler(;remote=false, exit=true) # to spawn the zygote


        openmsg = WebSocketOpen()
        msgdata = "Random message"
        sendmsg = WebSocketSend(msgdata, addr(testCaller), missing)
        closeMsg = WebSocketClose()

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
