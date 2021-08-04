# SPDX-License-Identifier: MPL-2.0
using Jive

runtests(@__DIR__, skip=["coverage/", "cluster/clusterdebug.jl"])
