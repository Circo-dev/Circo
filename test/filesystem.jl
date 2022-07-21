module FSTest

using Test
using Circo
using Circo.MultiTask
using Circo.fs
using Circo.Block

@actor struct FSTester
    FSTester() = new()
end

@onspawn FSTester begin    
    @time for i=1:100
        file = @open("test$i.txt", "w")
        @test file isa FileDescriptor
    
        @write(file, "Hello, world!")
    
        @seek(file, 0)
        data = @read(file)
        @test data == Vector{UInt8}("Hello, world!")    
    end
    die(service, me; exit = true)
end

ctx = CircoContext(target_module=@__MODULE__,
    profile = Circo.Profiles.ClusterProfile(),
    userpluginsfn = () -> [NativeFS, MultiTaskService])
tester = FSTester()
sdl = Scheduler(ctx, [])
sdl(;remote=false)
spawn(sdl, tester)
sdl(;remote=false)
Circo.shutdown!(sdl)

end # module
