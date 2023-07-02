FROM alpine:3.18

LABEL maintainer="lx" \
      description="This is a mirror based on alpine:3.18"

RUN sed -i.orig 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/' /etc/apk/repositories \
    && apk add --no-cache tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && apk del tzdata \
    && apk cache clean \
    && rm -rf /var/cache/apk/*
