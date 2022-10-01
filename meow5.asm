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

;EAX: The accumulator/return val
;EBX: often for pointers
;ECX: often for counters
;EDX: whatever
;ESI: The source index for string operations.
;EDI: The destination index for string operations.
;EBP: pointer to current fn stack frame base
;ESP: pointer to current fn stack frame top
;EIP: instruction pointer!

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
data_segment: resb 1024 


section .text
; -----------------------------------------------

happy_exit:
    mov ebx, 0 ; exit with happy 0
exit:
    mov eax, SYS_EXIT
    int 0x80
;end_exit:
%assign exit_len ($ - happy_exit)

print_meow:
    mov ebx, STDOUT
    mov ecx, meow              ; str start addr
    mov edx, (end_meow - meow) ; str length
    mov eax, SYS_WRITE
    int 0x80
%assign meow_len ($ - print_meow)

; Start!
global _start
_start:
    cld    ; use increment order for certain cmds

    ; The First Test - Can I copy a meow?

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

