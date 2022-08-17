using Test
using HTTP, HTTP.WebSockets
using Sockets
using Circo, Circo.WebsocketClient
using Logging

include("../helper/testactors.jl");
import .TestActors: Puppet, msgcount, msgs

import Circo.send

struct StartTestMsg
    message::String
    url
end

mutable struct WebSocketTestActor <: Actor{Any}
    core
    receivedmessages::AbstractArray
    expectedmessages::AbstractArray
    errorevent::Vector
    websocketcaller
    websocketid::UInt32
    message

    WebSocketTestActor(core, expectedmessages) = new(core, [], expectedmessages, [])
end

function Circo.onmessage(me::WebSocketTestActor, msg::StartTestMsg, service)
    me.websocketcaller = getname(service, "websocketclient")
    me.message = msg.message
    openmsg = WebSocketOpen(addr(me), msg.url)

    send(service, me, me.websocketcaller, openmsg)
end

function Circo.onmessage(me::WebSocketTestActor, response::OpenEvent, service)
    @info "Circo.onmessage openEvent" response
    push!(me.receivedmessages, response)

    me.websocketid = UInt64(response.websocketid)

    sendmsg = WebSocketSend(me.message, addr(me), missing, me.websocketid)
    send(service, me, me.websocketcaller, sendmsg)
    # NOTE Sending close messsage right after sending WebSocketSend may cause scheduling problem. It caused the WebSocketCallerActor read messages full of "/0" 
end

function Circo.onmessage(me::WebSocketTestActor, response::MessageEvent, service)
    @debug "Cliens sending close"
    push!(me.receivedmessages, response)

    closeMsg = WebSocketClose(addr(me), me.websocketid)
    send(service, me, me.websocketcaller, closeMsg)
end

function Circo.onmessage(me::WebSocketTestActor, response::CloseEvent, service)
    @info "Circo.onmessage(me::WebSocketTestActor, ::CloseEvent, service)"
    push!(me.receivedmessages, response)

    @test size(me.receivedmessages) == size(me.expectedmessages)

    @debug "Client received messages" me.receivedmessages
    @debug "Client received messages" map(x -> String(copy(x.response)), me.receivedmessages)
    @debug "Client expected messages" me.expectedmessages

    for i in eachindex(me.receivedmessages)
        @test String(me.receivedmessages[i].response) == me.expectedmessages[i]
    end

    die(service, me; exit = true)
end

function Circo.onmessage(me::WebSocketTestActor, response::ErrorEvent, service)
    @info "we got ErrorEvent" response
    push!(me.errorevent, response)
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
    wait_for_server_close
    server_verification_data
end

function create_websocket_server(url, port)
    tcpserver = listen(port)

    waitForServerClose = false

    testServer = TestServer(tcpserver, missing, waitForServerClose, VerificationData())
    testServer.servertask = create_websocket_server(testServer, url, port)
    return testServer
end

function create_websocket_server(testserver::TestServer, url, port)
    @async WebSockets.listen(url, port; server=testserver.tcpserver, verbose=true) do ws
        @test ws.request isa HTTP.Request
        try
        for msg in ws
            data = String(msg)
                
            responsemessage = "Server send this : $data"
            @debug responsemessage
            testserver.server_verification_data.messagereceived = true
            push!(testserver.server_verification_data.receivedmessages, data)

                if data == "Send error"
                    @info "Sending \"Unexpected\" error"
                    error(responsemessage)
                else 
                    HTTP.send(ws, responsemessage)
        end
            end
        finally
        @debug "Server start to close"
        testserver.server_verification_data.websocketservercloses = true
        testserver.wait_for_server_close = true
        end
    end
end

function serverside_verification(testServer::TestServer, expectedMessages)
    actual = testServer.server_verification_data
    @test timedwait(() -> testServer.wait_for_server_close == true, 5.0) === :ok

    @test actual.websocketservercloses == true
    @test actual.messagereceived == true

    @debug "Server actuall received msgs" actual.receivedmessages
    @debug "Server expected received msgs" expectedMessages

    for index in 1:size(actual.messagereceived, 1)
        @test actual.receivedmessages[index] == expectedMessages[index]
    end

    @test size(actual.receivedmessages) == size(expectedMessages)
end

function close_with_test(testserver::TestServer)
    close(testserver.tcpserver)
    @test timedwait(() -> testserver.servertask.state === :done, 5.0) === :ok
end

function verify_websocket_clientactor(scheduler)
    websocketcalleraddr = getname(scheduler.service, "websocketclient")
    websocketcaller = getactorbyid(scheduler, websocketcalleraddr.box)
    @test isempty(websocketcaller.messageChannels)
end

@testset "WebSockets" begin
    msgdata = "Random message"
    protocol = "ws://"
    url = "127.0.0.1"

    @testset "Testing sending message not from f(ws)" begin
        @info "Testing sending message not from f(ws)"
        port = UInt16(8086)

        testserver = create_websocket_server(url, port)
        try 
        messagechannel = Channel{}(2)
        closingsignal = Channel{}(2)

            @async WebSockets.open("$(protocol)$(url):$(port)"; verbose=true) do ws
            HTTP.send(ws, "Client send message!")
            msg = HTTP.receive(ws)
            @debug "Client side", String(msg)

            @debug "Client wait for external message"
            msg = take!(messagechannel)
            HTTP.send(ws, "Client : $msg")

            msg = take!(messagechannel)
            HTTP.send(ws, "Client : $msg")
            put!(closingsignal, true)
            @debug "Client closing"
        end

        put!(messagechannel, msgdata)
        put!(messagechannel, Vector{UInt8}(msgdata))

        @test take!(closingsignal)

        serverside_verification(testserver, [
            "Client send message!", "Client : $(msgdata)", "Client : $(msgdata)"
        ])

        finally
        close_with_test(testserver)
    end
    end

    @testset "Testing with Circo actor" begin
        @info "Testing with Circo actor"
        port = UInt16(8086)

        testserver = create_websocket_server(url, port)
        try
            ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [WebSocketClient])
            testactor = WebSocketTestActor(emptycore(ctx), [
                    "Websocket connection established!", "Server send this : $(msgdata)", "Websocket connection closed"
                ]
            )

            scheduler = Scheduler(ctx, [testactor])
            scheduler(;remote=false)

            send(scheduler, testactor, StartTestMsg(msgdata, "$(protocol)$(url):$(port)"))
            scheduler(;remote=true)

            @test findfirst(x -> typeof(x) == CloseEvent && x.status == 1000, testactor.receivedmessages) !== nothing
            @test isempty(testactor.errorevent)

            serverside_verification(testserver, [
                msgdata
            ])

            verify_websocket_clientactor(scheduler)
            Circo.shutdown!(scheduler)
        finally
            close_with_test(testserver)
        end

    end

    @testset "Testing with multiple connection" begin
        @info "Testing with multiple connection"
        portOne = UInt16(8086)
        portTwo = UInt16(8087)

        testServerOne = create_websocket_server(url, portOne)
        testServerTwo = create_websocket_server(url, portTwo)
        try
            msgdataTwo = "Different message"

            ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [WebSocketClient])
            testActorOne = WebSocketTestActor(emptycore(ctx), [
                    "Websocket connection established!", "Server send this : $(msgdata)", "Websocket connection closed"
                ]
            )
            testActorTwo = WebSocketTestActor(emptycore(ctx), [
                    "Websocket connection established!", "Server send this : $(msgdataTwo)", "Websocket connection closed"
                ]
            )

            scheduler = Scheduler(ctx, [testActorOne, testActorTwo])
            scheduler(;remote=false) # to spawn the zygote

            send(scheduler, testActorOne, StartTestMsg(msgdata,  "$(protocol)$(url):$(portOne)"))
            send(scheduler, testActorTwo, StartTestMsg(msgdataTwo,  "$(protocol)$(url):$(portTwo)"))

            scheduler(;remote=true)

            @test findfirst(x -> typeof(x) == CloseEvent && x.status == 1000, testActorOne.receivedmessages) !== nothing
            @test isempty(testActorOne.errorevent)

            @test findfirst(x -> typeof(x) == CloseEvent && x.status == 1000, testActorTwo.receivedmessages) !== nothing
            @test isempty(testActorTwo.errorevent)


            serverside_verification(testServerOne, [
                msgdata
            ])
            serverside_verification(testServerTwo, [
                msgdataTwo
            ])

            verify_websocket_clientactor(scheduler)
            Circo.shutdown!(scheduler)
        finally   
          close_with_test(testServerOne)
          close_with_test(testServerTwo)
        end
    end

    @testset "Testing simple error() ErrorEvent" begin
        @info "Testing simple error() ErrorEvent"
        port = UInt16(8086)
        errormsg = "Send error"
        testserver = create_websocket_server(url, port)
        try
            ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [WebSocketClient])
            testactor = WebSocketTestActor(emptycore(ctx), [
                "Websocket connection established!",
                "Unexpected server websocket error"
                ])

            scheduler = Scheduler(ctx, [testactor])
            scheduler(;remote=false)

            send(scheduler, testactor, StartTestMsg(errormsg, "$(protocol)$(url):$(port)"))
            scheduler(;remote=true)

            @test findfirst(x -> typeof(x) == CloseEvent && x.status > 1000, testactor.receivedmessages) !== nothing
            @test isempty(testactor.errorevent)

            serverside_verification(testserver, [errormsg])

            verify_websocket_clientactor(scheduler)
            Circo.shutdown!(scheduler)
        finally
            close_with_test(testserver)
        end
        
    end

    @testset "Testing with Circo actor" begin
        @info "Testing with Circo actor"
        port = UInt16(8086)

        testserver = create_websocket_server(url, port)
        try
            ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [WebSocketClient])
            puppet = TestActors.Puppet()
            scheduler = Scheduler(ctx, [puppet])
            scheduler(;remote=false)

            send(scheduler, puppet, StartTestMsg(msgdata, "$(protocol)$(url):$(port)"))
            @async scheduler(;remote=true)

            websocketcalleraddr = getname(scheduler.service, "websocketclient")
            websocketcaller = getactorbyid(scheduler, websocketcalleraddr.box)

            send(scheduler, puppet, WebSocketSend("Something unrelevant", addr(puppet), missing, rand(UInt32)))
            
            errorevent = get(puppet.msgs, ErrorEvent, missing)
            @test errorevent === missing


            Circo.shutdown!(scheduler)
        finally
            close_with_test(testserver)
        end

    end
end
