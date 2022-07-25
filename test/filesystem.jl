module FSTest

using Test
using Circo
using Circo.MultiTask
using Circo.fs
using Circo.Block

@actor struct FSTester
    cycles::Int
    FSTester(cycles=1) = new(cycles)
end

@onspawn FSTester begin
    @time for i=1:1
        file = @open("test$i.txt", "w")
        @test file isa FileDescriptor
    
        @write(file, "Hello, world!")
    
        @seek(file, 1)
        data = @read(file)
        @test data == Vector{UInt8}("ello, world!")

        @seek(file, 0)
        data = Circo.fs.read(service, me, file; nb = 5)
        @test data == Vector{UInt8}("Hello")

        @close(file)
    end
    if me.cycles > 1
        @spawn FSTester(me.cycles - 1)
    end
    die(service, me; exit = true)
end

ctx = CircoContext(target_module=@__MODULE__,
    profile = Circo.Profiles.ClusterProfile(),
    userpluginsfn = () -> [NativeFS, MultiTaskService])
tester = FSTester(1)
sdl = Scheduler(ctx, [])
sdl(;remote=false)
spawn(sdl, tester)
sdl(;remote=true)
Circo.shutdown!(sdl)

end # module
