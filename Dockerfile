FROM nvcr.io/nvidia/l4t-base:r32.5.0 AS base

WORKDIR /tmp/workdir

# https://askubuntu.com/questions/972516/debian-frontend-environment-variable
ARG DEBIAN_FRONTEND="noninteractive"
# http://stackoverflow.com/questions/48162574/ddg#49462622
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn
# https://github.com/NVIDIA/nvidia-docker/wiki/Installation-(Native-GPU-Support)
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"

RUN	apt-get update && apt-get install -y gnupg ca-certificates \
    && echo "deb https://repo.download.nvidia.com/jetson/common r32.5 main" >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list \
    && echo "deb https://repo.download.nvidia.com/jetson/t210 r32.5 main" >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list \
    && apt-key adv --fetch-key http://repo.download.nvidia.com/jetson/jetson-ota-public.asc \
    && mkdir -p /opt/nvidia/l4t-packages/ && touch /opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall \
    && apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y \
    -o Dpkg::Options::=--force-confnew \
    -o Dpkg::Options::=--force-confdef \
    --allow-downgrades --allow-remove-essential --allow-change-held-packages \
    expat \
    libgomp1 \
    cmake \
    xz-utils \
    rsync \
    git \
    wget \
    libv4l-dev \
    libegl1-mesa-dev \
    nvidia-l4t-jetson-multimedia-api \
    nvidia-l4t-multimedia \
    nvidia-l4t-cuda \
    nvidia-l4t-3d-core \
    nvidia-l4t-wayland \
    libunistring-dev \
    libx264-dev \
    nasm \
    zlib1g-dev \
    libx265-dev \
    libnuma-dev \
    libvpx-dev \
    libmp3lame-dev \
    libopus-dev \
    libffi6 && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

ENV UDEV=1

FROM base as build

ENV FFMPEG_VERSION=4.2

RUN apt-get -y update && \
    apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    curl \
    bzip2 \
    libexpat1-dev \
    g++ \
    gcc \
    gperf \
    libtool \
    make \
    nasm \
    pkg-config \
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
    libssl-dev \
    yasm \
    libomxil-bellagio-dev \
    libpthread-stubs0-dev \
    zlib1g-dev && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

ARG PREFIX=/opt/ffmpeg

COPY . /tmp/jetson-ffmpeg
## Nvidia Jetson hwaccel https://github.com/jocover/jetson-ffmpeg
RUN	DIR=/tmp/jetson-ffmpeg && \
     cd ${DIR} && \
     mkdir build && \
     cd build && \
     cmake -DCMAKE_INSTALL_PREFIX:PATH="${PREFIX}" .. && \
     make -j $(nproc) && \
     make -j $(nproc) install && \
     ldconfig && \
     rm -rf ${DIR}

COPY ./ffmpeg_nvmpi.patch /tmp/ffmpeg_nvmpi.patch
## ffmpeg https://ffmpeg.org/
RUN	DIR=/tmp/ffmpeg && mkdir -p ${DIR} && cd ${DIR} && \
    curl -sLO https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2 && \
    tar -jx --strip-components=1 -f ffmpeg-${FFMPEG_VERSION}.tar.bz2 && \
    git apply /tmp/ffmpeg_nvmpi.patch

RUN	DIR=/tmp/ffmpeg && mkdir -p ${DIR} && cd ${DIR} && \
    export PATH=$PATH:/usr/local/cuda/bin && \
    export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:${PREFIX}/lib/pkgconfig && \
    ./configure \
    --enable-nvmpi \
    --enable-shared \
    --enable-avresample \
    --enable-gpl \
    --enable-libfreetype \
    --enable-nonfree \
    --enable-cuda-nvcc \
    --enable-openssl \
    --enable-postproc \
    --enable-version3 \
    --extra-libs=-ldl \
    --enable-neon \
    --disable-debug \
    --disable-static \
    --disable-doc \
    --disable-ffplay \
    --disable-libxcb \
    --disable-libxcb-shm \
    --disable-libxcb-xfixes \
    --disable-libxcb-shape \
    --prefix="${PREFIX}" \
    --extra-cflags="-I${PREFIX}/include -I /usr/src/jetson_multimedia_api/include/ -I/usr/local/cuda/include" \
    --extra-ldflags="-L${PREFIX}/lib -L/usr/lib/aarch64-linux-gnu/tegra -lnvbuf_utils -L/usr/local/cuda/lib64" && \
    make -j $(nproc) && \
    make -j $(nproc) install && \
    make distclean && \
    hash -r

## cleanup
RUN ldd ${PREFIX}/bin/ffmpeg | grep opt/ffmpeg | cut -d ' ' -f 3 | xargs -i cp {} /usr/local/lib/ && \
        for lib in /usr/local/lib/*.so.*; do ln -s "${lib##*/}" "${lib%%.so.*}".so; done && \
        cp -rv /opt/ffmpeg/lib/* /usr/local/lib/ && \
        cp ${PREFIX}/bin/* /usr/local/bin/ && \
        cp -r ${PREFIX}/share/ffmpeg /usr/local/share/ && ls /usr/local/lib && \
    ldd /usr/local/bin/ffmpeg && \
        cp -r ${PREFIX}/include/libav* ${PREFIX}/include/libpostproc ${PREFIX}/include/libsw* /usr/local/include && \
        mkdir -p /usr/local/lib/pkgconfig && \
        for pc in ${PREFIX}/lib/pkgconfig/libav*.pc ${PREFIX}/lib/pkgconfig/libpostproc.pc ${PREFIX}/lib/pkgconfig/libsw*.pc; do \
        sed "s:${PREFIX}:/usr/local:g" <"$pc" >/usr/local/lib/pkgconfig/"${pc##*/}"; \
        done

FROM base AS release

ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64:/usr/lib:/usr/lib64:/lib:/lib64:/usr/lib/aarch64-linux-gnu/tegra:/usr/lib/aarch64-linux-gnu/tegra-egl \
    PATH=$PATH:/usr/local/cuda/bin

COPY --from=build /usr/local /usr/local/
