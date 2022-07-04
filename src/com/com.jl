"""
    COM Component Object Model

An actor-based component model inspired by web components

"""
module COM

using ..Circo

export define,
    instantiate, vitalize,
    Child,
    sub,
    fromasml, Node

include("localcomponentregistry.jl")
include("combasics.jl")
include("comhtml.jl")
include("pubsub.jl")

end # module
