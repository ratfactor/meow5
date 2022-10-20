; +--------------------------------------------------------+
; |       >o.o<   Meow5: A very conCATenative language     |
; +--------------------------------------------------------+

%assign STDIN 0
%assign STDOUT 1
%assign STDERR 2

%assign SYS_EXIT 1
%assign SYS_WRITE 4

; word flags (can have 32 of these if needed)
%assign COMPILED  00000001b
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
return_addr: resb 4     ; to avoid messing with stack!
token_buffer: resb 32   ; For get-token
input_buffer_pos: resb 4 ; Save position of read tokens

; ----------------------------------------------------------
; DATA - defined values
; ----------------------------------------------------------
section .data
meow_str:
    db `Meow.\n`
meow_str_end:
imm_meow_str:
    db `Meow!\n`
imm_meow_str_end:

; Find failed error message
not_found_str1:
    db 'Could not find word "'
not_found_str2:
    db `"\n`
not_found_end:

; I can't get these from the user yet, but I'm pretending we
; did. These are the word names we'll 'find' and 'inline' to
; compile.
temp_meow_name: db 'meow', 0
temp_exit_name: db 'exit', 0

; I'm pretending to get this string from an input source:
; NOTE: This buffer will move to the BSS section when I
; start reading real input.
input_buffer_start:
    db 'meow meow meow meow meow exit', 0
input_buffer_end:

; ----------------------------------------------------------
; MACROS!
; ----------------------------------------------------------

%macro CALLWORD 1 ; takes label of word to call
    ; For faking call/ret to word as if 'twas a function
    ; within assembly while creating the meow5 executable.
    ;
    ; This single return address will surely need to be
    ; upgraded to a stack as soon as I 'call' a word from
    ; another word? We'll see.
    ; (There won't be any such thing as "calling" words
    ; within compiled words since the invocations will
    ; inline the whole callee!)
    ;
    ; Note that '%%return_to' is a macro-local label.
        mov dword [return_addr], %%return_to ; CALLWORD
        jmp %1                               ; CALLWORD
    %%return_to:                             ; CALLWORD
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
        jmp [return_addr]
    tail_%1:
        dd LAST_WORD_TAIL ; 32b address, linked list
        %define LAST_WORD_TAIL tail_%1
        dd (end_%1 - %1)  ; 32b length of word machine code
        dd %3             ; 32b flags for word
        db %2, 0          ; xxb null-terminated name string
%endmacro


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
ENDWORD exit, "exit", (COMPILED | IMMEDIATE) 

DEFWORD imm_meow
    mov ebx, STDOUT
    mov ecx, imm_meow_str                  ; str start addr
    mov edx, (imm_meow_str_end - imm_meow_str) ; str length
    mov eax, SYS_WRITE
    int 0x80
ENDWORD imm_meow, "meow", (IMMEDIATE)

DEFWORD meow
    mov ebx, STDOUT
    mov ecx, meow_str                  ; str start addr
    mov edx, (meow_str_end - meow_str) ; str length
    mov eax, SYS_WRITE
    int 0x80
ENDWORD meow, "meow", (COMPILED)

DEFWORD inline
    pop esi ; param1: tail of word to inline
    mov edi, [here]    ; destination
    mov ecx, [esi + 4] ; get len into ecx
    sub esi, ecx       ; sub len from  esi (start of code)
    rep movsb          ; copies from esi to esi+ecx into edi
    add edi, ecx       ; update here pointer...
    mov [here], edi    ; ...and store it
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
    ; currently in (IMMEDIATE vs COMPILED):
    mov eax, [mode]
    and eax, [edx + 8] ; see if mode bit is set in word tail
    cmp eax, 0
    jz .try_next_word ; bit wasn't set to match this mode
    ; Now we'll compare name to find vs this dictionary name
    ; (ebx vs edx) byte-by-byte until a mismatch or one hits
    ; a 0 terminator first.  Only having all correct letters
    ; AND hitting 0 at the same time is a match.
    lea ebx, [edx + 12] ; set dict. word name pointer
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
    jmp [return_addr]
.return_token:
    lea eax, [ebx + ecx]
    mov [input_buffer_pos], eax ; save position
    mov [edx + ecx], byte 0     ; terminate str null
    push DWORD token_buffer     ; return str address
ENDWORD get_token, "get_token", (IMMEDIATE)


; ----------------------------------------------------------
; PROGRAM START!
; ----------------------------------------------------------
global _start
_start:
    cld    ; use increment order for certain cmds

    ; Start in immediate mode - execute words immediately!
    mov dword [mode], IMMEDIATE;

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

	; ----------------------------------------------------
    ; Interpreter!
    ; ----------------------------------------------------
get_next_token:
    CALLWORD get_token
    cmp dword [esp], 0  ; check return without popping
    je .run_it           ; all out of tokens!
    CALLWORD find       ; find token (ignore error)
    cmp dword [esp], 0  ; check return without popping
    je .token_not_found
    CALLWORD inline     ; inline it!!!
    jmp get_next_token
.run_it:
    push 0           ; push exit code to stack for exit
    jmp data_segment ; jump to the "compiled" program
    ; NOT expecting a return - for now, this test
    ; should cleanly exit in whatever we compiled into
    ; the data_segment!
.token_not_found:
    ; Repetitous temporary code until we get fancy!
    ; output fd, string start, string len...
    ; Message 1/3:
    mov ebx, STDOUT
    mov ecx, not_found_str1
    mov edx, (not_found_str2 - not_found_str1)
    mov eax, SYS_WRITE
    int 0x80
    ; Message 2/3:  calc strlen of token...
    ; Someday I'll be able to call a word to do this.
    mov ecx, token_buffer ; token will always be here
    mov edx, 0 ; will contain len
.find_tok_end:
    cmp byte [ecx + edx], 0 ; null term?
    je .print_bad_tok
    inc edx            ; not yet, increase len
    jmp .find_tok_end
.print_bad_tok:
    ; now edx and ecx should be set
    mov ebx, STDOUT
    mov eax, SYS_WRITE
    int 0x80
    ; Message 3/3:
    mov ebx, STDOUT
    mov ecx, not_found_str2
    mov edx, (not_found_end - not_found_str2)
    mov eax, SYS_WRITE
    int 0x80
    CALLWORD exit
