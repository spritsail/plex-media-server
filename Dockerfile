FROM spritsail/busybox:libressl

ARG PLEX_VER=latest
ARG PLEX_URL
ARG LIBSTDCPP_VER=8-20180312-2
ARG LIBGCC1_VER=8-20180312-2

LABEL maintainer="Spritsail <plex@spritsail.io>" \
      org.label-schema.vendor="Spritsail" \
      org.label-schema.name="Plex Media Server" \
      org.label-schema.url="https://www.plex.tv/downloads/" \
      org.label-schema.description="Tiny Docker image for Plex Media Server, built on spritsail/busybox" \
      org.label-schema.version=$PLEX_VER

ENV SUID=900 SGID=900
ADD start_pms /usr/sbin/start_pms

WORKDIR /tmp

RUN chmod +x /usr/sbin/start_pms \
 && wget http://ftp.de.debian.org/debian/pool/main/g/gcc-8/libstdc++6_${LIBSTDCPP_VER}_amd64.deb \
 && wget http://ftp.de.debian.org/debian/pool/main/g/gcc-8/libgcc1_${LIBGCC1_VER}_amd64.deb \
 && dpkg-deb -x libstdc++6*.deb . \
 && dpkg-deb -x libgcc1*.deb . \
 # We only need the lib files, everything else is debian junk.
 && mv $PWD/usr/lib/x86_64-linux-gnu/* /lib \
 && mv $PWD/lib/x86_64-linux-gnu/* /lib \
 \
 && if [ "$PLEX_VER" == "latest" -o -z "$PLEX_URL" ]; then \
        export PLEX_VER="$(wget -qO- https://spritsail.io/plex/release.php?raw=version)"; \
        export PLEX_URL="$(wget -qO- https://spritsail.io/plex/release.php?raw=url-deb)"; \
        export PLEX_SHA="$(wget -qO- https://spritsail.io/plex/release.php?raw=csum-deb)"; \
    fi \
 && echo "$PLEX_SHA  plexmediaserver.deb" > sumfile \
 && wget -O plexmediaserver.deb "$PLEX_URL" \
 && sha1sum -c sumfile \
 \
 && dpkg-deb -x plexmediaserver.deb . \
 && mv usr/lib/plexmediaserver /usr/lib \
 && find $PWD -mindepth 1 -delete

HEALTHCHECK --interval=10s --timeout=5s \
    CMD [ "wget", "-O", "/dev/null", "-T", "10", "-q", "localhost:32400/identity" ]

WORKDIR /usr/lib/plexmediaserver

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["start_pms"]
