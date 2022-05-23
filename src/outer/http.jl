# SPDX-License-Identifier: MPL-2.0
module Http

export HttpRequest, HttpResponse, PrefixRoute, HttpServer, HttpClient

using ..Circo
using Plugins
using HTTP
import HTTP, Sockets
using Logging

HttpReqId = UInt64
Base.@kwdef struct HttpRequest
    id::HttpReqId = rand(HttpReqId)
    respondto::Addr
    target::String
    method::String = "GET"
    headers::Vector{Pair{String,String}} = []
    body
    keywordargs::NamedTuple = NamedTuple()   # used by HTTP.request() function. This isn't used server side. 

end

struct HttpResponse
    reqid::HttpReqId
    status::Int16
    headers::Vector{Pair{String,String}}
    body::Vector{UInt8}
end

include("httpclient.jl")
include("httpserver.jl")

__init__() = begin 
    Plugins.register(HttpServerImpl)
    Plugins.register(HttpClientImpl)
end

end #module