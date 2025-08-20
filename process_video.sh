#!/bin/bash

# This is the entry point to the ubuntu-phalp Docker environment and should not be run manually

# Shouldn't doing this in the Dockerfile be sufficient? Apparently not.
source activate phalp
conda activate phalp
conda run -n phalp ln -sf /usr/lib/x86_64-linux-gnu/libstdc++.so.6 ${CONDA_PREFIX}/lib/libstdc++.so.6
ln -sf /app/inout /app/LART/outputs

if [ $1 = "lart" ]; then
  cd /app/LART
  echo "Running LART on pickle file $2 using frames in /app/inout/_DEMO/video_basename_stem/img/"
  conda run -n phalp python scripts/infer_on_pkl.py +pkl_path="/app/inout/$2" video.output_dir="/app/inout/"
elif [ $1 = "phalp" ]; then
  cd /app/PHALP
  echo "Running PHALP on video file $2"
  conda run -n phalp python scripts/infer.py video.source="/app/inout/$2" render.enable=false video.output_dir="/app/inout"
else
  echo "Usage: process_video.sh [phalp|lart] [input_filename]"
fi 
