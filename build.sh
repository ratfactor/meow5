#!/bin/bash

# Usage:
#
#   build.sh        Assemble, link
#   build.sh gdb    Assemble, link, and debug
#   build.sh run    Assemble, link, and run

set -e # quit on errors

F=meow5

# assemble and link!
#  -w+all turns on all warnings
#  -g     enables debugging symbols
#  -f     assembled output type
#  -o     output filename
nasm -w+all -g -f elf32 -o $F.o $F.asm
ld -m elf_i386 $F.o -o $F
rm $F.o

if [[ $1 == 'gdb' ]]
then
    # -q         - skips the verbiage at the beginning
    gdb $F -q
    exit
fi

if [[ $1 == 'run' ]]
then
    ./$F
    exit
fi

