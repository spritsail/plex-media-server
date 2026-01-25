ARG PLEX_VER=1.41.9.9961-46083195d

ARG OUTPUT=/output
ARG DESTDIR=/prefix

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM spritsail/alpine:3.23 AS plex

ARG PLEX_VER
ARG OUTPUT

WORKDIR $OUTPUT

# Fetch Plex and required libraries
RUN apk add --no-cache curl dpkg \
 && if [ "$(uname -m)" = "aarch64" ]; then \
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

FROM spritsail/alpine:3.23

RUN apk add --no-cache \
        curl \
        libcrypto3 \
        libssl3 \
        nghttp2-libs \
        xmlstarlet

ARG PLEX_VER
ARG OUTPUT

LABEL org.opencontainers.image.authors="Spritsail <plex@spritsail.io>" \
      org.opencontainers.image.title="Plex Media Server" \
      org.opencontainers.image.url="https://www.plex.tv/downloads/" \
      org.opencontainers.image.description="Tiny Docker image for Plex Media Server, built on busybox" \
      org.opencontainers.image.version=${PLEX_VER} \
      io.spritsail.version.plex=${PLEX_VER}

WORKDIR /usr/lib/plexmediaserver

COPY --from=plex "$OUTPUT" /

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
