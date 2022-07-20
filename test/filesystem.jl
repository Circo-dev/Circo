module FSTest

using Test
using Circo
using Circo.MultiTask
using Circo.fs

@actor struct FSTester
    FSTester() = new()
end

@onspawn FSTester begin
    @show awaitresponse(service, me,
        getname(service, "fs"),
        Open(me, "alma.txt", "w"),
    )
end

ctx = CircoContext(target_module=@__MODULE__,
    profile = Circo.Profiles.ClusterProfile(),
    userpluginsfn = () -> [NativeFS, MultiTaskService])
tester = FSTester()
sdl = Scheduler(ctx, [
    tester
])
sdl(;remote=false)
Circo.shutdown!(sdl)

end # module