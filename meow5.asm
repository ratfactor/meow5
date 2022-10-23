; +--------------------------------------------------------+
; |       >o.o<   Meow5: A very conCATenative language     |
; +--------------------------------------------------------+

%assign STDIN 0
%assign STDOUT 1
%assign STDERR 2

%assign SYS_EXIT 1
%assign SYS_WRITE 4

; word flags (can have 32 of these if needed)
%assign COMPILE  00000001b
%assign IMMEDIATE 00000010b

; ----------------------------------------------------------
; BSS - reserved space
; ----------------------------------------------------------
section .bss
mode: resb 4            ; 1=compile mode, 0=immediate mode
last: resb 4            ; Pointer to last defined word tail
data_segment: resb 1024 ; We inline ("compile") here!
here: resb 4            ; Current data_segment pointer
meow_counter: resb 1    ; Will count the five meows
token_buffer: resb 32   ; For get-token
input_buffer_pos: resb 4 ; Save position of read tokens

; Return stack for immediate mode execution only
return_stack: resb 512  ; Not expecting deep calls... 
return_ptr:   resb 4    ; To "push/pop" return stack

; ----------------------------------------------------------
; DATA - defined values
; ----------------------------------------------------------
section .data
meow_str:
    db `Meow.\n`,0
meow_str_end:
imm_meow_str:
    db `Immediate Meow!\n`,0
imm_meow_str_end:

; Find failed error message
not_found_str1:
    db 'Could not find word "',0
not_found_str2:
    db `"\n`,0

; I'm pretending to get this string from an input source:
; NOTE: This buffer will move to the BSS section when I
; start reading real input.
input_buffer_start:
    db 'meow : meow meow meow exit', 0
input_buffer_end:

; ----------------------------------------------------------
; MACROS!
; ----------------------------------------------------------

%macro CALLWORD 1 ; takes label/addr of word to call
    ; For faking call/ret to word as if 'twas a function
    ; within assembly while creating the meow5 executable.
        mov eax, [return_ptr] ; current return stack pos
        add eax, 4            ; advance it (grow fwd)
        mov [return_ptr], eax ; save pos
        mov dword [eax], %%return_to ; CALLWORD
        jmp %1                               ; CALLWORD
    %%return_to:                             ; CALLWORD
    ; Note that '%%return_to' is a macro-local label.
%endmacro

%macro DEFWORD 1 ; takes name of word to make
    ; Start a word definition
    %1:
%endmacro

%macro ENDWORD 3
    ; End a word definiton with a tail, etc.
    ; params:
    ;   %1 - word name for label (must be NASM-safe)
    ;   %2 - string word name for find
    ;   %3 - 32 bits of flags
    ; Here ends the machine code for the word:
    end_%1:
        ; If we've called this in immediate mode, use the
        ; return address. This part won't be inlined.
        mov eax, [return_ptr] ; current return stack pos
        sub dword [return_ptr], 4 ; "pop" return stack
        jmp [eax]             ; go to return addr!
    tail_%1:
        dd LAST_WORD_TAIL ; 32b address, linked list
        %define LAST_WORD_TAIL tail_%1
        dd (end_%1 - %1)  ; 32b length of word machine code
        dd (tail_%1 - %1) ; 32b distance from tail to start
        dd %3             ; 32b flags for word
        db %2, 0          ; xxb null-terminated name string
%endmacro

; Memory offsets for each item in tail:
%define T_CODE_LEN    4
%define T_CODE_OFFSET 8
%define T_FLAGS       12
%define T_NAME        16

; ----------------------------------------------------------
; TEXT - executable program - starting with words
; ----------------------------------------------------------
section .text

; Keep track of word addresses for linked list.
; We start at 0 (null pointer) to indicate end of list.
%define LAST_WORD_TAIL 0

DEFWORD exit
    pop ebx ; param1: exit code
    mov eax, SYS_EXIT
    int 0x80
ENDWORD exit, "exit", (COMPILE | IMMEDIATE) 

DEFWORD inline
    pop esi ; param1: tail of word to inline
    mov edi, [here]    ; destination
    mov eax, [esi + T_CODE_LEN]    ; get len of code
    mov ebx, [esi + T_CODE_OFFSET] ; get start of code
    sub esi, ebx    ; set start of code for movsb
    mov ecx, eax    ; set len of code for movsb
    rep movsb       ; copy [esi]...[esi+ecx] into [edi]
    add [here], eax ; save current position
ENDWORD inline, "inline", (IMMEDIATE)

DEFWORD find
    pop ebp ; param1 - start of word string to find
    ; in-word register use:
    ;   al  - to-find name character being checked
	;   ebx - start of dict word's name string
	;   ecx - byte offset counter (each string character)
    ;   edx - dictionary list pointer
    ; search backwards from last word
    mov edx, [last]
.test_word:
    cmp edx, 0  ; a null pointer (0) is end of list
    je .not_found
    ; First, see if this word is for the mode we're
    ; currently in (IMMEDIATE vs COMPILE):
    mov eax, [mode]
    and eax, [edx + T_FLAGS] ; see if mode bit is set in word tail
    cmp eax, 0
    jz .try_next_word ; bit wasn't set to match this mode
    ; Now we'll compare name to find vs this dictionary name
    ; (ebx vs edx) byte-by-byte until a mismatch or one hits
    ; a 0 terminator first.  Only having all correct letters
    ; AND hitting 0 at the same time is a match.
    lea ebx, [edx + T_NAME] ; set dict. word name pointer
    mov ecx, 0          ; reset byte offset counter
.compare_names_loop:
	mov al, [ebp + ecx] ; get next to-find name byte
    cmp al, [ebx + ecx] ; compare with next dict word byte
    jne .try_next_word  ; found a mismatch!
    cmp al, 0           ; both hit 0 terminator at same time
    je .found_it
	inc ecx
	jmp .compare_names_loop
.try_next_word:
    mov edx, [edx]   ; follow the tail! (linked list)
    jmp .test_word
.not_found:
    push 0   ; return 0 to indicate not found
    jmp .done
.found_it:
    push edx ; return  pointer to tail of dictionary word
.done:
ENDWORD find, "find", (IMMEDIATE)

DEFWORD get_token
    ; Returns (on stack) either:
    ;  * Address of null-termed token string or
    ;  * 0 if we're out of tokens
    ;
    ;  * * *
    ; Input 'faked' for now, but fairly realistic. This
    ; will definitely be changing in various ways with real
    ; line input, though. For example, we'll need to see if
    ; there's _more_ input available.
    ;  * * *
    ;
    mov ebx, [input_buffer_pos] ; set input read addr
    mov edx, token_buffer       ; set output write addr
    mov ecx, 0                  ; position index
.get_char:
    mov al, [ebx + ecx] ; input addr + position index
    cmp al, 0           ; end of input?
    je .end_of_input    ; yes
    cmp al, ' '         ; token separator? (space)
    jne .add_char       ; nope! get char
    cmp ecx, 0          ; yup! do we have a token yet?
    je .eat_space       ; no
    jmp .return_token   ; yes, return it
.eat_space:
    inc ebx             ; 'eat' space by advancing input
    jmp .get_char
.add_char:
    mov [edx + ecx], al ; write character
    inc ecx             ; next character
    jmp .get_char
.end_of_input:
    ; okay, now did we hit the end while gathering
    ; a token, or did we come up empty-handed?
    cmp ecx, 0         ; did we have anything?
    jne .return_token  ; we have a token
    push DWORD 0       ; empty-handed
    jmp .return
.return_token:
    lea eax, [ebx + ecx]
    mov [input_buffer_pos], eax ; save position
    mov [edx + ecx], byte 0     ; terminate str null
    push DWORD token_buffer     ; return str address
.return:
ENDWORD get_token, "get_token", (IMMEDIATE)

DEFWORD colon
    ; just set mode for now...will eventually
    ; get name from next token and store it...
    mov dword [mode], COMPILE
ENDWORD colon, ":", (IMMEDIATE)

; Gets length of null-terminated string
; (Note that this doesn't pop the string's start address
; because I think it's silly to have to duplicate the
; address on the stack when you _probably_ don't want to do
; that. Instead, we'll 'drop' if that's what we want later.)
%macro strlen_code 0
    mov eax, [esp] ; get string addr (without popping!)
    mov ecx, 0     ; byte counter will contain len
.find_null:
    cmp byte [eax + ecx], 0 ; null term?
    je .done                ; yes, done
    inc ecx                 ; no, continue
    jmp .find_null          ; loop
.done:
    push ecx           ; return len
%endmacro
DEFWORD strlen ; (straddr) strlen (straddr len)
    strlen_code
ENDWORD strlen, "strlen", (IMMEDIATE & COMPILE)

; Prints a null-terminated string by address on stack.
%macro print_code 0
    strlen_code        ; (after: straddr, len)
    mov ebx, STDOUT    ; write destination file
    pop edx            ; strlen
    pop ecx            ; start address
    mov eax, SYS_WRITE ; syscall
    int 0x80           ; interrupt to linux!
%endmacro
DEFWORD print ; (straddr) print ()
    print_code
ENDWORD print, "print", (IMMEDIATE & COMPILE)

DEFWORD imm_meow
    push imm_meow_str
    print_code
ENDWORD imm_meow, "meow", (IMMEDIATE)

DEFWORD meow
    push meow_str
    print_code
ENDWORD meow, "meow", (COMPILE)

; ----------------------------------------------------------
; PROGRAM START!
; ----------------------------------------------------------
global _start
_start:
    cld    ; use increment order for certain cmds

    ; Start in immediate mode - execute words immediately!
    mov dword [mode], IMMEDIATE
    ;mov dword [mode], COMPILE

	; Here points to the current spot where we're going to
	; inline ("compile") the next word.
    mov dword [here], data_segment

    ; Store last tail for dictionary searches (note that
	; find just happens to be the last word defined in the
	; dictionary at the moment).
    mov dword [last], LAST_WORD_TAIL

    ; This will probably _really_ get set when we read
    ; more input. But for now, set to start of buffer:
    mov dword [input_buffer_pos], input_buffer_start

    ; Initialize return stack pointer to point at the
    ; beginning of the return stack reserved memory:
    mov dword [return_ptr], return_stack

; ----------------------------------------------------------
; Interpreter!
; ----------------------------------------------------------
get_next_token:
    CALLWORD get_token
    cmp dword [esp], 0  ; check return without popping
    je .run_it           ; all out of tokens!
    CALLWORD find       ; find token, returns tail addr
    cmp dword [esp], 0  ; check return without popping
    je .token_not_found
    cmp dword [mode], IMMEDIATE
    je .exec_word
    CALLWORD inline     ; inline it!!!
    jmp get_next_token
.exec_word:
    ; Run current word in immediate mode!
    ; We currently have the tail of a found word.
    pop ebx ; addr of word tail left on stack by 'find'
    mov eax, [ebx + T_CODE_OFFSET]
    sub ebx, eax ; set to start of word's machine code
    CALLWORD ebx ; call word with that addr (via reg)
    jmp get_next_token
.run_it: ; By "it" I mean the code we've compiled/inlined.
    push 0           ; push exit code to stack for exit
    jmp data_segment ; jump to the "compiled" program
    ; NOT expecting a return - for now, this test
    ; should cleanly exit in whatever we compiled into
    ; the data_segment!
.token_not_found:
    ; TODO: print which mode we were in when we were
    ; looking! (IMMEDIATE or COMPILE)
    push not_found_str1
    CALLWORD print
    push token_buffer
    CALLWORD print
    push not_found_str2
    CALLWORD print
    CALLWORD exit
