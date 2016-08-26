FROM alpine:3.4
MAINTAINER Adam Dodman <adam.dodman@gmx.com>

ENV UID=787 UNAME=plex GID=990 GNAME=media DESTDIR="/plex"
ENV GLIBC_LIBRARY_PATH="/plex/lib" GLIBC_LD_LINUX_SO="/plex/lib/ld-linux-x86-64.so.2"

ADD start_pms.patch /tmp/start_pms.patch

WORKDIR /tmp

RUN addgroup -g $GID $GNAME \
 && adduser -SH -u $UID -G $GNAME -s /usr/sbin/nologin $UNAME \

 && echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \
 && apk add --no-cache xz binutils patchelf openssl file \

 && wget http://ftp.debian.org/debian/pool/main/g/glibc/libc6_2.23-5_amd64.deb \
 && wget http://ftp.debian.org/debian/pool/main/g/gcc-4.9/libgcc1_4.9.2-10_amd64.deb \
 && wget http://ftp.debian.org/debian/pool/main/g/gcc-4.9/libstdc++6_4.9.2-10_amd64.deb \
 && wget -O plexmediaserver.deb 'https://plex.tv/downloads/latest/1?channel=8&build=linux-ubuntu-x86_64&distro=ubuntu' \

 && for pkg in libc6 libgcc1 libstdc++6 plexmediaserver; do \
        mkdir $pkg; \
        cd $pkg; \
        ar x ../$pkg*.deb; \
        tar -xf data.tar.*; \
        cd ..; \
    done \

 && mkdir -p $GLIBC_LIBRARY_PATH \

 && mv libc6/lib/x86_64-linux-gnu/* $GLIBC_LIBRARY_PATH \
 && mv libgcc1/lib/x86_64-linux-gnu/* $GLIBC_LIBRARY_PATH \
 && mv libstdc++6/usr/lib/x86_64-linux-gnu/* $GLIBC_LIBRARY_PATH \

 && find plexmediaserver/usr/lib/plexmediaserver -type f -perm /0111 -exec sh -c "file --brief \"{}\" | grep -q "ELF" && patchelf --set-interpreter \"$GLIBC_LD_LINUX_SO\" \"{}\" " \; \

 && mv /tmp/start_pms.patch plexmediaserver/usr/sbin/ \
 && cd plexmediaserver/usr/sbin/ \
 && patch < start_pms.patch \
 && cd /tmp \
 && sed -i "s|<destdir>|$DESTDIR|" plexmediaserver/usr/sbin/start_pms \

 && mv plexmediaserver/usr/sbin/start_pms $DESTDIR/ \
 && mv plexmediaserver/usr/lib/plexmediaserver $DESTDIR/plex-media-server \

 && apk del --no-cache xz binutils patchelf file \
 && rm -rf /tmp/*


USER plex

WORKDIR /plex

CMD ["/plex/start_pms"]
