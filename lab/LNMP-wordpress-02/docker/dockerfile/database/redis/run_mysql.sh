#!/bin/bash 

ORIG_DIR=$PWD

cd ../../database/mysql/

MYSQL_DIR=$PWD


. run_container.sh

cd ${ORIG_DIR}


