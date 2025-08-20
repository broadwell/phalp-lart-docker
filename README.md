# Running inference with the MIME-specific versions of PHALP and LART in a Docker container

Although for a long it was impressively easy to run inference via PHALP and LART on a Linux (typically Ubuntu) machine with a fairly recent CUDA vintage using only a couple of conda environments, eventually the march of time and Linux distributions caused some virtualization via Docker to be necessary.

The Dockerfile in this repository defines a container that can run both the MIME-inflected versions of PHALP and LART -- at least until Nvidia retires the base container image -- and the `process_video.sh` script is the entrypoint for the PHALP and LART inference tasks in the container. 

Creating the Docker container, assuming Docker is installed on the host system, should simply involve running the following command after cloning this repo and `cd`ing into the folder:

`$ docker build -t ubuntu-phalp .`

The other files in this repo are scripts to be run on the host that have quite different degrees of complexity, but the same goal: running inference with both PHALP and LART on a set of video files using the Docker environment. `docker_commands.sh` provides sample incantations (though the paths may need to be updated to suit your own host system), while `batch_phalp_processor_timing.sh` is more complex but also provides many more automation, optimization and monitoring capabilities.
