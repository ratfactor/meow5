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
meow_str:
    db `Meow.\n`
end_meow_str:

section .bss
; -----------------------------------------------
here: resb 4 ; pointer to current spot

; This is where the "compiled" program goes!
data_segment: resb 1024 


section .text
; -----------------------------------------------

exit:
    mov ebx, 0 ; exit with happy 0
    mov eax, SYS_EXIT
    int 0x80
exit_tail:
    dd 0 ; null link is end of linked list
    dd (exit_tail - exit) ; len of machine code
    db "exit", 0 ; name, null-terminated

meow:
    mov ebx, STDOUT
    mov ecx, meow_str              ; str start addr
    mov edx, (end_meow_str - meow_str) ; str length
    mov eax, SYS_WRITE
    int 0x80
meow_tail:
    dd exit_tail ; exit is previous word
    dd (meow_tail - meow)
    db "meow", 0


; inline function!
;   input: esi - tail of the word to inline
inline:
    mov edi, [here]    ; destination
    mov ecx, [esi + 4] ; get len into ecx
    sub esi, ecx       ; sub len from  esi (start of code)
    rep movsb ; movsb copies from esi to esi+ecx into edi
    add edi, ecx       ; update here pointer...
    mov [here], edi    ; ...and store it
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
    mov esi, meow_tail   ; source
    call inline
    dec eax
    jnz inline_a_meow

    ; inline exit
    mov esi, exit_tail
    call inline

    ; Run!
    ; jump to the "compiled" program
    jmp data_segment

