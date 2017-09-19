FROM adamant/busybox:libressl
MAINTAINER Adam Dodman <adam.dodman@gmx.com>

ENV UID=900 GID=900
ADD start_pms /usr/sbin/start_pms

WORKDIR /tmp

ARG PLEX_VER

RUN set -ax \
 && wget http://ftp.de.debian.org/debian/pool/main/g/gcc-6/libstdc++6_6.3.0-18_amd64.deb \
 && wget http://ftp.de.debian.org/debian/pool/main/g/gcc-6/libgcc1_6.3.0-18_amd64.deb \
 && dpkg-deb -x libstdc++6*.deb . \
 && dpkg-deb -x libgcc1*.deb . \
 # We only need the lib files, everything else is debian junk.
 && mv /tmp/usr/lib/x86_64-linux-gnu/* /lib \
 && mv /tmp/lib/x86_64-linux-gnu/* /lib \
 && if [ -z "$PLEX_VER" ]; then \
        export PLEX_VER=$(wget -qO- https://adam-ant.co.uk/plex/version.php | sed -n 's/.*"release":\s*"\([^"]*\)".*/\1/p'); \
    fi \
 && wget -O plexmediaserver.deb "https://downloads.plex.tv/plex-media-server/$PLEX_VER/plexmediaserver_"$PLEX_VER"_amd64.deb" \
 && dpkg-deb -x plexmediaserver.deb . \
 # Move usr/lib/plexmediaserver. Everything else is useless
 && mv usr/lib/plexmediaserver /usr/lib \
 && chmod +x /usr/sbin/start_pms \
 && find /tmp -mindepth 1 -delete

WORKDIR /usr/lib/plexmediaserver

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["start_pms"]
