# SPDX-License-Identifier: MPL-2.0
using Jive, CircoCore

include("migrate/migrate-base.jl") # TODO: Remove Migrant from Main

# To run specific tests:
# julia --project=. -e 'using Pkg; Pkg.test(;test_args=["identity"])'

runtests(@__DIR__, skip=["coverage/", "cluster/clusterdebug.jl", "http/testclient.jl"])
