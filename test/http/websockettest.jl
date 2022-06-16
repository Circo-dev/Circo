using Test
using HTTP
using HTTP.IOExtras, HTTP.Sockets, HTTP.WebSockets
using Sockets
using Circo.Marshal


# @testset "WebSockets" begin
    # @testset "Testing sending message not from f(ws)" begin
        port=UInt16(8086)
        tcpserver = listen(port)

        messageChannel = Channel{}(2)
        websocketChannel = Channel{}(2)
        waitForServerClose = Channel{}(2)

        servertask =  @async WebSockets.listen("127.0.0.1", port; server=tcpserver, verbose=true) do ws
            @test ws.request isa HTTP.Request
            while !eof(ws)
                data = readavailable(ws)
                println("Server hez ért : $(String(data))")
                write(ws, "Server hez ért : ", String(data))
            end
            println("Servernek kiírt mindent szóval close")
            put!(waitForServerClose, true)
        end

        @async WebSockets.open("ws://127.0.0.1:$(port)"; verbose=true) do ws
            put!(websocketChannel, ws)
            println("Client megjött, send message!")

            write(ws, "Client megjött, send message!")
            msg = readavailable(ws)
            println("Clients oldal" , String(msg))

            println("Clients2 Várunk még üzenetre")
            msg = take!(messageChannel)
            write(ws, "Clients2 $msg")
            println("Clients2 Bevárt üzenet elküldve")

            println("Most már elég, client oldal close-ol")
        end

        readmsg = "Mit is küldjünk"
        websocket = take!(websocketChannel)
        println(typeof(websocket))

        msg2 = "Client3 $readmsg"
        println(msg2)
        put!(messageChannel, msg2)

        serverReachedClose = take!(waitForServerClose)
        @test serverReachedClose

        close(tcpserver)
        @test timedwait(()->servertask.state === :failed, 5.0) === :ok
        @test_throws Exception wait(servertask)
#     end
# end
