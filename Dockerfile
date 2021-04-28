ARG PLEX_VER=1.23.0.4482-62106842a
ARG PLEX_SHA=022f2ac2a18ec602f0402baf94d69f405b9207a4
ARG BUSYBOX_VER=1.33.0
ARG SU_EXEC_VER=0.4
ARG TINI_VER=0.19.0
ARG ZLIB_VER=1.2.11
ARG LIBXML2_VER=v2.9.10
ARG LIBXSLT_VER=v1.1.34
ARG XMLSTAR_VER=1.6.1
ARG OPENSSL_VER=1.1.1i
ARG CURL_VER=curl-7_76_1

ARG OUTPUT=/output
ARG DESTDIR=/prefix

ARG CFLAGS="-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=2 -flto"
ARG LDFLAGS="$CFLAGS -Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM spritsail/alpine:3.13 AS builder

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
        xxd

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS plex

ARG PLEX_VER
ARG PLEX_SHA
ARG OUTPUT

WORKDIR $OUTPUT

# Fetch Plex and required libraries
RUN curl -fsSL -o plexmediaserver.deb https://downloads.plex.tv/plex-media-server-new/${PLEX_VER}/debian/plexmediaserver_${PLEX_VER}_amd64.deb \
 && echo "$PLEX_SHA  plexmediaserver.deb" | sha1sum -c - \
 && dpkg-deb -x plexmediaserver.deb . \
    \
 && rm -r \
        etc/ usr/share/ \
        plexmediaserver.deb \
    \
 && cd usr/lib/plexmediaserver \
 && rm \
        lib/libcrypto.so* \
        lib/libcurl.so* \
        lib/libssl.so* \
        lib/libnghttp2.so* \
        lib/libxml2.so* \
        lib/libxslt.so* \
        lib/libexslt.so* \
        lib/plexmediaserver.* \
        etc/ld-musl-x86_64.path \
        Resources/start.sh \
    \
    # Place shared libraries in usr/lib so they can be actually shared
 && mv lib/*.so* lib/dri ../ \
 && rmdir lib etc \
 && ln -sv ../ lib \
    # Replace hardlink with a symlink; these files are the same
 && cd .. && ln -sfvn ld-musl-x86_64.so.1 libc.so

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS busybox

ARG BUSYBOX_VER
ARG SU_EXEC_VER
ARG TINI_VER
ARG CFLAGS
ARG LDFLAGS
ARG MAKEFLAGS
ARG OUTPUT

WORKDIR /tmp/busybox

RUN curl -fsSL https://busybox.net/downloads/busybox-${BUSYBOX_VER}.tar.bz2 \
        | tar xj --strip-components=1 \
 && make defconfig \
 && make \
 && install -Dm755 busybox "$OUTPUT/usr/bin/busybox" \
    # "Install" busybox, creating symlinks to all binaries it provides
 && mkdir -p "$OUTPUT/usr/bin" "$OUTPUT/usr/sbin" \
 && ./busybox --list-full | sed -E 's@^(s?bin)@usr/\1@' | xargs -i ln -Tsv /usr/bin/busybox "$OUTPUT/{}"

WORKDIR /tmp/su-exec

RUN curl -fL https://github.com/frebib/su-exec/archive/v${SU_EXEC_VER}.tar.gz \
        | tar xz --strip-components=1 \
 && make \
 && install -Dm755 su-exec "$OUTPUT/usr/sbin/su-exec"

WORKDIR /tmp/tini

RUN curl -fL https://github.com/krallin/tini/archive/v${TINI_VER}.tar.gz \
        | tar xz --strip-components=1 \
 && cmake . \
 && make tini \
 && install -Dm755 tini "$OUTPUT/usr/sbin/tini"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS zlib

ARG ZLIB_VER
ARG CFLAGS
ARG LDFLAGS
ARG MAKEFLAGS
ARG OUTPUT
ARG DESTDIR

WORKDIR /tmp/zlib

RUN curl -sSf https://www.zlib.net/zlib-$ZLIB_VER.tar.xz \
        | tar xJ --strip-components=1 \
 && ./configure \
        --prefix=/usr \
        --shared \
 && make DESTDIR="$DESTDIR" install \
 && mkdir -p "$OUTPUT/usr/lib" \
 && cp -a "$DESTDIR"/usr/lib/*.so* "$OUTPUT/usr/lib"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS xml

ARG LIBXML2_VER
ARG LIBXSLT_VER
ARG XMLSTAR_VER
ARG CFLAGS
ARG LDFLAGS
ARG MAKEFLAGS
ARG OUTPUT
ARG DESTDIR

COPY --from=zlib "$DESTDIR" "$DESTDIR"

WORKDIR /tmp/libxml2
RUN git clone https://gitlab.gnome.org/GNOME/libxml2.git --branch $LIBXML2_VER --depth 1 . \
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
 && make DESTDIR="$DESTDIR" install \
 && mkdir -p "$OUTPUT/usr/lib" \
 && cp -a "$DESTDIR"/usr/lib/*.so* "$OUTPUT/usr/lib"

WORKDIR /tmp/libxslt
RUN git clone https://gitlab.gnome.org/GNOME/libxslt.git --branch $LIBXSLT_VER --depth 1 . \
 && ./autogen.sh \
        --prefix=/usr \
        --with-libxml-src=../libxml2 \
        --without-crypto \
        --without-plugins \
        --without-python \
 && make DESTDIR="$DESTDIR" install \
 && mkdir -p "$OUTPUT/usr/lib" \
 && cp -a "$DESTDIR"/usr/lib/*.so* "$OUTPUT/usr/lib"

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

FROM builder AS curl

ARG OPENSSL_VER
ARG CURL_VER
ARG CFLAGS
ARG LDFLAGS
ARG MAKEFLAGS
ARG OUTPUT
ARG DESTDIR

COPY --from=zlib "$DESTDIR" "$DESTDIR"

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
 && make build_libs \
 && make build_programs \
 && make DESTDIR="$DESTDIR" \
    install_sw \
    install_ssldirs \
 && mkdir -p "$OUTPUT/usr/lib" \
 && cp -a "$DESTDIR"/usr/lib/*.so* "$OUTPUT/usr/lib" \
 && sed -i "s@prefix=/usr@prefix=$DESTDIR/usr@g" "$DESTDIR"/usr/lib/pkgconfig/*.pc

# /usr/lib # curl --version
# curl 7.74.0-DEV (x86_64-pc-linux-musl) libcurl/7.73.0-DEV OpenSSL/1.1.1i zlib/1.2.11 nghttp2/1.41.0
# Protocols: http https
# Features: AsynchDNS HTTP2 HTTPS-proxy IPv6 Largefile libz SSL UnixSockets

WORKDIR /tmp/curl
RUN git clone https://github.com/curl/curl.git --branch $CURL_VER --depth 1 . \
 && autoreconf -sif \
 && ./configure \
        --prefix=/usr \
        --enable-http \
        --enable-ipv6 \
        --enable-largefile \
        --enable-proxy \
        --enable-unix-sockets \
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
        --without-libmetalink \
        --without-libpsl \
        --without-librtmp \
        --without-winidn \
 && make DESTDIR="$DESTDIR" install \
 && install -Dm755 "$DESTDIR/usr/bin/curl" "$OUTPUT/usr/bin/curl" \
    # Cheat and "borrow" libnghttp2 from Alpine
 && mkdir -p "$OUTPUT/usr/lib" \
 && cp -a "$DESTDIR"/usr/lib/*.so* /usr/lib/libnghttp2.so* "$OUTPUT/usr/lib"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS combine

ARG OUTPUT
WORKDIR $OUTPUT

COPY --from=plex    "$OUTPUT" .
COPY --from=busybox "$OUTPUT" .
COPY --from=zlib    "$OUTPUT" .
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

LABEL maintainer="Spritsail <plex@spritsail.io>" \
      org.label-schema.vendor="Spritsail" \
      org.label-schema.name="Plex Media Server" \
      org.label-schema.url="https://www.plex.tv/downloads/" \
      org.label-schema.description="Tiny Docker image for Plex Media Server, built on busybox" \
      org.label-schema.version=${PLEX_VER} \
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
