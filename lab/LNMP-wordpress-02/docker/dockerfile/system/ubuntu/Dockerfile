FROM ubuntu:22.04

LABEL maintainer="lx" \
      description="This is a mirror based on ubuntu:22.04"

RUN sed -i.orig 's/cn.archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list \
    && apt update \
    && echo -e "6\n70" | apt install -y tzdata \
    && apt autoremove \
    && rm -rf /var/cache/apt/*
