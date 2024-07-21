# syntax=docker/dockerfile:1

# build openresty
FROM alpine AS builder

ARG OPENRESTY_VERSION
ARG PREFIX="/openresty"
ARG BASENAME="nginx"
ARG CONFIG_PATH="/config"

WORKDIR /tmp/openresty

ADD https://openresty.org/download/openresty-$OPENRESTY_VERSION.tar.gz ../openresty.tar.gz

COPY --chmod=755 deplib/ ../

RUN set -ex; \
    apk add --no-cache --virtual .build-deps \
      linux-headers \
      gd-dev \
      geoip-dev \
      openssl-dev \
      libxml2-dev \
      libxslt-dev
	    luajit-dev \
      pcre-dev \
      perl-dev \
      pkgconf \
      readline-dev \
      zlib-dev \
    ; \
    tar xf ../openresty.tar.gz --strip-components=1; \
    ./configure \
      --prefix=$PREFIX/usr/lib/$BASENAME \
      --sbin-path=$PREFIX/usr/sbin/$BASENAME \
      --modules-path=$PREFIX/usr/lib/$BASENAME/modules \
      --conf-path=$PREFIX/etc/$BASENAME/$BASENAME.conf \
      --pid-path=/var/run/$BASENAME/$BASENAME.pid \
      --lock-path=/var/run/$BASENAME/$BASENAME.lock \
      --error-log-path=$CONFIG_PATH/log/$BASENAME/error.log \
      --http-log-path=$CONFIG_PATH/log/$BASENAME/access.log \
      \
      --http-client-body-temp-path=/var/tmp/$BASENAME/client_body \
      --http-proxy-temp-path=/var/tmp/$BASENAME/proxy \
      --http-fastcgi-temp-path=/var/tmp/$BASENAME/fastcgi \
      --http-uwsgi-temp-path=/var/tmp/$BASENAME/uwsgi \
      --http-scgi-temp-path=/var/tmp/$BASENAME/scgi \
      --with-perl_modules_path=/usr/lib/perl5/vendor_perl \
      \
      --user=$BASENAME \
      --group=$BASENAME \
      \
      --with-compat \
      --with-file-aio \
      --with-http_addition_module \
      --with-http_auth_request_module \
      --with-http_dav_module \
      --with-http_degradation_module \
      --with-http_flv_module \
      --with-http_geoip_module=dynamic \
      --with-http_gunzip_module \
      --with-http_gzip_static_module \
      --with-http_image_filter_module=dynamic \
      --with-http_mp4_module \
      --with-http_perl_module=dynamic \
      --with-http_random_index_module \
      --with-http_realip_module \
      --with-http_secure_link_module \
      --with-http_slice_module \
      --with-http_ssl_module \
      --with-http_stub_status_module \
      --with-http_sub_module \
      --with-http_v2_module \
      --with-http_v3_module \
      --with-http_xslt_module=dynamic \
      --with-ipv6 \
      --with-mail=dynamic \
      --with-mail_ssl_module \
      --with-md5-asm \
      --with-pcre-jit \
      --with-sha1-asm \
      --with-stream=dynamic \
      --with-stream_geoip_module=dynamic \
      --with-stream_realip_module \
      --with-stream_ssl_module \
      --with-stream_ssl_preread_module \
      --with-threads \
    ; \
    make -j $(nproc) install; \
    \
    # build ffmpeg lib files
    ../cplibfiles.sh $PREFIX/sbin/nginx $PREFIX/library; \
    apk del --no-network .build-deps; \
    rm -rf \
        /var/cache/apk/* \
        /var/tmp/* \
        ../* \
    ;

# Build the final combined image
FROM clion007/alpine

LABEL mantainer="Clion Nihe Email: clion007@126.com"

ARG BRANCH="edge"
ARG JELLYFIN_PATH=/usr/lib/openresty/
ARG JELLYFIN_WEB_PATH=/usr/share/openresty-web/

# Default environment variables for the Jellyfin invocation
ENV JELLYFIN_LOG_DIR=/config/log \
    JELLYFIN_DATA_DIR=/config/data \
    JELLYFIN_CACHE_DIR=/config/cache \
    JELLYFIN_CONFIG_DIR=/config/config \
    JELLYFIN_WEB_DIR=/usr/share/openresty-web \
    XDG_CACHE_HOME=${JELLYFIN_CACHE_DIR}

# add openresty files
COPY --from=server /server $JELLYFIN_PATH
COPY --from=web /web $JELLYFIN_WEB_PATH
COPY --from=ffmpeg /ffmpeg/bin /usr/bin/
COPY --from=ffmpeg /ffmpeg/library /

# add local files
COPY --chmod=755 root/ /

# install packages
RUN set -ex; \
  apk add --no-cache \
    --repository=http://dl-cdn.alpinelinux.org/alpine/$BRANCH/main \
    --repository=http://dl-cdn.alpinelinux.org/alpine/$BRANCH/community \
    su-exec \
    logrotate \
    apache2-utils \
  ; \
  apk add --no-cache --virtual .user-deps \
    shadow \
  ; \
  \
  # set openresty process user and group
  groupadd -g 101 openresty; \
  useradd -u 100 -s /bin/nologin -M -g 101 openresty; \
  ln -s /usr/lib/openresty/openresty /usr/bin/openresty; \
  chown openresty:openresty /usr/bin/openresty; \
  \
  # make dir for config and data
  mkdir -p /config; \
  chown openresty:openresty /config; \
  \
  apk del --no-network .user-deps; \
  rm -rf \
      /var/cache/apk/* \
      /var/tmp/* \
      /tmp/* \
  ;
  
# ports
EXPOSE 8096 8920 7359/udp 1900/udp

# entrypoint set in clion007/alpine base image
CMD ["--ffmpeg=/usr/bin/ffmpeg"]
