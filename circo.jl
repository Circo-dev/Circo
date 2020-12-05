# Default CircoCore script.
# Overwrite this file with your program or set CIRCO_INITSCRIPT environment variable before starting the node/cluster

#include("examples/linkedlist.jl")

zygote(ctx) = []
plugins(;options...) = [Debug.MsgStats(;options...), HttpService(;options...)]
profile(;options...) = Circo.Profiles.DefaultProfile(;options...)

