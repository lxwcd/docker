#!/bin/bash 

ORIG_DIR=$PWD

cd ../../database/mysql/ > /dev/null

. run.sh

cd ${ORIG_DIR} > /dev/null


