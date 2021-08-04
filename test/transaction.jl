# SPDX-License-Identifier: MPL-2.0

using Test
using Circo
using Circo.Transactions

mutable struct TransactionTester
    prop1::Int
    prop2
end

@testset "Transactions unit tests" begin
    t = TransactionTester(42, Any["X"])
    Transactions.apply!(t, Write(:prop1, 1), nothing)
    @test t.prop1 == 1

    Transactions.apply!(t, Write(:prop2, [42]), nothing)
    @test t.prop2[1] == 42

    Transactions.apply!(t, Write(:prop2, Write(2, 43)), nothing)
    @test t.prop2[2] == 43

    Transactions.apply!(t, Write(:prop2, Write(2:4, [2,3,4])), nothing)
    @test t.prop2 == [42,2,3,4]
    @test t.prop1 == 1
end