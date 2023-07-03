FROM alpine-base:3.18-01

LABEL maintainer="lx" \
      description="nginx + php-fpm, based on alpine"

ARG NGINX_VERSION="1.24.0"
ARG NGINX_FILE="nginx-${NGINX_VERSION}.tar.gz" \
    PATH_TMP="/tmp/src" \
    PATH_PREFIX="/usr/local/nginx" \
    PATH_PHP_CONF="/etc/php82" \
    PATH_DATA="/data/www" 
   
    
ADD src/${NGINX_FILE} ${PATH_TMP}/

RUN set -x \
    && addgroup -g 124 -S www \
    && adduser -u 124 -S -D -H -s /sbin/nologin -G www -g www www \
    && apk update && apk upgrade \
    && apk add --no-cache build-base openssl-dev pcre-dev zlib-dev wget \
    && mkdir -p ${PATH_PREFIX}/run \
    && cd ${PATH_TMP}/nginx-${NGINX_VERSION} \
    && ./configure \
        --prefix=${PATH_PREFIX} \
        --http-log-path=${PATH_PREFIX}/logs/access.log \
        --error-log-path=${PATH_PREFIX}/logs/error.log \
        --sbin-path=${PATH_PREFIX}/sbin/nginx \
        --pid-path=${PATH_PREFIX}/run/nginx.pid \
        --user=www \
        --group=www \
        --with-http_ssl_module \
        --with-http_gzip_static_module \
        --with-pcre \
        --with-stream \
        --with-stream_ssl_module \
    && make && make install \
    && ln -sv /usr/local/nginx/sbin/nginx /usr/sbin/ \
    && ln -sf /dev/stdout ${PATH_PREFIX}/logs/access.log \
    && ln -sf /dev/stderr ${PATH_PREFIX}/logs/error.log \
    && mkdir -p ${PATH_DATA} && chown -R www:www ${PATH_DATA} \
    && apk add --no-cache php82-fpm=8.2.7-r0 php82-mysqlnd=8.2.7-r0 \
       php82-common=8.2.7-r0 php82-mysqli=8.2.7-r0 php82-session=8.2.7-r0 \
    && rm -rf ${PATH_TMP} \
    && apk del build-base \
    && rm -rf /var/cache/apt/* 

COPY --chown=www:www data/  ${PATH_DATA}
COPY --chown=www:www nginx/conf/  ${PATH_PREFIX}/conf/
COPY --chown=www:www php82/  ${PATH_PHP_CONF}/
COPY --chown=www:www entrypoint.sh  /entrypoint.d/

EXPOSE 80 

ENTRYPOINT ["/entrypoint.d/entrypoint.sh"]
