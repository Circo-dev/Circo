# Introducing Circo

Circo is a decentralized actor system which is fast, scalable and extensible.

- *Fast:* Up to 630 million msg/sec on a single node [^singlenode]. Up to 20 million msg/sec single threaded performance.
- *Scalable:* Includes a decentralized cluster manager to avoid single point of failure.
- *Extensible:* Build on top of a custom-made [plugin system](https://github.com/tisztamo/Plugins.jl) which allows inlining of plugin code into the main event loop. [Multithreading](https://github.com/Circo-dev/Circo/blob/master/src/host.jl) is a plugin. [Actor migration](https://github.com/Circo-dev/Circo/blob/master/src/migration.jl) is a plugin. Even last-mile message [delivery](https://github.com/Circo-dev/CircoCore.jl/blob/master/src/onmessage.jl) is a plugin. If something is not a plugin, that's a bug.

Circo also features *Infoton Optimization*, a physics-inspired solution to the data-locality problem. [^infoton]

Circo is implemented in [Julia](https://julialang.org) - an incredibly fast, dynamic, yet compiled language -, and it has a JavaScript sister: [Circo.js](https://github.com/Circo-dev/Circo.js), which can run in the browser and transparently integrate into the Circo cluster. These two components form a high performance, distributed application platform.

There is a monitoring tool named "Camera Diserta" which can help to tune Circo applications and to research
Infoton Optimization.

Please note that Circo is in alpha stage. It is more like a research tool at the time than a mature platform. The documentation is also far from complete. Contributions are welcome!

[^singlenode]: Measured on an AWS C6g 16xlarge instance, 64 Graviton 2 ARM core. See [maxthroughput.jl](https://github.com/Circo-dev/CircoCore.jl/blob/master/benchmark/maxthroughput.jl)
[^infoton]: Go to [Infoton Optimization](./infotons/) for a description of this novel algorithm.
