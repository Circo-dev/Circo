module fs

export NativeFS, FileSystem, FileDescriptor, open, read

using Circo
using Circo.MultiTask
using Circo.DistributedIdentities, Circo.DistributedIdentities.Reference
using Plugins

abstract type FileSystem <: Plugin end

mutable struct NativeFS <: FileSystem
    endpoint::Addr
    helper
    NativeFS(;options...) = new()
end

__init__() = Plugins.register(NativeFS)
Plugins.symbol(::FileSystem) = :fs

# TODO @typedactor NativeFSActor
mutable struct NativeFSActor{TCore} <: Actor{TCore}
    core::TCore
    NativeFSActor(core) = new(Dict(), core)
end

Circo.schedule_start(fs::FileSystem, scheduler) = begin
    fs.helper = NativeFSActor(emptycore(scheduler.service))
    fs.endpoint = @spawn fs.helper
    registername("fs", fs.endpoint)
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
    reference::IdRef
    Opened(token, descriptor) = new(token, descriptor)
end
@response Open Opened

@actor struct File
    @distid_field
    path::String
    descriptors::Dict{FileDescriptor, _FileDescriptor}
    core::TCore
    File() = new()
    File(id) = new(id)
end
DistributedIdentities.identity_style(::Type{File}) = DenseDistributedIdentity()

struct _FileDescriptor
    id::UInt64
    opener::Addr
    mode::String
    io::IOStream
    _FileDescriptor(id, opener, path, mode, io) = new(id, opener, path, mode, io)
end

@onspawn NativeFSActor begin
    me.registry = getname(sdl.service, IdRegistry.REGISTRY_NAME)
    @assert !isnothing(registery)
end

@onmessage Open => NativeFSActor begin
    @send RegistryQuery(addr(tester), IDREG_TEST_KEY) => me.registry
end

@onmessage Open => File begin
    open(msg.path, msg.mode) do io
        filedescriptor = FileDescriptor(msg.opener)
        me.descriptors[filedescriptor] = _FileDescriptor(rand(UInt64), msg.opener, msg.path, msg.mode, io)
        @send filedescriptor => msg.respondto
    end
end

struct Create <: Request
    opener::Addr
    path::String
    Create(opener, path) = new(opener, path)
end

struct Read <: Request
    token::Token
    descriptor::FileDescriptor
    nb::Integer
    Read(descriptor::FileDescriptor; nb=typemax(Int)) = new(Token(), descriptor, nb)
end
struct Data <: Response
    data::Vector{UInt8}
    Data(data) = new(data)
end
@response Read Data

@onmessage Read => File begin
    read(me.descriptors[msg.descriptor].io; nb=msg.nb) do data
        @send Data(data) => msg.descriptor.opener
    end
end

end #module
