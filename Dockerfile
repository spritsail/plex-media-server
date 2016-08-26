FROM alpine:3.4
MAINTAINER Adam Dodman <adam.dodman@gmx.com>

ENV UID=787 UNAME=plex GID=990 GNAME=media
ENV debs "libc6 libgcc1 libstdc++6 plexmediaserver"
ENV destdir "/plex"

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

 && for pkg in $debs; do \
        mkdir $pkg; \
        cd $pkg; \
        ar x ../$pkg*.deb; \
        tar -xf data.tar.*; \
        cd ..; \
    done \

 && mkdir -p $destdir/lib \

 && mv libc6/lib/x86_64-linux-gnu/* $destdir/lib \
 && mv libgcc1/lib/x86_64-linux-gnu/* $destdir/lib \
 && mv libstdc++6/usr/lib/x86_64-linux-gnu/* $destdir/lib \

 && echo "export GLIBC_LIBRARY_PATH=/plex/lib" >"$destdir/lib/vars.sh" \
 && echo "export GLIBC_LD_LINUX_SO=/plex/lib/ld-linux-x86-64.so.2" >>"$destdir/lib/vars.sh" \
 && chmod +x $destdir/lib/vars.sh \

 && . $destdir/lib/vars.sh \

 && find plexmediaserver/usr/lib/plexmediaserver -type f -perm /0111 -exec sh -c "file --brief \"{}\" | grep -q "ELF" && patchelf --set-interpreter \"$GLIBC_LD_LINUX_SO\" \"{}\" " \; \

 && mv /tmp/start_pms.patch plexmediaserver/usr/sbin/ \
 && cd plexmediaserver/usr/sbin/ \
 && patch < start_pms.patch \
 && cd /tmp \
 && sed -i "s|<destdir>|$destdir|" plexmediaserver/usr/sbin/start_pms \

 && mv plexmediaserver/usr/sbin/start_pms $destdir/ \
 && mv plexmediaserver/usr/lib/plexmediaserver $destdir/plex-media-server \

 && apk del --no-cache xz binutils patchelf file \
 && rm -rf /tmp/*


USER plex

WORKDIR ["/plex"]

CMD ["/plex/start_pms"]
