; +--------------------------------------------------------+
; |       >o.o<   Meow5: A very conCATenative language     |
; +--------------------------------------------------------+

%assign STDIN 0
%assign STDOUT 1
%assign STDERR 2

%assign SYS_EXIT 1
%assign SYS_WRITE 4

; ----------------------------------------------------------
; BSS - reserved space
; ----------------------------------------------------------
section .bss
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
end_meow_str:

; I can't get these from the user yet, but I'm pretending we
; did. These are the word names we'll 'find' and 'inline' to
; compile.
temp_meow_name: db 'meow', 0
temp_exit_name: db 'exit', 0

; I'm pretending to get this string from an input source:
; NOTE: This buffer will move to the BSS section when I
; start reading real input.
input_buffer_start:
    db ' meow   meow meow meow meow exit', 0
input_buffer_end:

; ----------------------------------------------------------
; TEXT - executable program - starting with words
; ----------------------------------------------------------
section .text

exit: ; exit WORD (takes exit code from stack)
; ==================
    pop ebx ; exit code
    mov ebx, 0 ; exit with happy 0
    mov eax, SYS_EXIT
    int 0x80
exit_tail:
    dd 0 ; null link is end of linked list
    dd (exit_tail - exit) ; len of machine code
    db "exit", 0 ; name, null-terminated

meow: ; meow WORD (no stack change)
    mov ebx, STDOUT
    mov ecx, meow_str                  ; str start addr
    mov edx, (end_meow_str - meow_str) ; str length
    mov eax, SYS_WRITE
    int 0x80
meow_tail:
    dd exit_tail ; link to prev word
    dd (meow_tail - meow)
    db "meow", 0

inline: ; inline WORD (takes addr of tail from stack)
; ==================
    pop esi ; tail of word to inline
    mov edi, [here]    ; destination
    mov ecx, [esi + 4] ; get len into ecx
    sub esi, ecx       ; sub len from  esi (start of code)
    rep movsb          ; copies from esi to esi+ecx into edi
    add edi, ecx       ; update here pointer...
    mov [here], edi    ; ...and store it
    jmp [return_addr]
inline_tail:
    dd meow_tail ; link to prev word
    dd (inline_tail - inline)
    dd "inline", 0

find:
; ==================
    ; register use:
    ;   al  - to-find name character being checked
	;   ebx - start of dict word's name string
	;   ecx - byte offset counter (each string character)
    ;   edx - dictionary list pointer
	;   ebp - start of to-find name string
    ;
    pop ebp ; first param from stack!

    ; search backwards from last word
    mov edx, [last]
.test_word:
    cmp edx, 0  ; a null pointer (0) is end of list
    je .not_found

    ; Now we'll compare name to find vs this dictionary name
    ; (ebx vs edx) byte-by-byte until a mismatch or one hits
    ; a 0 terminator first.  Only having all correct letters
    ; AND hitting 0 at the same time is a match.
    lea ebx, [edx + 8] ; set dict. word name pointer
    mov ecx, 0         ; reset byte offset counter
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
    jmp [return_addr]

.found_it:
    push edx ; return  pointer to tail of dictionary word
    jmp [return_addr]

find_tail:
    dd inline_tail ; link to prev word
    dd (find_tail - find)
    dd "find", 0


get_token:
; ==================
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
    jmp [return_addr]
get_token_tail:
    dd find_tail ; link to prev word
    dd (get_token_tail - get_token)
    dd "get_token", 0

; ----------------------------------------------------------
; CALLWORD macro - for faking call/ret to word as if 'twas
; a function. Will only be needed for tiny subset of words.
; ----------------------------------------------------------
%macro CALLWORD 1 ; takes label of word to call
    ; This single return address will surely need to be
    ; upgraded to a stack as soon as I 'call' a word from
    ; another word (only here in assembly - this has nothing
    ; to do with normal word execution!)
    ; Note that '%%return_to' is a macro-local label.
        mov dword [return_addr], %%return_to ; CALLWORD
        jmp %1                               ; CALLWORD
    %%return_to:                             ; CALLWORD
%endmacro

; ----------------------------------------------------------
; PROGRAM START!
; ----------------------------------------------------------
global _start
_start:
    cld    ; use increment order for certain cmds

	; Here points to the current spot where we're going to
	; inline ("compile") the next word.
    mov dword [here], data_segment

    ; Store last tail for dictionary searches (note that
	; find just happens to be the last word defined in the
	; dictionary at the moment).
    mov dword [last], find_tail

    ; This will probably _really_ get set when we read
    ; more input. But for now, set to start of buffer:
    mov dword [input_buffer_pos], input_buffer_start

	; ----------------------------------------------------
    ; "Compile" the program!
    ; ----------------------------------------------------
get_next_token:
    CALLWORD get_token
    cmp DWORD [esp], 0  ; check return without popping
    je run_it           ; all out of tokens!
    CALLWORD find       ; find token (ignore error)
    CALLWORD inline     ; inline it!!!
    jmp get_next_token

;    mov byte [meow_counter], 5 ; 5 meows
;inline_a_meow:
;    ; use 'find' to get meow_tail!
;	; TEMP: ignoring a possible null pointer return because
;	; in this test I KNOW it will be found.
;	; NOTE: I'm currently leaking four bytes of memory per
;	; find because I'm not popping the param I push on the
;	; stack...
;    push temp_meow_name ; the name string to find
;    CALLWORD find
;    CALLWORD inline
;    dec byte [meow_counter]
;    jnz inline_a_meow
;
;    ; inline exit
;    push temp_exit_name ; the name string to find
;    CALLWORD find
;    CALLWORD inline

run_it:
    push 0           ; push exit code to stack for exit
    jmp data_segment ; jump to the "compiled" program

