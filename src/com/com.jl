"""
    COM Component Object Model

An actor-based component model inspired by web components

"""
module COM

using ..Circo
using Circo.Marshal

export Node, instantiate, vitalize

"""
struct SyntaxError
end

struct QuerySelector
  selectors::String
end

struct QuerySelectorAll
  selectors::String
end
abstract type NodeList <: AbstractVector{Node} end
"""


mutable struct Node
    tagname::String
    attrs::Dict{String, String}
    children::Vector{Node}
    instance
    Node(tagname) = new(tagname, Dict(), [])
    Node(tagname, attrs, children) = new(tagname, attrs, children)
    Node(tagname, children; attrs...) = new(tagname, attrs, children)
end

function initattrs(component, attrs)
  component.attrs = attrs
end

function oninstantiate(component, children) end

const typeregistry = TypeRegistry()

function instantiate(node::Node)
    type = Circo.Marshal.gettype(typeregistry, node.tagname)
    component = type()
    component.children = Addr[]
    node.instance = component
    initattrs(component, node.attrs)
    oninstantiate(component, node.children)
    for child in node.children
        instantiate(child)
    end
    return component
end

function onvitalize(component, service) end

function vitalize(node::Node, sdl)
    component = node.instance
    addr = spawn(sdl, component)
    onvitalize(component, sdl.service)
    for child in node.children
        push!(component.children, vitalize(child, sdl))
    end
    return addr
end

end # module
