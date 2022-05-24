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
    @debug "HttpClientActor.addr : $address"
end

function Circo.onmessage(me::HttpClientActor, msg::HttpRequest, service)
    @debug "HttpClientActor Actor with address : $(addr(me)) got message!"

    @async begin
        response = nothing
        try 
            if length(msg.keywordargs) > 0
                response = HTTP.request(msg.method, msg.target, msg.headers, msg.body; 
                    msg.keywordargs... ,
                    connection_limit = 30 
                    , retry = false
                    , status_exception = false
                )

            else
                response = HTTP.request(msg.method, msg.target, msg.headers, msg.body; 
                    connection_limit=30 
                    , retry = false
                    , status_exception = false
                )

            end
        catch e
            @error "Error when initiating HTTP request!" e
        end

        @debug "HTTP.request returned to HttpClientActor" response
        address = msg.respondto
        @debug "Sending HttpResponse message to $address"
        
        ownresponse = HttpResponse(msg.id, response.status, response.headers, response.body)
        send(service, me, address , ownresponse)
    end
end