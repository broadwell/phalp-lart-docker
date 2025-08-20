# Running inference with the MIME-specific versions of PHALP and LART in a Docker container

For the first couple of years after their release, it was impressively easy to run inference via [PHALP](https://github.com/brjathu/PHALP) and [LART](https://github.com/brjathu/LART) on a Linux (typically Ubuntu 22.04) system with a fairly recent CUDA vintage using only a couple of conda environments. Lately, the relentless march of time and Linux distributions has made it often necessary to configure the environment to use somewhat outdated libraries (e.g., of CUDA, PyTorch), so virtualization via Docker is now frequently the best solution.

The Dockerfile in this repository defines a container that can run both the [MIME](https://github.com/sul-cidr/mime)-specific versions of [PHALP](https://github.com/broadwell/PHALP/tree/mime-version) and [LART](https://github.com/broadwell/LART/tree/mime-version) -- at least until Nvidia retires the [container image](https://hub.docker.com/layers/nvidia/cuda/12.1.0-devel-ubuntu22.04/images/sha256-da7476bffce34d8dd3e84a7db3f221fd4b14ee3a0a83c508cafe113b6b5c0e1b) -- and the `process_video.sh` script is the entrypoint for the PHALP and LART inference tasks in the container. 

Creating the Docker container, assuming Docker is installed on the host system, should simply involve running the following command after cloning this repo and `cd`ing into the folder:

`$ docker build -t ubuntu-phalp .`

The other files in this repo are scripts to be run on the host that have quite different degrees of complexity, but the same goal: running inference with both PHALP and LART on a set of video files using the Docker environment.
- `docker_commands.sh` provides sample incantations for running each tool; you'll want to check the comments and host system file paths it refers to in order to make it work.
- `batch_phalp_processor_timing.sh` is more complex but also provides many more automation, optimization and monitoring capabilities.
