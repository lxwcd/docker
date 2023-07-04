#!/bin/sh

set -e

redis-server /usr/local/redis/etc/redis.conf &
redis-sentinel /usr/local/redis/etc/sentinel.conf

