#!/bin/bash

# Have to comment out when testing non-0 return values
# from test programs:
# set -e # quit on errors

F=meow5

# rebuild
./build.sh

# execute the 'foo' elf maker script in meow5!
echo ': foo 42 exit ; make_elf foo' | ./$F

# examine elf headers with mez
../mez/mez 2>&1 | ag 'entry|File offset|Target memory'

# try to run it
echo "Running..."
./foo
echo "(Exited with code $?)"

# debug it
gdb foo -q --command=dbgfoo.gdb


