using Test
using Circo, Circo.Http
import Circo:onmessage, onspawn

mutable struct HttpTestCaller <: Actor{Any}
    core::Any
    requestsent::Bool
    responsearrived::Bool
    reqidsent::Integer
    reqidarrived::Integer

    HttpTestCaller() = new()
end

function Circo.onspawn(me::HttpTestCaller, service)
    me.requestsent = false
    me.responsearrived = false
    me.reqidsent = 12
    me.reqidarrived = 0

    httpactor = getname(service, "httpclient")
    request = HttpRequest(me.reqidsent, addr(me), "GET", "http://localhost:8080/test")
    
    address = addr(me)
    println("Actor with address $address sending httpRequest with httpRequestId :  $(request.id) message to $httpactor")
    me.requestsent = true
    send(service, me, httpactor, request)
end

function Circo.onmessage(me::HttpTestCaller, msg::HttpResponse, service)
    address = addr(me)
    println("Actor with address $address got httpResponse message with httpRequestId : $(msg.reqid)")
    me.responsearrived = true
    me.reqidarrived = msg.reqid

    println(service.scheduler.msgqueue)
    die(service, me)
end

# @testset "Httpclient" begin
    tester = HttpTestCaller()
    ctx = CircoContext(target_module=@__MODULE__, userpluginsfn=() -> [HttpClient])
    scheduler = Scheduler(ctx, [tester])
    scheduler(;exit=true)
    Circo.shutdown!(scheduler)
    println("After circo.shutdown! $(scheduler.msgqueue)")

    @test tester.requestsent == true
    @test tester.responsearrived == true
    @test tester.reqidsent == tester.reqidarrived
# end