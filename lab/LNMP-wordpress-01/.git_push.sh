#!/bin/bash

# doesn't support this format in git Bash 5.2.12
#COMMAND=${1:=push} 

[ -z $1 ] && COMMAND="push"

RET=1
while [ $RET -gt 0 ]; do
    git $COMMAND 
    [ $? -eq 0 ] && RET=0
done
 

