module Debug

using ..Circo

export Run, Step, Stop, MsgStats

struct Run
    a::UInt8
    Run(a) = new(a)
    Run() = new(42)
end
struct Step
     a::UInt8
     Step(a) = new(a)
     Step() = new(42)
 end
struct Stop
    a::UInt8
    Stop(a) = new(a)
    Stop() = new(42)
end

for command in (Run, Step, Stop)
    registermsg(command; ui = true)
end

include("msgstats.jl")

end
