FROM adamant/busybox
MAINTAINER Adam Dodman <adam.dodman@gmx.com>

ENV UID=787 GID=990
ADD start_pms.patch /tmp/start_pms.patch

WORKDIR /tmp

RUN wget http://ftp.de.debian.org/debian/pool/main/g/gcc-4.9/libstdc++6_4.9.2-10_amd64.deb \
 && pkgextract libstdc++6*.deb \
 && wget -O plexmediaserver.deb 'https://plex.tv/downloads/latest/1?channel=8&build=linux-ubuntu-x86_64&distro=ubuntu' \
 && dpkg-deb -x plexmediaserver.deb . \
 # Move usr/lib and start_pms. Everything else is useless
 && mv usr/lib/plexmediaserver /usr/lib \
 && mv usr/sbin/start_pms /usr/sbin \
 && patch /usr/sbin/start_pms < /tmp/start_pms.patch \
 && find /tmp -mindepth 1 -delete

WORKDIR /usr/lib/plexmediaserver

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["su-exec", "$UID:$GID", "start_pms"]
