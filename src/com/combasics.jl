import AbstractTrees

mutable struct Node
    tagname::String
    attrs::Dict{String, String}
    children::Vector{Node}
    instance
    Node(tagname) = new(tagname, Dict(), [])
    Node(tagname, attrs, children) = new(tagname, attrs, children)
    Node(tagname, children; attrs...) = new(tagname, attrs, children)
end

AbstractTrees.children(n::Node) = n.children
AbstractTrees.nodevalue(n::Node) = (n.tagname, n.attrs)

function initattrs(component, attrs)
  component.attrs = attrs
end

function oninstantiate(component, children) end

function instantiate(node::Node)
    type = getcomponent(node.tagname)
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
