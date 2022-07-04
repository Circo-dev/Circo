module COMBasicTests

using Test

using Circo, Circo.COM

abstract type TestComponent <: Actor{Any} end

mutable struct Root <: TestComponent
    attrs::Dict{String, String}
    children::Vector{Child}
    core
    Root() = new()
end
define("test-root", Root)

mutable struct Inner <: TestComponent
    attrs::Dict{String, String}
    children::Vector{Child}
    core
    Inner() = new()
end
define("test-inner", Inner)

mutable struct Leaf <: TestComponent
    attrs::Dict{String, String}
    children::Vector{Child}
    core
    Leaf() = new()
end
define("test-leaf", Leaf)

const vitalized_components = []

Circo.COM.onvitalize(component::TestComponent, service) = begin
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

    @test root.instance.children[1].addr == addr(vitalized_components[2])
    @test root.instance.children[1].tagname == "test-inner"
    @test vitalized_components[2].children[1].addr == addr(vitalized_components[3])
    @test vitalized_components[2].children[1].tagname == "test-leaf"
end

end # module
