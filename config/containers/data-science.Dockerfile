# ============================================================================
# DATA-SCIENCE: CUDA, Jupyter, Scientific Computing, Bioinformatics
# ============================================================================
#
# Category-specific layer appended after common.Dockerfile
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# Switch to root for package installation
USER root

# Install the latest stable CUDA Toolkit from the NVIDIA Ubuntu repo
RUN bash -lc 'set -e; if [ -f /etc/os-release ]; then . /etc/os-release; fi; VERSION_ID="${VERSION_ID:-26.04}"; CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${VERSION_ID//.}/x86_64/"; CUDA_PACKAGE="$(curl -fsSL "$CUDA_REPO_URL" 2>/dev/null | grep -oE "cuda-toolkit-[0-9]+-[0-9]+" | LC_ALL=C sort -V | tail -n 1 || echo "cuda-toolkit-13-5")"; [ -n "$CUDA_PACKAGE" ]; CUDA_NVCC_PACKAGE="${CUDA_PACKAGE/cuda-toolkit-/cuda-nvcc-}"; CUDA_LIBRARIES_PACKAGE="${CUDA_PACKAGE/cuda-toolkit-/cuda-libraries-dev-}"; CUDA_CUDART_PACKAGE="${CUDA_PACKAGE/cuda-toolkit-/cuda-cudart-dev-}"; curl -fsSL --retry 5 --retry-delay 10 "${CUDA_REPO_URL}cuda-keyring_1.1-1_all.deb" -o /tmp/cuda-keyring.deb; dpkg -i /tmp/cuda-keyring.deb; rm -f /tmp/cuda-keyring.deb; apt-get update; apt-get install -y --no-install-recommends "$CUDA_PACKAGE" "$CUDA_NVCC_PACKAGE" "$CUDA_LIBRARIES_PACKAGE" "$CUDA_CUDART_PACKAGE"; rm -rf /var/lib/apt/lists/*'

# Install the newest compatible CUDA runtime libraries for the active toolkit release
RUN bash -lc 'set -e; if [ -f /etc/os-release ]; then . /etc/os-release; fi; VERSION_ID="${VERSION_ID:-26.04}"; CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${VERSION_ID//.}/x86_64/"; CUDA_PACKAGE="$(curl -fsSL "$CUDA_REPO_URL" 2>/dev/null | grep -oE "cuda-toolkit-[0-9]+-[0-9]+" | LC_ALL=C sort -V | tail -n 1 || echo "cuda-toolkit-13-5")"; CUDA_VERSION="${CUDA_PACKAGE/cuda-toolkit-/}"; CUDA_RUNTIME_PACKAGES=(); for pkg in cuda-cudart cuda-nvrtc libcublas libcufft libcurand libcusparse libcusolver libnvjitlink; do CUDA_RUNTIME_PACKAGES+=("${pkg}-${CUDA_VERSION}"); done; CUDA_CUDNN_PACKAGE="libcudnn9-cuda-${CUDA_VERSION%%-*}"; apt-get update; apt-get install -y --no-install-recommends "${CUDA_RUNTIME_PACKAGES[@]}" "$CUDA_CUDNN_PACKAGE"; rm -rf /var/lib/apt/lists/*'

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
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    CUDA_HOME=/usr/local/cuda

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-dev python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install R packages for bioinformatics (phyloseq, etc.) - must be root
RUN R --vanilla -e "install.packages(c('BiocManager', 'tidyverse', 'ggplot2', 'ggmap', 'plotly'), repos='http://cran.r-project.org')" \
    && R --vanilla -e "BiocManager::install(c('phyloseq', 'dada2', 'DESeq2', 'limma', 'edgeR', 'igraph'), ask=FALSE)" \
    && R --vanilla -e "install.packages('vegan', repos='http://cran.r-project.org')"

# Install Miniforge (lightweight conda) as root, then update conda itself to latest
RUN wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && \
    rm /tmp/miniforge.sh && \
    /opt/conda/bin/conda update -n base -c conda-forge conda -y && \
    /opt/conda/bin/conda clean -afy

ENV PATH="/opt/conda/bin:$PATH"

# Create conda environment with scientific and bioinformatics stack (as root)
RUN conda create -y -n datasci python=3.12 && \
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
    torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu126 \
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
