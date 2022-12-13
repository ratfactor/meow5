#!/usr/bin/bash

./build.sh

function try {
    # -q tells grep to not echo, just return match status
    if echo "$1" | ./meow5 | grep -q "^$2\$"
    then
        printf '.'
    else
        echo
        echo "Error!"
        echo "Wanted:"
        echo "-------------------------------------------"
        echo "$1"
        echo "$2"
        echo "-------------------------------------------"
        echo
        echo "But got:"
        echo "-------------------------------------------"
        echo "$1"
        echo "$1" | ./meow5
        echo "-------------------------------------------"
        echo
        exit
    fi
}

#   Input                  Expected Result
#   -------------------    ------------------------
try 'ps'                   ''
try '5 ps'                 '5 ' # note space
try '5 5 5 + ps'           '5 10 '
try '9 2 * ps'             '18 '
try '18 5 / ps'            '3 3 '
try '5 2 - ps'             '3 '

try '"Hello$\\\$\n" print' 'Hello$\\$'

try '"Hello" say'          'Hello'

try ': five 5 ; five ps'   '5 '

try ': m "M." print ;
     m "" say'             'M.'

try ': m "M." print ;
     : m5 m m m m m ;
     m5 "" say'            'M.M.M.M.M.'

try 'var x
     4 x set
     x get ps'             '4 '

try 'var x 
     4 x set
     : x? x get "x=$" say ;
     x?'                   'x=4'

echo
echo Passed!
