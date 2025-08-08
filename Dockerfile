ARG PLEX_VER=1.42.1.10054-f333bdaa8
ARG BUSYBOX_VER=1.37.0
ARG SU_EXEC_VER=0.4
ARG TINI_VER=0.19.0
ARG ZLIB_VER=1.3.1
# https://sourceforge.net/p/xmlstar/bugs/135/
# https://bugs.gentoo.org/944765
ARG LIBXML2_VER=2.13.4
ARG LIBXSLT_VER=1.1.43
ARG XMLSTAR_VER=1.6.1
ARG OPENSSL_VER=3.5.1
ARG NGHTTP2_VER=1.66.0
ARG CURL_VER=8.14.1

ARG OUTPUT=/output
ARG DESTDIR=/prefix

ARG CFLAGS="-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=2 -flto=auto"
ARG LDFLAGS="$CFLAGS -Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM spritsail/alpine:3.22 AS builder

RUN apk add --no-cache \
        autoconf \
        automake \
        binutils \
        cmake \
        curl \
        dpkg \
        file \
        gcc \
        git \
        libtool \
        linux-headers \
        make \
        musl-dev \
        nghttp2-dev \
        pkgconfig \
        xxd \
        zstd

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS plex

ARG PLEX_VER
ARG OUTPUT

WORKDIR $OUTPUT

# Fetch Plex and required libraries
RUN if [ "$(uname -m)" = "aarch64" ]; then \
        ARCH=arm64; LIB_DIRS=lib/omx; \
    else \
        ARCH=amd64; \
    fi \
 && curl -fsSL -o plexmediaserver.deb https://downloads.plex.tv/plex-media-server-new/${PLEX_VER}/debian/plexmediaserver_${PLEX_VER}_${ARCH}.deb \
 && dpkg-deb -x plexmediaserver.deb . \
    \
 && rm -rfv \
        etc/ usr/share/ \
        usr/lib/plexmediaserver/etc \
        plexmediaserver.deb \
    \
 && cd usr/lib/plexmediaserver \
 && rm -v \
        lib/libcrypto.so* \
        lib/libcurl.so* \
        lib/libssl.so* \
        lib/libnghttp2.so* \
        lib/plexmediaserver.* \
        Resources/start.sh \
    \
    # Place shared libraries in usr/lib so they can be actually shared
 && mv lib/*.so* $LIB_DIRS ../ \
 && rmdir lib \
 && ln -sv ../ lib \
    # Replace hardlink with a symlink; these files are the same
 && cd .. && ln -sfvn "ld-musl-$(uname -m).so.1" libc.so

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS busybox

ARG CFLAGS
ARG LDFLAGS
ARG MAKEFLAGS
ARG OUTPUT

ARG BUSYBOX_VER
WORKDIR /tmp/busybox

RUN curl -fsSL https://busybox.net/downloads/busybox-${BUSYBOX_VER}.tar.bz2 \
        | tar xj --strip-components=1 \
 && curl -fsS https://git.busybox.net/busybox/patch/?id=bf57f732a5b6842f6fa3e0f90385f039e5d6a92c | git apply \
 && make defconfig \
 # https://lists.busybox.net/pipermail/busybox-cvs/2024-January/041752.html
 && sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config \
 && make \
 && install -Dm755 busybox "$OUTPUT/usr/bin/busybox" \
    # "Install" busybox, creating symlinks to all binaries it provides
 && mkdir -p "$OUTPUT/usr/bin" "$OUTPUT/usr/sbin" \
 && ./busybox --list-full | sed -E 's@^(s?bin)@usr/\1@' | xargs -i ln -Tsv /usr/bin/busybox "$OUTPUT/{}"

ARG SU_EXEC_VER
WORKDIR /tmp/su-exec

RUN curl -fL https://github.com/frebib/su-exec/archive/v${SU_EXEC_VER}.tar.gz \
        | tar xz --strip-components=1 \
 && make \
 && install -Dm755 su-exec "$OUTPUT/usr/sbin/su-exec"

ARG TINI_VER
WORKDIR /tmp/tini

RUN curl -fL https://github.com/krallin/tini/archive/v${TINI_VER}.tar.gz \
        | tar xz --strip-components=1 \
 && curl -fsS https://github.com/krallin/tini/commit/7c430f3eb68ebfc8a8706ab09faad6c6fa8aa13e.patch \
        | git apply \
 && cmake . \
 && make tini \
 && install -Dm755 tini "$OUTPUT/usr/sbin/tini"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS zlib

ARG CFLAGS
ARG LDFLAGS
ARG MAKEFLAGS
ARG OUTPUT
ARG DESTDIR

ARG ZLIB_VER
WORKDIR /tmp/zlib

RUN curl -sSf https://www.zlib.net/zlib-$ZLIB_VER.tar.xz \
        | tar xJ --strip-components=1 \
 && ./configure \
        --prefix=/usr \
        --shared \
 && make install \
 && make DESTDIR="$DESTDIR" install \
 && mkdir -p "$OUTPUT/usr/lib" \
 && cp -aP "$DESTDIR"/usr/lib/*.so* "$OUTPUT/usr/lib"

ARG LIBXML2_VER
WORKDIR /tmp/libxml2

RUN git clone https://gitlab.gnome.org/GNOME/libxml2.git --branch v$LIBXML2_VER --depth 1 . \
 && ./autogen.sh \
        --prefix=/usr \
        --with-zlib="$DESTDIR/usr" \
        --without-catalog \
        --without-docbook \
        --without-ftp \
        --without-http \
        --without-iconv \
        --without-iso8859x \
        --without-legacy \
        --without-modules \
        --without-python \
 && make install \
 && make DESTDIR="$DESTDIR" install \
 && cp -aP "$DESTDIR"/usr/lib/*.so* "$OUTPUT/usr/lib"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM zlib AS xml

ARG CFLAGS
ARG LDFLAGS
ARG MAKEFLAGS
ARG OUTPUT
ARG DESTDIR

ARG LIBXSLT_VER
WORKDIR /tmp/libxslt

RUN git clone https://gitlab.gnome.org/GNOME/libxslt.git --branch v$LIBXSLT_VER --depth 1 . \
 && ./autogen.sh \
        --prefix=/usr \
        --with-libxml-src=../libxml2 \
        --without-crypto \
        --without-plugins \
        --without-python \
 && make DESTDIR="$DESTDIR" install \
 && cp -aP "$DESTDIR"/usr/lib/*.so* "$OUTPUT/usr/lib"

ARG XMLSTAR_VER
ADD xmlstarlet-*.patch /tmp
WORKDIR /tmp/xmlstarlet

RUN git clone git://git.code.sf.net/p/xmlstar/code --branch $XMLSTAR_VER --depth 1 . \
 && git apply /tmp/xmlstarlet*.patch \
 && autoreconf -sif \
 && ./configure \
        --prefix=/usr \
        --disable-build-docs \
        --with-libxml-prefix="$DESTDIR/usr" \
        --with-libxslt-prefix="$DESTDIR/usr" \
 && make DESTDIR="$DESTDIR" install \
 && install -Dm755 "$DESTDIR/usr/bin/xml" "$OUTPUT/usr/bin/xmlstarlet"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM zlib AS curl

ARG CFLAGS
ARG LDFLAGS
ARG MAKEFLAGS
ARG OUTPUT
ARG DESTDIR

ARG OPENSSL_VER
WORKDIR /tmp/openssl

RUN curl -sSL https://openssl.org/source/openssl-${OPENSSL_VER}.tar.gz \
        | tar xz --strip-components=1 \
 && ./config \
        --prefix=/usr \
        --libdir=lib \
        --with-zlib-lib="$DESTDIR/usr/lib" \
        --with-zlib-include="$DESTDIR/usr/include" \
        shared \
        zlib-dynamic \
        no-engine \
        no-rc5 \
        no-ssl3-method \
        no-tests \
 && make build_libs \
 && make build_programs \
 && make DESTDIR="$DESTDIR" \
    install_sw \
    install_ssldirs \
 && cp -aP "$DESTDIR"/usr/lib/*.so* "$OUTPUT/usr/lib" \
 && sed -i "s@prefix=/usr@prefix=$DESTDIR/usr@g" "$DESTDIR"/usr/lib/pkgconfig/*.pc

ARG NGHTTP2_VER
WORKDIR /tmp/libnghttp2

RUN git clone https://github.com/nghttp2/nghttp2.git -b v$NGHTTP2_VER --depth 1 . \
 && autoreconf -i \
 && ./configure \
        --prefix=/usr \
        --enable-lib-only \
        --with-libxml2=yes \
        --with-openssl=yes \
        --with-zlib=yes \
 && make DESTDIR="$DESTDIR" install \
 && cp -aP "$DESTDIR"/usr/lib/libnghttp2*.so* "$OUTPUT/usr/lib"

# /usr/lib # curl --version
# curl 8.0.1 (x86_64-pc-linux-musl) libcurl/8.0.1 OpenSSL/3.0.8 zlib/1.2.13 nghttp2/1.52.0
# Release-Date: 2023-03-20
# Protocols: http https
# Features: alt-svc AsynchDNS HSTS HTTP2 HTTPS-proxy IPv6 Largefile libz SSL threadsafe UnixSockets

ARG CURL_VER
WORKDIR /tmp/curl
RUN export CURL_TAG=curl-${CURL_VER//./_} \
 && git clone https://github.com/curl/curl.git --branch $CURL_TAG --depth 1 . \
 && sed -i \
        -e "/\WLIBCURL_VERSION\W/c #define LIBCURL_VERSION \"$CURL_VER\"" \
        -e "/\WLIBCURL_TIMESTAMP\W/c #define LIBCURL_TIMESTAMP \"$(git log -1 --format=%cs "$CURL_TAG")\"" \
        include/curl/curlver.h \
 && autoreconf -sif \
 && ./configure \
        --prefix=/usr \
        --enable-http \
        --enable-ipv6 \
        --enable-largefile \
        --enable-proxy \
        --enable-unix-sockets \
        --with-libnghttp2="$DESTDIR/usr" \
        --with-ssl="$DESTDIR/usr" \
        --with-zlib="$DESTDIR/usr" \
        --enable-optimize \
        --enable-symbol-hiding \
        --enable-versioned-symbols \
        --enable-threaded-resolver \
        --disable-cookies \
        --disable-crypto-auth \
        --disable-curldebug \
        --disable-dependency-tracking \
        --disable-dict \
        --disable-file \
        --disable-ftp \
        --disable-gopher \
        --disable-imap \
        --disable-ldap \
        --disable-ldaps \
        --disable-libcurl-option \
        --disable-manual \
        --disable-mqtt \
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
        --without-libpsl \
        --without-librtmp \
        --without-winidn \
 && make DESTDIR="$DESTDIR" install \
 && install -Dm755 "$DESTDIR/usr/bin/curl" "$OUTPUT/usr/bin/curl" \
 && cp -aP "$DESTDIR"/usr/lib/*.so* "$OUTPUT/usr/lib"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS combine

ARG OUTPUT
WORKDIR $OUTPUT

COPY --from=plex    "$OUTPUT" .
COPY --from=busybox "$OUTPUT" .
COPY --from=xml     "$OUTPUT" .
COPY --from=curl    "$OUTPUT" .

RUN install -m 1777 -o root -g root -d tmp \
 && ln -sv /usr/lib /usr/bin /usr/sbin . \
    # Link Plex ca-certificates as system store so curl and others can use them too
 && mkdir -p etc/ssl/certs \
 && ln -sv /usr/lib/plexmediaserver/Resources/cacert.pem etc/ssl/certs/ca-certificates.crt \
    # Strip all unneeded symbols for optimum size
 && find . -type f -exec sh -c 'file "{}" | grep -q ELF && strip --strip-debug "{}"' \;

ADD --chmod=755 \
        entrypoint \
        claim-server.sh \
        gen-config.sh \
        plex-util.sh \
        usr/bin/

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM scratch

ARG PLEX_VER
ARG XMLSTAR_VER
ARG BUSYBOX_VER
ARG SU_EXEC_VER
ARG TINI_VER
ARG OPENSSL_VER
ARG CURL_VER
ARG OUTPUT

LABEL org.opencontainers.image.authors="Spritsail <plex@spritsail.io>" \
      org.opencontainers.image.title="Plex Media Server" \
      org.opencontainers.image.url="https://www.plex.tv/downloads/" \
      org.opencontainers.image.description="Tiny Docker image for Plex Media Server, built on busybox" \
      org.opencontainers.image.version=${PLEX_VER} \
      io.spritsail.version.plex=${PLEX_VER} \
      io.spritsail.version.xmlstarlet=${XMLSTAR_VER} \
      io.spritsail.version.busybox=${BUSYBOX_VER} \
      io.spritsail.version.su-exec=${SU_EXEC_VER} \
      io.spritsail.version.tini=${TINI_VER} \
      io.spritsail.version.openssl=${OPENSSL_VER} \
      io.spritsail.version.curl=${CURL_VER}

WORKDIR /usr/lib/plexmediaserver

COPY --from=combine "$OUTPUT" /

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
CMD ["/usr/bin/entrypoint"]
