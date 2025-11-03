FROM nvidia/cuda:12.1.0-devel-ubuntu22.04

SHELL ["/bin/bash", "-c"]

WORKDIR /app
RUN apt-get update && \
    apt-get install -y wget build-essential vim git libgl1 libgl1-mesa-glx libgl1-mesa-dri libglib2.0-0 libegl1 libglu1 && \
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /miniconda.sh && \
    bash /miniconda.sh -b -p /opt/conda && \
    rm /miniconda.sh && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/conda/bin:$PATH"
ENV CUDA_HOME="/usr/local/cuda"
ENV CI="true"

COPY . /app/

RUN mkdir /usr/lib/dri && ln -s /usr/lib/x86_64-linux-gnu/dri/swrast_dri.so /usr/lib/dri/

RUN conda
RUN conda create -n phalp python=3.10 mkl=2023.*
RUN echo "source activate phalp" > /root/.bashrc
ENV PATH="/opt/conda/envs/phalp/bin:$PATH"

RUN source /root/.bashrc
RUN conda init
RUN source activate phalp

RUN conda run -n phalp conda install -y ninja pytorch==2.1.1 torchvision==0.16.1 pytorch-cuda=12.1 -c pytorch -c nvidia

ENV HOME="/app"

# If building from an empty folder, may need to copy some other files around...
RUN git clone -b mime-version --single-branch https://github.com/broadwell/LART.git
RUN git clone -b mime-version --single-branch https://github.com/broadwell/PHALP.git

RUN cd /app/LART && TORCH_CUDA_ARCH_LIST="8.6 8.7 8.9" conda run -n phalp pip install -e .[demo]

RUN cd /app/PHALP && TORCH_CUDA_ARCH_LIST="8.6 8.7 8.9" conda run -n phalp pip install -e .[all]

RUN cd /app && wget https://huggingface.co/spaces/brjathu/HMR2.0/resolve/e5201da358ccbc04f4a5c4450a302fcb9de571dd/data/smpl/basicModel_neutral_lbs_10_207_0_v1.0.0.pkl

# One of these cp commands probably isn't necessary...
RUN cp /app/basicModel_neutral_lbs_10_207_0_v1.0.0.pkl /app/PHALP/. && \
    mkdir -p /app/PHALP/data && cp /app/basicModel_neutral_lbs_10_207_0_v1.0.0.pkl /app/PHALP/data/.

RUN if [ -f "/app/.cache/4DHumans/logs/train/multiruns/hmr2/0/checkpoints/epoch=35-step=1000000.ckpt" ]; then conda run -n phalp python -m pytorch_lightning.utilities.upgrade_checkpoint /app/.cache/4DHumans/logs/train/multiruns/hmr2/0/checkpoints/epoch=35-step=1000000.ckpt; fi

ENTRYPOINT ["/app/process_video.sh"]
CMD ["phalp_or_lart", "source_file"]
