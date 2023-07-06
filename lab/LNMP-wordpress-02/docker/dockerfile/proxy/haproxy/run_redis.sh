#!/bin/bash 

ORIG_DIR=$PWD

cd ../../database/redis > /dev/null

. run.sh

cd ${ORIG_DIR} > /dev/null


