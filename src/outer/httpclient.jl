# SPDX-License-Identifier: MPL-2.0

abstract type HttpClient <: Plugin end
Plugins.symbol(plugin::HttpClient) = :httpclient

mutable struct HttpClientActor <: Actor{Any} 
    core::Any
    HttpClientActor() = new()
end

mutable struct HttpClientImpl <: HttpClient
    helper::HttpClientActor
    HttpClientImpl(;options...) = new()
end

function Circo.schedule_start(http::HttpClientImpl, scheduler)
    http.helper = HttpClientActor()
    spawn(scheduler.service, http.helper)
    registername(scheduler.service, "httpclient", http.helper)

    address = addr(http.helper)
    println("HttpClientActor.addr : $address")
end

function Circo.onmessage(me::HttpClientActor, msg::HttpRequest, service)
    println("HttpClientActor Actor with address : $(addr(me)) got message!")
    @async begin
        response = HTTP.request(msg.raw.method, msg.raw.target, msg.raw.headers, msg.raw.body; 
        connection_limit=30 
        # , connect_timeout = 0
        , retry = false
        )
        println("HTTP.request returned to HttpClientActor")
        address = msg.respondto
        println("Sending HttpResponse message to $address")
        
        ownresponse = HttpResponse(msg.id, response.status, response.headers, response.body)
        send(service.scheduler, address , ownresponse)
    end
end