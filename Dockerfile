FROM ubuntu:22.04 AS build

ENV DEBIAN_FRONTEND=noninteractive \
    VCPKG_ROOT=/opt/vcpkg \
    VCPKG_DEFAULT_TRIPLET=x64-linux
ENV PATH="${VCPKG_ROOT}:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    bison \
    build-essential \
    ca-certificates \
    curl \
    flex \
    git \
    libtool \
    ninja-build \
    pkg-config \
    python3 \
    tar \
    unzip \
    zip \
    cmake \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 https://github.com/microsoft/vcpkg.git \
    && ${VCPKG_ROOT}/bootstrap-vcpkg.sh

WORKDIR /usr/src/forgottenserver-downgrade

COPY vcpkg.json ./
# Pre-seed Lua's distfile to avoid transient vcpkg download timeouts in CI.
RUN set -eux; \
    mkdir -p /opt/vcpkg/downloads; \
    curl -fL --retry 10 --retry-all-errors --retry-delay 5 --connect-timeout 30 --max-time 600 \
        -o /opt/vcpkg/downloads/lua-5.5.0.tar.gz \
        https://www.lua.org/ftp/lua-5.5.0.tar.gz; \
    /opt/vcpkg/vcpkg install --triplet x64-linux
# Copiar el resto del código
COPY cmake /usr/src/forgottenserver-downgrade/cmake/
COPY src /usr/src/forgottenserver-downgrade/src/
COPY CMakeLists.txt /usr/src/forgottenserver-downgrade/
WORKDIR /usr/src/forgottenserver-downgrade
# Usar el flujo clásico de CMake con vcpkg toolchain
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_TOOLCHAIN_FILE=/opt/vcpkg/scripts/buildsystems/vcpkg.cmake \
    && cmake --build build --config RelWithDebInfo

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libgcc-s1 \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/src/forgottenserver-downgrade/build/tfs /bin/tfs
COPY data /srv/data/
COPY LICENSE README.md *.dist *.sql key.pem /srv/

EXPOSE 7171 7172
WORKDIR /srv
VOLUME /srv
ENTRYPOINT ["/bin/tfs"]
