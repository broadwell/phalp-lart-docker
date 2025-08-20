#!/bin/bash

# This is to be run on the Docker host (outside the ubuntu-phalp environment)

# Instructions for running PHALP are below.
# To run LART via the Docker image on one or more .phalp.pkl files, those input files
# must already be in the inout/results/ folder. Also, the per-video frames folders generated
# by PHALP (usually in PHALP/output/_DEMO/) must have been copied to the inout/_DEMO/ folder.

for f in `cat list_of_filenames.txt`
  do
    fb=`basename $f .mp4`
    echo "Processing file for $f $fb"
    # To run PHALP on a video file (which must be in the inout/) folder, just do
    docker run --gpus all -v inout:/app/inout ubuntu-phalp phalp $f
    # This runs LART on the PHALP pkl file generated from a video file. It will look for it
    # in the inout/results/ folder that is created by PHALP
    # docker run --gpus all -v inout:/app/inout ubuntu-phalp lart $f.phalp.pkl
  done
