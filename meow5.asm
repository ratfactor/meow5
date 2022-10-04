; -----------------------------------------------
;              MeowMeowMeowMeowMeow
;              o      Meow5       M
;              e                  e
;              M      ^   ^       o
;              w       o o        w
;              o      =\T/=       M
;              e                  e
;              eMwoeMwoeMwoeMwoeMwo
;         A very conCATenative language
; -----------------------------------------------

%assign STDIN 0
%assign STDOUT 1
%assign STDERR 2

%assign SYS_EXIT 1
%assign SYS_WRITE 4

section .data
; -----------------------------------------------
meow:
    db `Meow.\n`
end_meow:

section .bss
; -----------------------------------------------
here: resb 4 ; pointer to current spot

; This is where the "compiled" program goes!
data_segment: resb 1024 


section .text
; -----------------------------------------------

happy_exit:
    mov ebx, 0 ; exit with happy 0
exit:
    mov eax, SYS_EXIT
    int 0x80
%assign exit_len ($ - happy_exit)

print_meow:
    mov ebx, STDOUT
    mov ecx, meow              ; str start addr
    mov edx, (end_meow - meow) ; str length
    mov eax, SYS_WRITE
    int 0x80
%assign meow_len ($ - print_meow)

; inline function!
;   input: esi - word start source address
;   input: ecx - word length
inline:
    mov edi, [here] ; destination
    rep movsb
    add edi, ecx    ; update here pointer...
    mov [here], edi ; ...and store it
    ret

; Start!
global _start
_start:
    cld    ; use increment order for certain cmds

    ; Here points to the current spot where we're
    ; going to inline ("compile") the next word.
    mov dword [here], data_segment

    ; "Compile" the program!
    ; inline five meows
    mov eax, 5 ; 5 meows
inline_a_meow:
    mov esi, print_meow   ; source
    mov ecx, meow_len     ; bytes to copy
    call inline
    dec eax
    jnz inline_a_meow

    ; inline exit
    mov esi, happy_exit
    mov ecx, exit_len
    call inline

    ; Run!
    ; jump to the "compiled" program
    jmp data_segment

