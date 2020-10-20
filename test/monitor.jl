# SPDX-License-Identifier: MPL-2.0
module TokenTest

using Test
using Circo
import Circo: monitorprojection

mutable struct EmptyActor <: Actor{Any}
    core
    EmptyActor() = new()
end

mutable struct MonitorTester <: Actor{Any}
    core
    MonitorTester() = new()
end

const PROJECTION = JS("{
    geometry: new THREE.BoxBufferGeometry(1, 1, 1),
    scale: { x: .42, y: 1, z: 1 }
}")
monitorprojection(::Type{MonitorTester}) = PROJECTION

@testset "Monitor" begin
    empty = EmptyActor()
    @test typeof(monitorprojection(typeof(empty))) === JS

    tester = MonitorTester()
    @test monitorprojection(typeof(tester)) === PROJECTION
end

end
