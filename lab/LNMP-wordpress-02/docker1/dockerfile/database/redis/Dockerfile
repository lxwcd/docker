FROM alpine-base:3.18-01
# FROM alpine-base:3.18-01
# FROM alpine-base:3.18-01
# FROM alpine-base:3.18-01
# FROM alpine-base:3.18-01

LABEL maintainer="lx" \
      description="redis based on alpine" \
      reference="https://github.com/docker-library/redis/tree/7ef4e925387c9c4063b25e83928a85ff44dddf4d"

ARG REDIS_VERSION="7.0.11"
ARG REDIS_FILE="${REDIS_VERSION}.tar.gz" \
    PATH_TMP="/tmp/src" \
    PATH_PREFIX="/usr/local/redis" \
    UID="998" \
    USER="redis" \
    GID="998" \
    GROUP="redis" 
   
    
ADD src/${REDIS_FILE} ${PATH_TMP}/

# need to install elogind-dev and can't remove it 
RUN set -eux \
    && addgroup -g $GID -S $GROUP \
    && adduser -u $UID -S -D -H -s /sbin/nologin -G $GROUP -g $GROUP $USER \
    && apk update && apk upgrade \
    && apk add --no-cache --virtual .build-deps \
		coreutils \
        dpkg-dev dpkg \
		gcc \
		linux-headers \
		make \
		musl-dev \
		openssl-dev \
    && apk add --no-cache elogind-dev \
    && mkdir -p ${PATH_PREFIX}/run \
    && cd ${PATH_TMP}/redis-${REDIS_VERSION} \
    && make PREFIX=${PATH_PREFIX} install \
    && ln -s ${PATH_PREFIX}/bin/redis-*  /usr/local/bin/ \
    && apk del --no-network .build-deps \
    && rm -rf /var/cache/apk/* 

COPY --chown=${UID}:${GID} init_data/  ${PATH_PREFIX}
COPY entrypoint.sh  /entrypoint.d/

ENTRYPOINT ["/entrypoint.d/entrypoint.sh"]
#CMD ["cat /etc/issue"]
