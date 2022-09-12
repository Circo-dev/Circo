module Tape

export Recorder

using Plugins
using Circo
using Circo.Marshal

mutable struct Recorder <: Plugin
    outputfilename::String
    fileio::Union{Nothing, IOStream}
    Recorder(; recorder_outputfilename = "circo.rec", options...) = new(recorder_outputfilename, nothing)
end
__init__() = Plugins.register(Recorder)
Circo.symbol(::Recorder) = :recorder


@inline Circo.localdelivery(recorder::Recorder, scheduler, msg, targetactor) = begin
    open_file_if_needed(recorder)
    buf = marshal(msg)
    seek(buf, 0)
    write(recorder.fileio, buf)
    return false
end

Circo.schedule_stop(recorder::Recorder, scheduler) = begin
    if !isnothing(recorder.fileio)    
        close(recorder.fileio)
        recorder.fileio = nothing
    end
    return false
end

function open_file_if_needed(recorder::Recorder)
    if isnothing(recorder.fileio)
        recorder.fileio = open(recorder.outputfilename; write = true, truncate = true)
    end
end

end # module
