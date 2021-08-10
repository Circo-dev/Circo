# SPDX-License-Identifier: MPL-2.0
using Jive

# To run specific tests:
# julia --project=. -e 'using Pkg; Pkg.test(;test_args=["identity"])'

runtests(@__DIR__, skip=["coverage/", "cluster/clusterdebug.jl"])
