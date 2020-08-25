# Installation

## Requirements

- Linux or OSX 
- Julia >= v"1.4" [download](https://julialang.org/)
- git (Tested with "version 2.17.1") [download](https://git-scm.com/download/linux)
- Node.js (Tested with "v12.4.0") [download](https://nodejs.org/en/download/) - For the optional frontend

## Install & run a sample

You need to checkout two repos: The [Circo](https://github.com/Circo-dev/Circo) "backend" and the [CircoCore.js](https://github.com/Circo-dev/CircoCore.js) "frontend".

**In terminal #1 (backend)**

```bash
git clone https://github.com/Circo-dev/Circo.git
cd Circo/
julia --project -e 'using Pkg;Pkg.instantiate()'
bin/circonode.sh --threads 6 --zygote
```

This starts a local (in-process) cluster with six schedulers running the sample project.

**In terminal #2 (monitoring frontend, optional)**

```bash
git clone https://github.com/Circo-dev/CircoCore.js.git
cd CircoCore.js
npm install
npm run serve
```

This starts a web server on port 8000. Open [http://localhost:8000](http://localhost:8000)
