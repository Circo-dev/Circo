module COMHTMLTests
using Test
using Circo, Circo.COM

mutable struct SampleBackend <: Actor{Any}
    children
    attrs
    core
    SampleBackend() = new()
end
define("sample-backend", SampleBackend)

mutable struct FirstService <: Actor{Any}
    children
    attrs
    core
    FirstService() = new()
end
define("first-service", FirstService)

mutable struct SecondService <: Actor{Any}
    children
    attrs
    core
    SecondService() = new()
end
define("second-service", SecondService)

mutable struct InnerComponent <: Actor{Any}
    children
    attrs
    core
    InnerComponent() = new()
end
define("inner-component", InnerComponent)

@testset "comhtml" begin
    prog = fromhtml("""
        <sample-backend target="mycluster">
            <first-service></first-service>
            <second-service>
                <inner-component id="1"></inner-component>
                <inner-component id="2"></inner-component>
            </second-service>
        </sample-backend>
    """)

    @test typeof(prog) == Node
    @test prog.tagname == "sample-backend"
    @test prog.attrs["target"] == "mycluster"
    @test length(prog.children) == 2
    @test prog.children[1].tagname == "first-service"
    @test prog.children[2].tagname == "second-service"
    @test length(prog.children[2].children) == 2
    @test prog.children[2].children[1].tagname == "inner-component"
    @test prog.children[2].children[1].attrs["id"] == "1"
    @test prog.children[2].children[2].tagname == "inner-component"
    @test prog.children[2].children[2].attrs["id"] == "2"

    instantiate(prog)

    sdl = Scheduler(CircoContext(target_module=@__MODULE__))
    vitalize(prog, sdl)
end

end # module
