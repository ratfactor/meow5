#!/usr/bin/bash

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
        echo $2
        echo "-------------------------------------------"
        echo
        echo "But got:"
        echo "-------------------------------------------"
        echo "$1" | ./meow5
        echo "-------------------------------------------"
        echo
    fi
}

try '"Hello" say' 'Hello'
try '"Hello" say' 'beans'
