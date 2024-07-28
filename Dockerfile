# syntax=docker/dockerfile:1

# build openresty
FROM alpine AS builder

ARG OPENRESTY_VERSION
ARG PREFIX="/openresty"
ARG BASENAME="nginx"
ARG CONFIG_PATH="/config"

WORKDIR /tmp/openresty

ADD https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz ../openresty.tar.gz

COPY --chmod=755 deplib/ ../

RUN set -ex; \
    apk add --no-cache --virtual .build-deps \
      linux-headers \
      gd-dev \
      geoip-dev \
      openssl-dev \
      libxml2-dev \
      libxslt-dev \
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
      --with-stream \
      --with-stream_geoip_module=dynamic \
      --with-stream_realip_module \
      --with-stream_ssl_module \
      --with-stream_ssl_preread_module \
      --with-threads \
    ; \
    make -j ${nproc}; \
    make -j $(nproc) install; \
    \
    # build ffmpeg lib files
    ../cplibfiles.sh $PREFIX/usr/lib/nginx/bin/openresty /library; \
    apk del --no-network .build-deps; \
    rm -rf \
        /var/cache/apk/* \
        /var/tmp/* \
        ../* \
    ;

    # build luarocks
    FROM alpine AS luarocks
    
    ARG LUAROCKS_VERSION
    ARG PREFIX="/luarocks"
    
    WORKDIR /tmp/luarocks
    
    ADD https://luarocks.github.io/luarocks/releases/luarocks-${LUAROCKS_VERSION}.tar.gz ../luarocks.tar.gz
    
    COPY --chmod=755 deplib/ ../
    
    RUN set -ex; \
        apk add --no-cache --virtual .build-deps \
          perl-dev \
          build-base \ 
          linux-headers \
        ; \
        tar xf ../luarocks.tar.gz --strip-components=1; \
        ./configure \
          --prefix=$PREFIX/usr \
          --sysconfdir=$PREFIX/etc \
          --rocks-tree=$PREFIX/usr/local \
          --with-lua=$PREFIX/usr \
			    --with-lua-lib=$PREFIX/usr \
        ; \
        make -j ${nproc}; \
        make -j $(nproc) install; \
        \
        # build ffmpeg lib files
        ../cplibfiles.sh $PREFIX/bin/luarocks /library; \
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

# add openresty files
COPY --from=builder /openresty /
COPY --from=builder /library /
COPY --from=luarocks /luarocks /
COPY --from=luarocks /library /

# add local files
COPY --chmod=755 root/ /

# install packages
RUN set -ex; \
  apk add --no-cache \
    --repository=http://dl-cdn.alpinelinux.org/alpine/$BRANCH/main \
    --repository=http://dl-cdn.alpinelinux.org/alpine/$BRANCH/community \
    pcre \
    perl \
    geoip \
    luajit \
    logrotate \
  ; \
  apk add --no-cache --virtual .user-deps \
    shadow \
  ; \
  \
  luarocks install lua-resty-t1k --server https://luarocks.cn; \
  \
  # set openresty process user and group
  groupadd -g 101 nginx; \
  useradd -u 100 -s /bin/nologin -M -g 101 nginx; \
  ln -s /usr/lib/nginx/bin/openresty /usr/bin/openresty; \
  chown nginx:nginx /usr/bin/openresty; \
  \
  # make dir for config and data
  mkdir -p /config; \
  chown nginx:nginx /config; \
  \  
  # configure nginx
  echo '# https://httpoxy.org/\n\
fastcgi_param  HTTP_PROXY         "";\n\
# http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html#fastcgi_split_path_info\n\
fastcgi_param  PATH_INFO          $fastcgi_path_info;\n\
# https://www.nginx.com/resources/wiki/start/topics/examples/phpfcgi/#connecting-nginx-to-php-fpm\n\
fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name;\n\
# Send HTTP_HOST as SERVER_NAME. If HTTP_HOST is blank, send the value of server_name from nginx (default is `_`)\n\
fastcgi_param  SERVER_NAME        $host;' >> \
    /etc/nginx/fastcgi_params; \

  # fix logrotate
  sed -i "s#/var/log/messages {}.*# #g" \
    /etc/logrotate.conf; \
  sed -i 's#/usr/sbin/logrotate /etc/logrotate.conf#/usr/sbin/logrotate /etc/logrotate.conf -s /config/log/logrotate.status#g' \
    /etc/periodic/daily/logrotate; \
  \
  apk del --no-network .user-deps; \
  rm -rf \
      /var/cache/apk/* \
      /var/tmp/* \
      /tmp/* \
  ;

# ports
EXPOSE 80 443 8080 8443

# Use SIGQUIT instead of default SIGTERM to cleanly drain requests
# See https://github.com/openresty/docker-openresty/blob/master/README.md#tips--pitfalls
STOPSIGNAL SIGQUIT

# entrypoint set in clion007/alpine base image
CMD [""-g","daemon off;""]
