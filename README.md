Meow5: "Meow. Meow. Meow. Meow. Meow."

A Forth-like language that is conCATenative in two ways: 1) "point free" data
flow, 2) inlined functions.

In the *point free data flow sense*: Instead of being called with explicit
named parameters, functions are "composed" so that each one takes as input what
the previous one left behind. (JavaScript programmers will recognize this
style: `sorted_long_names = people.map(get_names).filter(is_long).sort()`.

In the *inlined function* sense: all functions (and entire programs) are
concatenated copies of other functions.

The first sense is true of any Forth-like ("stack-based") language. The second
sense is what's unique about Meow5. Using Forth notation and nomenclature, the
following word "meow5" will be literally composed of five copies of the machine
code that makes the word "meow":

    : meow5 meow meow meow meow meow ;

This repo is a primitive work in progress, and proof of concept.  I want to see
how **simple** a Forth-like language can be.

To follow along, read the logNN.txt files in this repo. I'll be writing notes
as I go along, which helps me keep track of my progress over time.


== Why? ==

My idea is: Traditional "threaded interpreted" Forth goes to some pretty
extreme lengths to conserve memory. The execution model is not only
complicated, but seems also likely to not be all that great for efficiency on
modern machines.

In particular, the old Forth literature I have been reading is full of statements
about needing to conserve the few
Kb of core memory on a late 1960s machine.
But even my most modest low-powered Celeron and Atom-based computers
here at home have L1 CPU caches that dwarf those quantities!

So, given the tiny size of the programs I was writing with my JONESFORTH port,
I kept thinking, "how far could I get if I just inlined _everything_?" As in,
actually made a copy of every word's machine instructions every time it is
"compiled".

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

and ultimately an entire program would be just a single continuous
stream of concatenated instructions.

I expect this will be silly but fun and educational.
