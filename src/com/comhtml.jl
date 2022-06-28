using Gumbo

function fromhtml(htmlstring)
    parsed = parsehtml(htmlstring)
    body = parsed.root[2]
    @assert tag(body) == :body
    @assert length(body.children) == 1
    return nodize(body.children[1])
end

function nodize(elem)
    childelems = filter(e -> e isa Gumbo.HTMLElement, children(elem))
    return Node(String(tag(elem)), attrs(elem), map(nodize, childelems))
end
