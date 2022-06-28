"""
    COM Component Object Model

An actor-based component model inspired by web components

"""
module COM

using ..Circo

export define, instantiate, vitalize, fromhtml, Node

include("localcomponentregistry.jl")
include("combasics.jl")
include("comhtml.jl")

end # module
