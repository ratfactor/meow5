section .text

global _start
_start:
    push dword 42
    pop ebx
    mov eax, 1
    int 0x80
