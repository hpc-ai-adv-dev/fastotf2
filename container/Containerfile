# Copyright Hewlett Packard Enterprise Development LP.

# Start from official Chapel image
FROM chapel/chapel:2.6.0

# System deps needed for building OTF2 + Arrow
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake git wget curl unzip pkg-config \
    python3 python3-pip python3-dev python3-venv \
    libssl-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------
# Install OTF2
# -----------------------------
COPY otf2-3.1.1.tar.gz /opt/
WORKDIR /opt
RUN tar -xzf otf2-3.1.1.tar.gz && \
    cd otf2-3.1.1 && ./configure --prefix=/opt/otf2 && \
    make -j$(nproc) && make install && \
    rm -rf /opt/otf2-3.1.1*
ENV LD_LIBRARY_PATH=/opt/otf2/lib:$LD_LIBRARY_PATH

# -----------------------------
# Setup Python venv & install otf2
# -----------------------------
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN pip install --upgrade pip && \
    pip install otf2

# -----------------------------
# Default working dir + shell
# -----------------------------
WORKDIR /workspace
CMD ["/bin/bash"]

