# Circo

![Lifecycle](https://img.shields.io/badge/lifecycle-experimental-blue.svg)
[![CI](https://github.com/Circo-dev/Circo/actions/workflows/ci.yml/badge.svg)](https://github.com/Circo-dev/Circo/actions/workflows/ci.yml)
<!--[![codecov.io](http://codecov.io/github/Circo-dev/Circo/coverage.svg?branch=master)](http://codecov.io/github/Circo-dev/Circo?branch=master)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://Circo-dev.github.io/Circo.jl/stable)-->
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://Circo-dev.github.io/Circo-docs/dev)


A fast, scalable and extensible actor system.

- *Fast:* Up to 630 million msg/sec on a single node [^singlenode]. Up to 20 million msg/sec single threaded performance.
- *Scalable:* Includes a decentralized cluster manager to avoid single point of failure.
- *Extensible:* Built on top of a custom-made [plugin system](https://github.com/tisztamo/Plugins.jl) which allows inlining of plugin code into the main event loop. [Multithreading](https://github.com/Circo-dev/Circo/blob/master/src/host.jl) is a plugin. [Actor migration](https://github.com/Circo-dev/Circo/blob/master/src/migration.jl) is a plugin. Even last-mile message [delivery](https://github.com/Circo-dev/CircoCore.jl/blob/master/src/onmessage.jl) is a plugin. If something is not a plugin, that's a bug.

Circo also features *Infoton Optimization*, a physics-inspired solution to the data-locality problem (See the [paper](http://publikacio.uni-eszterhazy.hu/7010/1/AMI_53_from271to282.pdf)).

Circo is implemented in [Julia](https://julialang.org) - an incredibly fast, dynamic, yet compiled language -, and it has a JavaScript sister: [Circo.js](https://github.com/Circo-dev/Circo.js), which can run in the browser and transparently integrate into the Circo cluster. These two components form a high performance, distributed application platform.

There is a monitoring tool named "Camera Diserta" which can help to tune Circo applications and to research
Infoton Optimization.

Please note that Circo is in alpha stage. It is more like a research tool at the time than a mature platform. The documentation is also far from complete. Contributions are welcome!

## Published Papers

- [Exploiting the structure of communication in actor systems](http://publikacio.uni-eszterhazy.hu/7010/1/AMI_53_from271to282.pdf)


[^singlenode]: Measured on an AWS C6g 16xlarge instance, 64 Graviton2 Arm core. See [maxthroughput.jl](https://github.com/Circo-dev/CircoCore.jl/blob/master/benchmark/maxthroughput.jl)

