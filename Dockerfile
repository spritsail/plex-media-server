FROM spritsail/libressl

ARG PLEX_VER=1.13.2.5154-fd05be322
ARG PLEX_SHA=81ff7f8d80ac46ca663a54e09667ad47a2ccb1cd
ARG LIBSTDCPP_VER=6.3.0-18+deb9u1
ARG LIBGCC1_VER=6.3.0-18+deb9u1

LABEL maintainer="Spritsail <plex@spritsail.io>" \
      org.label-schema.vendor="Spritsail" \
      org.label-schema.name="Plex Media Server" \
      org.label-schema.url="https://www.plex.tv/downloads/" \
      org.label-schema.description="Tiny Docker image for Plex Media Server, built on busybox" \
      org.label-schema.version=${PLEX_VER} \
      io.spritsail.version.plex=${PLEX_VER} \
      io.spritsail.version.libstdcpp=${LIBSTDCPP_VER} \
      io.spritsail.version.libgcc1=${LIBGCC1_VER}

ENV SUID=900 SGID=900
ADD start_pms /usr/sbin/start_pms

WORKDIR /tmp

RUN chmod +x /usr/sbin/start_pms \
 && wget http://ftp.de.debian.org/debian/pool/main/g/gcc-${LIBSTDCPP_VER:0:1}/libstdc++6_${LIBSTDCPP_VER}_amd64.deb \
 && wget http://ftp.de.debian.org/debian/pool/main/g/gcc-${LIBGCC1_VER:0:1}/libgcc1_${LIBGCC1_VER}_amd64.deb \
 && dpkg-deb -x libstdc++6*.deb . \
 && dpkg-deb -x libgcc1*.deb . \
 # We only need the lib files, everything else is debian junk.
 && mv $PWD/usr/lib/x86_64-linux-gnu/* /lib \
 && mv $PWD/lib/x86_64-linux-gnu/* /lib \
 && echo "$PLEX_SHA  plexmediaserver.deb" > sumfile \
 && wget -O plexmediaserver.deb https://downloads.plex.tv/plex-media-server/${PLEX_VER}/plexmediaserver_${PLEX_VER}_amd64.deb \
 && sha1sum -c sumfile \
 && dpkg-deb -x plexmediaserver.deb . \
 && mv usr/lib/plexmediaserver /usr/lib \
 && find $PWD -mindepth 1 -delete

HEALTHCHECK --interval=10s --timeout=5s \
    CMD [ "wget", "-O", "/dev/null", "-T", "10", "-q", "localhost:32400/identity" ]

WORKDIR /usr/lib/plexmediaserver

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["start_pms"]
