FROM adamant/alpine-glibc
MAINTAINER Adam Dodman <adam.dodman@gmx.com>

ENV UID=787 UNAME=plex GID=990 GNAME=media
ADD start_pms.patch /tmp/start_pms.patch

WORKDIR /tmp

RUN addgroup -g $GID $GNAME \
 && adduser -SH -u $UID -G $GNAME -s /usr/sbin/nologin $UNAME \

 && apk add --no-cache xz binutils patchelf openssl file \

 && wget -O plexmediaserver.deb 'https://plex.tv/downloads/latest/1?channel=8&build=linux-ubuntu-x86_64&distro=ubuntu' \

 && ar x plexmediaserver.deb \
 && tar -xf data.tar.* \

 && find usr/lib/plexmediaserver -type f -perm /0111 -exec sh -c "file --brief \"{}\" | grep -q "ELF" && patchelf --set-interpreter \"$GLIBC_LD_LINUX_SO\" \"{}\" " \; \

 && mv /tmp/start_pms.patch usr/sbin/ \
 && cd usr/sbin/ \
 && patch < start_pms.patch \
 && cd /tmp \
 && sed -i "s|<destdir>|$DESTDIR|" usr/sbin/start_pms \

 && mv usr/sbin/start_pms $DESTDIR/ \
 && mv usr/lib/plexmediaserver $DESTDIR/plex-media-server \

 && apk del --no-cache xz binutils patchelf file \
 && rm -rf /tmp/*


USER plex

WORKDIR /glibc

CMD ["/glibc/start_pms"]
