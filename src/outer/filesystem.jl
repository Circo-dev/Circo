module fs

export NativeFS, FileSystem, FileDescriptor, @open, @read, @write, @seek, @close

using ..Circo
using Circo.MultiTask
using Circo.DistributedIdentities, Circo.DistributedIdentities.Reference, Circo.IdRegistry
using Circo.Transactions
using Plugins

const FS_REGISTRY_PREFIX = "_fs."

abstract type FileSystem <: Plugin end

mutable struct NativeFS <: FileSystem
    fs_basedir::String # Local fs mount point to use as root
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
    @assert me.path == msg.path
    open_local_file(me)
    handle = FileHandle(rand(UInt64))
    @send Opened(msg.token, handle, ref(service, me), 0) => msg.opener
end

function open_local_file(me)
    if !isnothing(me.io)
        return me.io
    end
    me.io = Base.open("$(string(box(me), base=16))_" * me.path; read=true, write=true, create=true, truncate=false, append=false)
    return me.io
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
    open_local_file(me)
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
    commit!(me, Transactions.SubArrayWrite(msg.position, 0, msg.data), service)
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

function Transactions.apply!(me::File, write::Transactions.SubArrayWrite, service)
    open_local_file(me)
    Base.seek(me.io, write.fromidx)
    Base.write(me.io, write.value)
end

struct Close <: Request
    token::Token
    handle::FileHandle
    respondto::Addr
    Close(descriptor::FileDescriptor, respondto) = new(Token(), descriptor.handle, respondto)
end
struct Closed
    token::Token
end
@response Close Closed

struct CloseTr <: Transactions.Write
    handle::FileHandle
end

@onmessage Close => File begin
    commit!(me, CloseTr(msg.handle), service)
    @send Closed(msg.token) => msg.respondto
end

function Transactions.apply!(me::File, write::CloseTr, service)
    if !isnothing(me.io)
        Base.close(me.io)
        me.io = nothing
    end
end

function close(service, me, descriptor)
    return awaitresponse(service, me, descriptor.ref, Close(descriptor, me))
end

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

macro close(descriptor)
    return quote
        Circo.fs.close(service, me, $descriptor)
    end |> esc
end

using Circo.Monitor
peerbox(peer) = !isnothing(peer.addr) ? (Symbol("peer$(Int(peer.addr.box % 1000))"), peer.addr.box) : (:p, nothing)
Circo.monitorextra(me::File) = begin
    peers = map(peerbox, values((me.distid.peers)))
    return (
        path = me.path,
        peers...
    )
end
Circo.monitorprojection(::Type{<:File}) = JS("{
    geometry: new THREE.BoxBufferGeometry(25, 25, 25),
    color: 0x00dddd,
}")

end #module
