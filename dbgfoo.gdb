# entry point address hard-coded because
break *0x08048054

run

disas 0x8048054,+13

quit
