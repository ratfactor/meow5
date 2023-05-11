#!/bin/bash

set -e # quit on errors

F=meow5

# rebuild
./build.sh

# execute the 'foo' elf maker script in meow5!
echo ': foo exit 42 ; make_elf foo' | ./$F

# examine elf headers with mez
../mez/mez 2>&1 | ag 'entry|File offset|Target memory'

# try to run it
./foo

# debug it
gdb $F -q --command=dbgfoo.gdb


