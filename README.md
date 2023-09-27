# Meow5: "Meow. Meow. Meow. Meow. Meow."

**MOVED!** Hello, I am moving my repos to http://ratfactor.com/repos/
and setting them to read-only ("archived") on GitHub. Thank you, _-Dave_

<img src="meow5cat.svg" alt="SVG meow5 kitty cat logo" align="right">

This is a work in progress. Check the `log*.txt` files to
see where I'm currently at! Also take a look at
`design-notes.txt` for more ongoing thoughts (also kinda
functions as a vague todo/done list).

The language is now fully interactive!

```
"Hello world!" say
Hello world!

: meow "Meow. " print ;
meow
Meow.

: meow5 meow meow meow meow meow ;
Meow. Meow. Meow. Meow. Meow.
```

Note that this is Linux-only and is assembled with NASM.

See also:

* http://ratfactor.com/meow5/ - Meow5's page on the World Wide Web
* http://ratfactor.com/assembly-nights2 - If you want to know what this is _really_ about

Oh, and check out the "Progress" section in this README below.

## What is Meow5?

A Forth-like language that is conCATenative in two ways:

1. "Point free" data flow
2. Inlined functions

In the **point free data flow sense**: Instead of being
called with explicit named parameters ("points"), functions
are "composed" so that each one takes as input what the
previous one left behind. JavaScript programmers will
recognize this style:

    people.map(get_names).filter(is_long).sort() // get sorted long names

Which might look like this in Forth:

    PEOPLE GETNAMES LONGNAMES SORT

In the **inlined function** sense: all functions (and entire
programs) are concatenated copies of other functions.

The first "point-free" sense is true of any Forth-like
("stack-based") language.

The second sense is what's unique about Meow5. Using Forth
notation and nomenclature, the following word "meow5"...:

    : meow5 meow meow meow meow meow ;

...will be literally composed of five copies
of the machine code that makes the word "meow". Crazy, right?


## Why?

I want to see how **simple** a Forth-like language can be.

My idea came about while studying Forth. A traditional
"threaded interpreted" Forth goes to some pretty extreme
lengths to conserve memory. The execution model is not only
complicated, but seems also likely to not be all that great
for efficiency on modern machines where memory is much more
abundant and the bottleneck oftenseems to be getting data
into the CPU fast enough.

In particular, the old Forth literature I have been reading
is full of statements about needing to conserve the **few
kilobytes of core memory** on a late 1960s machine.  But
even my most modest low-powered Celeron and Atom-based
computers have **L1 CPU caches** that dwarf those
quantities!

So, given the tiny size of the programs I was writing with
my JONESFORTH port, I kept thinking, "how far could I get if
I just inlined _everything_?" As in, actually made a copy of
every word's machine instructions every time it is
"compiled".

In the name of simplicity, I'm also avoiding too many
assembly tricks or any attempt at optimization (that stuff is
really fun, but I find it too distracting from making this
proof-of-concept). So, for example, I'll use:

    mov eax, 0

instead of the shorter (when assembled)  instruction:

    xor eax, eax

because the intent is clearer at a glance.


## Psuedocode examples

Given these pseudo machine code definitions:

    foo:
        00A 00B
        00C 00D

    bar:
        FFA FFB
        FFC FFD

this Forth-like word definition:

    : 2foo foo foo ;

would compile as:

    2foo: 
        00A 00B
        00C 00D
        00A 00B
        00C 00D

and this Forth-like:

    : bar2foo bar 2foo ;

would simply concatenate the entire contents of bar and 2foo:

    bar2foo:
        FFA FFB
        FFC FFD
        00A 00B
        00C 00D
        00A 00B
        00C 00D

and ultimately an entire program would be just a single
continuous stream of concatenated instructions.

I expect this will be silly but fun and educational.
