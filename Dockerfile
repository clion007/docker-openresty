# syntax=docker/dockerfile:1

# build openresty
FROM alpine AS builder

ARG OPENRESTY_VERSION

WORKDIR /tmp/openresty

ADD https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz ../openresty.tar.gz

COPY --chmod=755 deplib/ ../

RUN set -ex; \
    apk add --no-cache --virtual .build-deps \
      build-base \
      coreutils \
      gd-dev \
      geoip-dev \
      libxml2-dev \
      libxslt-dev \
      linux-headers \
	    luajit-dev \
      openssl-dev \
      pcre-dev \
      perl-dev \
      readline-dev \
      zlib-dev \
    ; \
    tar xf ../openresty.tar.gz --strip-components=1; \
    ./configure \
      --prefix=/usr/lib/nginx \
      --sbin-path=/usr/sbin/nginx \
      --modules-path=/usr/lib/nginx/modules \
      --conf-path=/etc/nginx/nginx.conf \
      --pid-path=/var/run/nginx/nginx.pid \
      --lock-path=/var/run/nginx/nginx.lock \
      --error-log-path=/config/log/nginx/error.log \
      --http-log-path=/config/log/nginx/access.log \
      \
      --with-perl_modules_path=/usr/lib/perl5/vendor_perl \
      \
      --user=nginx \
      --group=nginx \
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
      --with-luajit-xcflags='-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT' \
    ; \
    make -j ${nproc}; \
    make -j $(nproc) install; \
    \
    mkdir -p /openresty/etc/nginx \
      /openresty/usr/sbin \
      /openresty/usr/lib/nginx \
      /openresty/usr/lib/perl5; \
    \
    cp -r -L -n /etc/nginx/* /openresty/etc/nginx/; \
    cp -r -L -n /usr/lib/nginx/* /openresty/usr/lib/nginx/; \
    cp -r -L -n /usr/sbin/nginx /openresty/usr/sbin/nginx; \
    cp -r -L -n /usr/lib/perl5/* /openresty/usr/lib/perl5/; \
    \
    # build lib files
    ../cplibfiles.sh /usr/lib/nginx/bin/openresty /library; \
    apk del --no-network .build-deps; \
    rm -rf \
        /var/cache/apk/* \
        /var/tmp/* \
        ../* \
    ;

    # build luarocks
    FROM alpine AS luarocks
    
    ARG LUAROCKS_VERSION
    
    WORKDIR /tmp/luarocks
    
    ADD https://luarocks.github.io/luarocks/releases/luarocks-${LUAROCKS_VERSION}.tar.gz ../luarocks.tar.gz
    
    COPY --from=builder /openresty /
    COPY --from=builder /library /
    
    RUN set -ex; \
        apk add --no-cache --virtual .build-deps \
          perl-dev \
          build-base \
          linux-headers \
        ; \
        tar xf ../luarocks.tar.gz --strip-components=1; \
        ./configure \
          --prefix=/usr \
          --sysconfdir=/etc \
          --rocks-tree=/usr/local \
          --with-lua=/usr/lib/nginx/luajit \
          --with-lua-include=/usr/lib/nginx/luajit/include/luajit-2.1 \
        ; \
        make -j ${nproc}; \
        make -j $(nproc) install; \
        \
        mkdir -p /luarocks/etc/luarocks \
          /luarocks/usr/bin \
          /luarocks/usr/share/lua; \
        \
        cp -r -L -n /etc/luarocks/* /luarocks/etc/luarocks/; \
        cp -r -L -n /usr/bin/luarock* /luarocks/usr/bin/; \
        cp -r -L -n /usr/share/lua/* /luarocks/usr/share/lua/; \
        \
        # fix https://gitlab.alpinelinux.org/alpine/aports/-/merge_requests/48613 issues
        sed -i '/WGET/d' /luarocks/usr/share/lua/5.1/luarocks/fs/tools.lua; \
        \
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

# Add additional binaries into PATH for convenience
ENV PATH=$PATH:/usr/lib/nginx/luajit/bin:/usr/lib/nginx/bin
ENV LUA_PATH="/usr/lib/nginx/lualib/?.lua;/usr/lib/nginx/lualib/?/init.lua;./?.lua;/usr/share/luajit-2.1/?.lua;/usr/share/lua/5.1/?.lua"
ENV LUA_CPATH="/usr/lib/nginx/lualib/?.so;/usr/lib/nginx/lualib/?/?.so;./?.so;/usr/lib/lua/5.1/?.so"

# add openresty files
COPY --from=builder /openresty /
COPY --from=builder /library /
COPY --from=luarocks /luarocks /

# add local files
COPY --chmod=755 root/ /

# install packages
RUN set -ex; \
  apk add --no-cache \
    --repository=http://dl-cdn.alpinelinux.org/alpine/$BRANCH/main \
    --repository=http://dl-cdn.alpinelinux.org/alpine/$BRANCH/community \
    curl \
    pcre \
    perl \
    geoip \
    logrotate \
  ; \
  apk add --no-cache --virtual .user-deps \
    shadow \
  ; \
  \
  luarocks install lua-resty-t1k; \
  \
  # set openresty process user and group
  groupadd -g 101 nginx; \
  useradd -u 100 -s /bin/nologin -M -g 101 nginx; \
  chown nginx:nginx /usr/lib/nginx/bin/openresty; \
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
CMD ["-g","daemon off;"]
