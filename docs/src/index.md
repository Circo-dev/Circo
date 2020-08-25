# Introducing Circo

Circo is a decentralized actor system that is fast, scalable and extensible. 
It features *Infoton Optimization*, a physics-inspired solution to the data-locality problem. [^1]

Circo is implemented in [Julia](https://julialang.org) - an incredibly fast, dynamic yet compiled language -, and it has a JavaScript sister: [Circo.js](https://github.com/Circo-dev/Circo.js), which can run in the browser and transparently integrate into the Circo cluster. These two components form a high performance, distributed application platform.

There is a monitoring tool named "Camera Diserta" which can help to tune Circo applications and to research
Infoton Optimization.

Please note that Circo is in alpha stage, it is more like a research tool at the time than a mature platform. The documentation is also far from complete. Contributions are welcome!

[^1]: Go to [Infoton Optimization](./infotons/) for a description of this novel algorithm.