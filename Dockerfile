# qBittorrent, OpenVPN and WireGuard, qbittorrentvpn
FROM debian:bookworm-slim

# Load env vars
ARG BOOST_VERSION
ARG BOOST_VERSION_DOT

ENV BOOST_VERSION=${BOOST_VERSION}
ENV BOOST_VERSION_DOT=${BOOST_VERSION_DOT}

WORKDIR /opt

RUN usermod -u 99 nobody

# Make directories
RUN mkdir -p /downloads /config/qBittorrent /etc/openvpn /etc/qbittorrent

# Install required dependencies
RUN apt update && apt upgrade -y && \
    apt install -y --no-install-recommends \
        curl \
        ca-certificates \
        g++ \
        libxml2-utils \
        build-essential \
        cmake \
        ninja-build \
        libssl-dev \
        pkg-config \
        jq \
        python3 \
        tar && \
    rm -rf /var/lib/apt/lists/*

# Download and build Boost
WORKDIR /opt

RUN curl -L -o boost_${BOOST_VERSION}.tar.gz \
        https://archives.boost.io/release/${BOOST_VERSION_DOT}/source/boost_${BOOST_VERSION}.tar.gz && \
    tar -xzf boost_${BOOST_VERSION}.tar.gz && \
    cd boost_${BOOST_VERSION} && \
    ./bootstrap.sh --prefix=/usr && \
    ./b2 --prefix=/usr install && \
    cd /opt && \
    rm -rf boost_${BOOST_VERSION}*  # cleanup source and tarball

# Compile and install libtorrent-rasterbar
RUN apt update \
    && apt upgrade -y \
    && apt install -y --no-install-recommends \
    jq \
    libssl-dev \
    && LIBTORRENT_ASSETS=$(curl -sX GET "https://api.github.com/repos/arvidn/libtorrent/releases" | jq '.[] | select(.prerelease==false) | select(.target_commitish=="RC_1_2") | .assets_url' | head -n 1 | tr -d '"') \
    && LIBTORRENT_DOWNLOAD_URL=$(curl -sX GET ${LIBTORRENT_ASSETS} | jq '.[0] .browser_download_url' | tr -d '"') \
    && LIBTORRENT_NAME=$(curl -sX GET ${LIBTORRENT_ASSETS} | jq '.[0] .name' | tr -d '"') \
    && curl -o /opt/${LIBTORRENT_NAME} -L ${LIBTORRENT_DOWNLOAD_URL} \
    && tar -xzf /opt/${LIBTORRENT_NAME} \
    && rm /opt/${LIBTORRENT_NAME} \
    && cd /opt/libtorrent-rasterbar* \
    && cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr -DCMAKE_CXX_STANDARD=17 \
    && cmake --build build --parallel $(nproc) \
    && cmake --install build \
    && cd /opt \
    && rm -rf /opt/* \
    && rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

ENV QBITTORRENT_RELEASE=4.6.7

# Compile and install qBittorrent
RUN apt update \
    && apt upgrade -y \
    && apt install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    jq \
    libssl-dev \
    pkg-config \
    qtbase5-dev \
    qtbase5-private-dev \
    qttools5-dev \
    zlib1g-dev \
    # && QBITTORRENT_RELEASE=$(curl -sX GET "https://api.github.com/repos/qBittorrent/qBittorrent/tags" | jq '.[] | select(.name | index ("alpha") | not) | select(.name | index ("beta") | not) | select(.name | index ("rc") | not) | .name' | head -n 1 | tr -d '"') \
    && curl -o /opt/qBittorrent-release-${QBITTORRENT_RELEASE}.tar.gz -L "https://github.com/qbittorrent/qBittorrent/archive/refs/tags/release-${QBITTORRENT_RELEASE}.tar.gz" \
    && tar -xzf /opt/qBittorrent-release-${QBITTORRENT_RELEASE}.tar.gz \
    && rm /opt/qBittorrent-release-${QBITTORRENT_RELEASE}.tar.gz \
    && cd /opt/qBittorrent-release-${QBITTORRENT_RELEASE} \
    && cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DGUI=OFF -DCMAKE_CXX_STANDARD=17 \
    && cmake --build build --parallel $(nproc) \
    && cmake --install build \
    && cd /opt \
    && rm -rf /opt/* \
    && apt purge -y \
    build-essential \
    ca-certificates \
    curl \
    git \
    jq \
    libssl-dev \
    pkg-config \
    qtbase5-dev \
    qtbase5-private-dev \
    qttools5-dev \
    zlib1g-dev \
    && apt-get clean \
    && apt --purge autoremove -y \
    && rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

# Install WireGuard and some other dependencies some of the scripts in the container rely on.
RUN echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable-wireguard.list \
    && printf 'Package: *\nPin: release a=unstable\nPin-Priority: 150\n' > /etc/apt/preferences.d/limit-unstable \
    && apt update \
    && apt install -y --no-install-recommends \
    ca-certificates \
    dos2unix \
    inetutils-ping \
    ipcalc \
    iptables \
    kmod \
    libqt5network5 \
    libqt5xml5 \
    libqt5sql5 \
    libssl-dev \
    moreutils \
    net-tools \
    openresolv \
    openvpn \
    procps \
    wireguard-tools \
    && apt-get clean \
    && apt --purge autoremove -y \
    && rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

# Install (un)compressing tools like unrar, 7z, unzip and zip
RUN apt update \
    && apt install -y --no-install-recommends \
    unrar-free \
    p7zip-full \
    unzip \
    zip

# Remove src_valid_mark from wg-quick
RUN sed -i /net\.ipv4\.conf\.all\.src_valid_mark/d `which wg-quick`

VOLUME /config /downloads

ADD openvpn/ /etc/openvpn/
ADD qbittorrent/ /etc/qbittorrent/

RUN chmod +x /etc/qbittorrent/*.sh /etc/qbittorrent/*.init /etc/openvpn/*.sh

EXPOSE 8080
EXPOSE 8999
EXPOSE 8999/udp
CMD ["/bin/bash", "/etc/openvpn/start.sh"]
