# ============================================================================
# DATA-SCIENCE: CUDA, Jupyter, Scientific Computing, Bioinformatics
# ============================================================================
#
# Category-specific layer appended after common-tools.Dockerfile
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Switch to root for package installation
USER root

# Install CUDA Toolkit 13.1
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb \
    && dpkg -i /tmp/cuda-keyring.deb && rm /tmp/cuda-keyring.deb \
    && apt-get update && apt-get install -y \
        cuda-toolkit-13-1 cuda-nvcc-13-1 \
        cuda-libraries-dev-13-1 cuda-cudart-dev-13-1 \
    && rm -rf /var/lib/apt/lists/*

# Install CUDA 12.6 runtime libraries for PyTorch/TensorFlow compatibility
RUN apt-get update && apt-get install -y --no-install-recommends \
        cuda-cudart-12-6 cuda-nvrtc-12-6 \
        libcublas-12-6 libcufft-12-6 libcurand-12-6 \
        libcusparse-12-6 libcusolver-12-6 \
        libnvjitlink-12-6 libcudnn9-cuda-12 \
    && rm -rf /var/lib/apt/lists/*

# Install scientific computing, bioinformatics, and data science dependencies
RUN apt-get update && apt-get install -y \
    libopenblas-dev liblapack-dev libgomp1 \
    libhdf5-dev libnetcdf-dev \
    graphviz ghostscript \
    emboss ncbi-blast+ \
    bowtie2 samtools bcftools \
    bedtools bioperl \
    && rm -rf /var/lib/apt/lists/*

# Install R for statistical computing
RUN apt-get update && apt-get install -y \
    r-base r-base-dev r-recommended \
    && rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/local/cuda/bin:${PATH}:/usr/local/bin:/usr/bin:/bin \
    LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    CUDA_HOME=/usr/local/cuda

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-dev python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install R packages for bioinformatics (phyloseq, etc.) - must be root
RUN R --vanilla -e "install.packages(c('BiocManager', 'tidyverse', 'ggplot2', 'ggmap', 'plotly'), repos='http://cran.r-project.org')" \
    && R --vanilla -e "BiocManager::install(c('phyloseq', 'dada2', 'DESeq2', 'limma', 'edgeR', 'igraph'), ask=FALSE)" \
    && R --vanilla -e "install.packages('vegan', repos='http://cran.r-project.org')"

# Install Miniforge (lightweight conda) as root
RUN wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && \
    rm /tmp/miniforge.sh && \
    /opt/conda/bin/conda clean -afy

ENV PATH="/opt/conda/bin:$PATH"

# Create conda environment with scientific and bioinformatics stack (as root)
RUN conda create -y -n datasci python=3.11 && \
    conda run -n datasci conda install -y -c conda-forge \
    numpy scipy scikit-learn scikit-image \
    pandas polars dask \
    matplotlib seaborn plotly bokeh altair \
    jupyter jupyterlab jupyter-book \
    notebook ipykernel ipywidgets \
    statsmodels sympy networkx \
    nltk gensim spacy \
    biopython pysam pybedtools HTSeq \
    bioconda::samtools bioconda::bcftools bioconda::bedtools \
    && conda clean -afy

# Install PyTorch and TensorFlow in conda env (separate to manage dependencies)
RUN conda run -n datasci pip install --no-cache-dir \
    torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124 \
    tensorflow[and-cuda] pytorch-lightning \
    transformers huggingface-hub

# Install spacy model (use direct conda env paths to avoid activation issues)
RUN /opt/conda/envs/datasci/bin/python -m spacy download en_core_web_sm

# Install Jupyter extensions (use direct conda env paths)
RUN /opt/conda/envs/datasci/bin/pip install --no-cache-dir jupyter-lsp python-lsp-server jupyterlab-lsp jupyterlab-git jupyterlab-execute-time

# Enable conda env on shell startup
RUN echo "conda activate datasci" >> ~/.bashrc

# Switch to user
USER ${base_user}

# Activate conda env by default in shells
RUN echo 'source /opt/conda/etc/profile.d/conda.sh && conda activate datasci' >> ~/.bashrc

# Create Jupyter config directory
RUN mkdir -p ~/.jupyter && touch ~/.hushlogin

# Switch back to root for final setup
USER root
