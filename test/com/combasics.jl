module COMBasicTests

using Test

using Circo, Circo.COM
import Circo.COM.oninstantiate
import Circo.COM.onvitalize

abstract type TestComponent <: Actor{Any} end

mutable struct Root <: TestComponent
    attrs::Dict{String, String}
    children::Vector{Addr}
    core
    Root() = new()
end
define("test-root", Root)

mutable struct Inner <: TestComponent
    attrs::Dict{String, String}
    children::Vector{Addr}
    core
    Inner() = new()
end
define("test-inner", Inner)

mutable struct Leaf <: TestComponent
    attrs::Dict{String, String}
    children::Vector{Addr}
    core
    Leaf() = new()
end
define("test-leaf", Leaf)

const vitalized_components = []

function onvitalize(component::TestComponent, service)
    push!(vitalized_components, component)
end

@testset "COM basics" begin
    ctx = CircoContext(target_module=@__MODULE__)
    sdl = Scheduler(ctx)

    root = Node("test-root", Dict(["rootx" => "root42"]), [
        Node("test-inner", [
            Node("test-leaf")
        ])
    ])

    empty!(vitalized_components)
    instantiate(root)
    rootaddr = vitalize(root, sdl)
    sdl(;exit=true, remote=false)
    @test typeof(vitalized_components[1]) == Root
    @test typeof(vitalized_components[2]) == Inner
    @test typeof(vitalized_components[3]) == Leaf

    @test root.instance.children[1] == addr(vitalized_components[2])
    @test vitalized_components[2].children[1] == addr(vitalized_components[3])
end

end # module