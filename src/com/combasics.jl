import AbstractTrees

"""
    Node

    A non-vitalized, but possibly instantiated component.
    This is the assembly descriptor that is used before and during instantiation to generate the actor tree.
"""
mutable struct Node
    tagname::String
    attrs::Dict{String, String}
    childnodes::Vector{Node}
    instance
    Node(tagname) = new(tagname, Dict(), [])
    Node(tagname, attrs, childnodes) = new(tagname, attrs, childnodes)
    Node(tagname, childnodes; attrs...) = new(tagname, attrs, childnodes)
end

AbstractTrees.children(n::Node) = n.childnodes
AbstractTrees.nodevalue(n::Node) = (n.tagname, n.attrs)

function initattrs(component, attrs)
  component.attrs = attrs
end

function oninstantiate(component, childnodes) end

"""
    Child(tagname::String, attrs::Dict{String, String}, addr:: Addr)

    Represent a child of a vitalized component.
"""
struct Child
    tagname::String
    attrs::Dict{String, String}
    addr::Addr
end

function instantiate(node::Node)
    type = getcomponent(node.tagname)
    component = type()
    component.children = Child[]
    node.instance = component
    initattrs(component, node.attrs)
    oninstantiate(component, node.childnodes)
    for childnode in node.childnodes
        instantiate(childnode)
    end
    return component
end

function onvitalize(component, service) end
function onchildbirth(component, child, service) end

function vitalize(node::Node, sdl)
    component = node.instance
    compaddr = spawn(sdl, component)
    onvitalize(component, sdl.service)
    prev = ""
    for childnode in node.childnodes
        childnode.attrs["parent"] = string(compaddr)
        childnode.attrs["prev"] = prev
        push!(component.children, Child(childnode.tagname, childnode.attrs, vitalize(childnode, sdl)))
        onchildbirth(component, childnode, sdl.service)
        prev = string(addr(childnode.instance))
    end
    return compaddr
end
