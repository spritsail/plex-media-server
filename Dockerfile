ARG PLEX_VER=1.14.1.5488-cc260c476
ARG PLEX_SHA=1bd274026c4d7038ec57bad7c3735ce47f73b887
ARG LIBSTDCPP_VER=6.3.0-18+deb9u1
ARG LIBGCC1_VER=6.3.0-18+deb9u1
ARG XMLSTAR_VER=1.6.1
ARG CURL_VER=curl-7_64_0

FROM spritsail/debian-builder:stretch-slim as builder

ARG PLEX_VER
ARG PLEX_SHA
ARG LIBSTDCPP_VER
ARG LIBGCC1_VER
ARG LIBXML2_VER=v2.9.8
ARG LIBXSLT_VER=v1.1.32
ARG XMLSTAR_VER
ARG LIBRE_VER=2.8.2
ARG CURL_VER

ARG MAKEFLAGS=-j2

RUN apt-get -y update \
 && apt-get -y install zlib1g-dev

# Download and build libxml2
WORKDIR /tmp/libxml2
RUN git clone https://gitlab.gnome.org/GNOME/libxml2.git --branch $LIBXML2_VER --depth 1 . \
 && ./autogen.sh \
        --prefix=/usr \
        --without-catalog \
        --without-docbook \
        --without-ftp \
        --without-http \
        --without-iconv \
        --without-iso8859x \
        --without-legacy \
        --without-modules \
        --without-python \
 && make DESTDIR=/prefix install

# Download and build libxslt
WORKDIR /tmp/libxslt
RUN git clone https://gitlab.gnome.org/GNOME/libxslt.git --branch $LIBXSLT_VER --depth 1 . \
 && ./autogen.sh \
        --prefix=/usr \
        --with-libxml-src="../libxml2" \
        --without-crypto \
        --without-plugins \
        --without-python \
 && make DESTDIR=/prefix install

# Download and build xmlstarlet
ADD xmlstarlet-*.patch /tmp
WORKDIR /tmp/xmlstarlet
RUN git clone git://git.code.sf.net/p/xmlstar/code --branch $XMLSTAR_VER --depth 1 . \
 && git apply /tmp/xmlstarlet*.patch \
 && autoreconf -sif \
 && ./configure \
        --prefix=/usr \
        --disable-build-docs \
        --with-libxml-prefix=/prefix/usr \
        --with-libxslt-prefix=/prefix/usr \
 && make DESTDIR=/prefix install

# Download and build LibreSSL as a cURL dependency
WORKDIR /tmp/libressl
RUN curl -sSL https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${LIBRE_VER}.tar.gz \
        | tar xz --strip-components=1 \
    # Install to the default system directories so cURL can find it
 && ./configure --prefix=/usr \
 && make install

# Download and build curl
WORKDIR /tmp/curl
RUN git clone https://github.com/curl/curl.git --branch $CURL_VER --depth 1 . \
 && autoreconf -sif \
 && ./configure \
        --prefix=/usr \
        --enable-ipv6 \
        --enable-optimize \
        --enable-symbol-hiding \
        --enable-versioned-symbols \
        --enable-threaded-resolver \
        --with-ssl \
        --with-zlib \
        --disable-crypto-auth \
        --disable-curldebug \
        --disable-dependency-tracking \
        --disable-dict \
        --disable-gopher \
        --disable-imap \
        --disable-libcurl-option \
        --disable-ldap \
        --disable-ldaps \
        --disable-manual \
        --disable-ntlm-wb \
        --disable-pop3 \
        --disable-rtsp \
        --disable-smb \
        --disable-smtp \
        --disable-sspi \
        --disable-telnet \
        --disable-tftp \
        --disable-tls-srp \
        --disable-verbose \
        --without-axtls \
        --without-libmetalink \
        --without-libpsl \
        --without-librtmp \
        --without-winidn \
 && make DESTDIR=/prefix install

WORKDIR /prefix

# Fetch Plex and required libraries
RUN curl -fsSL http://ftp.de.debian.org/debian/pool/main/g/gcc-${LIBSTDCPP_VER:0:1}/libstdc++6_${LIBSTDCPP_VER}_amd64.deb | dpkg-deb -x - . \
 && curl -fsSL http://ftp.de.debian.org/debian/pool/main/g/gcc-${LIBGCC1_VER:0:1}/libgcc1_${LIBGCC1_VER}_amd64.deb | dpkg-deb -x - . \
 && curl -fsSL -o plexmediaserver.deb https://downloads.plex.tv/plex-media-server/${PLEX_VER}/plexmediaserver_${PLEX_VER}_amd64.deb \
    \
 && echo "$PLEX_SHA  plexmediaserver.deb" | sha1sum -c - \
 && dpkg-deb -x plexmediaserver.deb . \
    \
 && cd usr/lib/plexmediaserver \
 && rm -f \
        "Plex Media Server Tests" \
        MigratePlexServerConfig.sh \
        libcrypto.so* \
        libcurl.so* \
        libssl.so* \
        libxml2.so* \
        libxslt.so* \
        Resources/start.sh \
    # Place shared libraries in usr/lib so they can be actually shared
 && mv *.so* ../

    # Strip all unneeded symbols for optimum size
RUN find -exec sh -c 'file "{}" | grep -q ELF && strip --strip-debug "{}"' \; \
    \
 && mkdir -p /output/usr/lib /output/usr/bin \
 && mv usr/lib/x86_64-linux-gnu/*.so* \
       lib/x86_64-linux-gnu/*.so* \
       usr/lib/plexmediaserver \
       usr/lib/*.so* \
       /output/usr/lib \
 && mv usr/bin/curl /output/usr/bin \
 && mv usr/bin/xml /output/usr/bin/xmlstarlet

ADD entrypoint /output/usr/local/bin/
ADD *.sh /output/usr/local/bin/
RUN chmod +x /output/usr/local/bin/*

#=========================

FROM spritsail/libressl

ARG PLEX_VER
ARG LIBSTDCPP_VER
ARG LIBGCC1_VER
ARG CURL_VER
ARG XMLSTAR_VER

LABEL maintainer="Spritsail <plex@spritsail.io>" \
      org.label-schema.vendor="Spritsail" \
      org.label-schema.name="Plex Media Server" \
      org.label-schema.url="https://www.plex.tv/downloads/" \
      org.label-schema.description="Tiny Docker image for Plex Media Server, built on busybox" \
      org.label-schema.version=${PLEX_VER} \
      io.spritsail.version.plex=${PLEX_VER} \
      io.spritsail.version.curl=${CURL_VER} \
      io.spritsail.version.libgcc1=${LIBGCC1_VER} \
      io.spritsail.version.libstdcpp=${LIBSTDCPP_VER} \
      io.spritsail.version.xmlstarlet=${XMLSTAR_VER}

WORKDIR /usr/lib/plexmediaserver

COPY --from=builder /output/ /

ENV SUID=900 SGID=900 \
    PLEX_MEDIA_SERVER_MAX_PLUGIN_PROCS="6" \
    PLEX_MEDIA_SERVER_MAX_STACK_SIZE="3000" \
    PLEX_MEDIA_SERVER_TMPDIR="/tmp" \
    PLEX_MEDIA_SERVER_HOME="/usr/lib/plexmediaserver" \
    PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR="/var/lib/plexmediaserver"

HEALTHCHECK --interval=10s --timeout=5s \
    CMD [ "wget", "-O", "/dev/null", "-T", "10", "-q", "localhost:32400/identity" ]

EXPOSE 32400

VOLUME ["/config", "/transcode"]

RUN mkdir -p "$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR" \
 && ln -sfv /config "$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR/Plex Media Server"

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/entrypoint"]
