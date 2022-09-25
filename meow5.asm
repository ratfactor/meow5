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
meow:
    db `Meow.\n`
end_meow:

section .bss
data_segment: resb 1024 

; Start!
; -----------------------------------------------
section .text
global _start
_start:
    cld    ; use increment order for certain cmds

; A meow:
; -----------------------------------------------
print_meow:
    mov ebx, STDOUT
    mov ecx, meow              ; str start addr
    mov edx, (end_meow - meow) ; str length
    mov eax, SYS_WRITE
    int 0x80
end_print_meow:

; The First Test - Can I copy a meow?
; -----------------------------------------------
%define meow_len (end_print_meow - print_meow)
%define exit_len (end_exit - happy_exit)

    ; copy meow printing code
    mov edi, data_segment ; destination
    mov esi, print_meow   ; source
    mov ecx, meow_len     ; bytes to copy
    rep movsb             ; copy!

    ; copy exit code
    mov edi, (data_segment+meow_len) ; destination
    mov esi, happy_exit   ; source
    mov ecx, exit_len ; len
    rep movsb ; copy ecx bytes

    ; jump to the copied code!
    jmp data_segment

happy_exit:
    mov ebx, 0 ; exit with happy 0
exit:
    mov eax, SYS_EXIT
    int 0x80
end_exit:
