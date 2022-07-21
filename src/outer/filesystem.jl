module fs

export NativeFS, FileSystem, FileDescriptor, @open, @read, @write, @seek

using ..Circo
using Circo.MultiTask
using Circo.DistributedIdentities, Circo.DistributedIdentities.Reference, Circo.IdRegistry
using Plugins

const FS_REGISTRY_PREFIX = "_fs."

abstract type FileSystem <: Plugin end

mutable struct NativeFS <: FileSystem
    fs_basedir::String # Local fs
    endpoint::Addr
    helper
    NativeFS(deps...; fs_basedir = ".", options...) = new(fs_basedir)
end
Plugins.symbol(::FileSystem) = :fs
Plugins.deps(::Type{NativeFS}) = [DistIdService, MultiTaskService]
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

# sent over the wire
struct FileHandle
    id::UInt64
end

# Represents an opened file on the client side
mutable struct FileDescriptor
    handle::FileHandle
    ref::Addr
    position::UInt64
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
    handle::FileHandle
    ref::IdRef
    position::UInt64
end
@response Open Opened


mutable struct File <: Actor{Any}
    path::String
    io::Union{IOStream, Nothing}
    @distid_field
    eventdispatcher
    core
    File(path) = new(path, nothing)
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
    if !isnothing(me.io)
        close(me.io)
    end
    Base.open(msg.path, msg.mode) do io
        me.io = io
        handle = FileHandle(rand(UInt64))
        @send Opened(msg.token, handle, ref(service, me), position(io)) => msg.opener
    end
end


function open(service, me, path, mode)
    opened = awaitresponse(service, me,
        getname(service, "fs"),
        Open(me, path, mode),
    )
    return FileDescriptor(opened.handle, (@spawn opened.ref), opened.position)
end

struct Read <: Request
    token::Token
    handle::FileHandle
    position::UInt64
    nb::Integer
    respondto::Addr
    Read(descriptor::FileDescriptor, respondto; nb=typemax(Int)) = new(Token(), descriptor.handle, descriptor.position, nb, respondto)
end
struct Data <: Response
    token::Token
    data::Vector{UInt8}
    nextpos::UInt64
    Data(token, data, nextpos) = new(token, data, nextpos)
end
@response Read Data

@onmessage Read => File begin
    if !isnothing(me.io)
        close(me.io)
    end
    Base.open(me.path, "r") do io
        me.io = io
        execute_read(service, me, msg)
    end
end

function execute_read(service, me, msg)
    seek(me.io, msg.position)
    data = Base.read(me.io, msg.nb)
    @send Data(msg.token, data, position(me.io)) => msg.respondto
end

function read(service, me, descriptor::FileDescriptor; nb=typemax(Int))
    data = awaitresponse(service, me,
        descriptor.ref,
        Read(descriptor, me; nb=nb)
    )
    descriptor.position = data.nextpos
    return data.data
end

struct Write <: Request
    token::Token
    handle::FileHandle
    position::UInt64
    data::Vector{UInt8}
    respondto::Addr
    Write(descriptor::FileDescriptor, data::Vector{UInt8}, respondto) = new(Token(), descriptor.handle, descriptor.position, data, respondto)
end
struct Written <: Response
    token::Token
    nextpos::UInt64
end
@response Write Written

@onmessage Write => File begin
    if isnothing(me.io)
        Base.open(me.path, "w") do io
            me.io = io
            execute_write(service, me, msg)
        end
    else
        execute_write(service, me, msg)
    end
end

function execute_write(service, me, msg)
    seek(me.io, msg.position)
    Base.write(me.io, msg.data)
    @send Written(msg.token, position(me.io)) => msg.respondto
end

function write(service, me, descriptor::FileDescriptor, data::Vector{UInt8})
    data = awaitresponse(service, me,
        descriptor.ref,
        Write(descriptor, data, me)
    )
    bytecount = data.nextpos - descriptor.position
    descriptor.position = data.nextpos
    return bytecount
end

write(service, me, descriptor::FileDescriptor, data::String) =
    write(service, me, descriptor, Vector{UInt8}(data))


macro seek(file, position)
    return quote
        $(file).position = $position
    end |> esc
end

macro open(path, mode)
    return quote
        Circo.fs.open(service, me, $path, $mode)
    end |> esc
end

macro read(descriptor)
    return quote
        Circo.fs.read(service, me, $descriptor)
    end |> esc
end

macro write(descriptor, data)
    return quote
        Circo.fs.write(service, me, $descriptor, $data)
    end |> esc
end

end #module
