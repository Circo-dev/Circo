module fs

export NativeFS, FileSystem, FileDescriptor, Open, Read, open, read

using ..Circo
using Circo.MultiTask
using Circo.DistributedIdentities, Circo.DistributedIdentities.Reference, Circo.IdRegistry
using Plugins

const FS_REGISTRY_PREFIX = "_fs."

abstract type FileSystem <: Plugin end

mutable struct NativeFS <: FileSystem
    basedir::String
    endpoint::Addr
    helper
    NativeFS(idservice; fs_basedir = ".", options...) = new(fs_basedir)
end
Plugins.symbol(::FileSystem) = :fs
Plugins.deps(::Type{NativeFS}) = [DistIdService]
__init__() = Plugins.register(NativeFS)

@actor struct NativeFSActor
    registry::Addr
    NativeFSActor() = new()
end

Circo.schedule_start(fs::FileSystem, scheduler) = begin
    fs.helper = NativeFSActor()
    fs.endpoint = spawn(scheduler, fs.helper)
    registername(scheduler.service, "fs", fs.endpoint)
end

struct FileDescriptor
    id::UInt64
end

struct Open <: Request
    token::Token
    opener::Addr
    path::String
    mode::String
    Open(opener, path, mode) = new(Token(), opener, path, mode)
end
struct Opened <: Response
    token::Token
    descriptor::FileDescriptor
    ref::IdRef
end
@response Open Opened

struct _FileDescriptor
    id::UInt64
    opener::Addr
    path::String
    mode::String
    io::IOStream
    #_FileDescriptor(id, opener, path, mode, io) = new(id, opener, path, mode, io)
end

mutable struct File <: Actor{Any}
    path::String
    descriptors::Dict{FileDescriptor, _FileDescriptor}
    @distid_field
    eventdispatcher
    core
    File(path) = new(path, Dict())
end
DistributedIdentities.identity_style(::Type{File}) = DenseDistributedIdentity()

@onspawn NativeFSActor begin
    me.registry = getname(service, IdRegistry.REGISTRY_NAME)
    @assert !isnothing(me.registry)
end

@onmessage Open => NativeFSActor begin
    if contains(msg.mode, "w") # create
        file = File(msg.path)
        @spawn file
        @send RegisterIdentity(me, FS_REGISTRY_PREFIX * msg.path, IdRef(file, emptycore(service))) => me.registry
        @send msg => file
    else
        registryresponse = awaitresponse(service, me, me.registry, # TODO error handling
            RegistryQuery(me, FS_REGISTRY_PREFIX * msg.path)
        )
        @send msg => @spawn registryresponse.ref
    end
end

@onmessage Open => File begin
    open(msg.path, msg.mode) do io
        filedescriptor = FileDescriptor(rand(UInt64))
        me.descriptors[filedescriptor] = _FileDescriptor(filedescriptor.id, msg.opener, msg.path, msg.mode, io)
        @send Opened(msg.token, filedescriptor, ref(service, me)) => msg.opener
    end
end

struct Read <: Request
    token::Token
    descriptor::FileDescriptor
    nb::Integer
    Read(descriptor::FileDescriptor; nb=typemax(Int)) = new(Token(), descriptor, nb)
end
struct Data <: Response
    token::Token
    data::Vector{UInt8}
    Data(token, data) = new(token, data)
end
@response Read Data

@onmessage Read => File begin
    read(me.descriptors[msg.descriptor].io; nb=msg.nb) do data
        @send Data(data) => msg.descriptor.opener
    end
end

end #module
