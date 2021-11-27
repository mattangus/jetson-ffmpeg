FROM multiarch/qemu-user-static:x86_64-aarch64 as qemu
FROM nvcr.io/nvidia/l4t-base:r32.5.0 as app

# https://askubuntu.com/questions/972516/debian-frontend-environment-variable
ARG DEBIAN_FRONTEND="noninteractive"
# http://stackoverflow.com/questions/48162574/ddg#49462622
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn
# https://github.com/NVIDIA/nvidia-docker/wiki/Installation-(Native-GPU-Support)
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"

WORKDIR /workspace
COPY . /workspace

COPY --from=qemu /usr/bin/qemu-aarch64-static /usr/bin
COPY ffmpeg_nvmpi.patch /ffmpeg_nvmpi.patch

RUN apt-get update && apt-get install -y gnupg libssl-dev ca-certificates \
    && echo "deb https://repo.download.nvidia.com/jetson/common r32.5 main" >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list \
    && echo "deb https://repo.download.nvidia.com/jetson/t210 r32.5 main" >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list \
    && apt-key adv --fetch-key http://repo.download.nvidia.com/jetson/jetson-ota-public.asc \
    && mkdir -p /opt/nvidia/l4t-packages/ && touch /opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall \
    && apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y \
    -o Dpkg::Options::=--force-confnew \
    -o Dpkg::Options::=--force-confdef \
    --allow-downgrades --allow-remove-essential --allow-change-held-packages \
    autoconf \
    automake \
    build-essential \
    cmake \
    git-core \
    libass-dev \
    libfreetype6-dev \
    libgnutls28-dev \
    libsdl2-dev \
    libtool \
    libva-dev \
    libvdpau-dev \
    libvorbis-dev \
    libxcb1-dev \
    libxcb-shm0-dev \
    libxcb-xfixes0-dev \
    meson \
    ninja-build \
    pkg-config \
    texinfo \
    wget \
    yasm \
    zlib1g-dev \
    nvidia-l4t-jetson-multimedia-api \
    # these might be overkill
    libunistring-dev libx264-dev nasm libx265-dev libnuma-dev libvpx-dev libmp3lame-dev libopus-dev \
    && apt-get clean autoclean -y \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && git clone git://source.ffmpeg.org/ffmpeg.git -b release/4.2 --depth=1 \
    && cd ffmpeg \
    && git apply /ffmpeg_nvmpi.patch && \
    ./configure   \
    --enable-gpl \
    --enable-gnutls \
    --enable-libass \
    # --enable-libfdk-aac \
    --enable-libfreetype \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libx264 \
    --enable-libx265 \
    --enable-nvmpi \
    --enable-nonfree --prefix=/usr/ \
    && make -j$(nproc) \
    && make install