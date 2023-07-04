#!/bin/sh

set -e

php-fpm82

nginx -g "daemon off;"
