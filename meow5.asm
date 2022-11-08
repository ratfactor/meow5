; +--------------------------------------------------------+
; |       >o.o<   Meow5: A very conCATenative language     |
; +--------------------------------------------------------+

%assign STDIN 0
%assign STDOUT 1
%assign STDERR 2

%assign SYS_EXIT 1
%assign SYS_WRITE 4

; word flags (can have 32 of these if needed)
%assign COMPILE   00000001b ; word can be compiled
%assign IMMEDIATE 00000010b ; can be called in imm mode
%assign RUNCOMP   00000100b ; word execs in comp mode

; ----------------------------------------------------------
; BSS - reserved space
; ----------------------------------------------------------
section .bss
mode: resb 4            ; IMMEDATE or COMPILE
last: resb 4            ; Pointer to last defined word tail
here: resb 4            ; Will point to compile_area
free: resb 4            ; Will point to data_area
token_buffer: resb 32   ; For get_token
name_buffer:  resb 32   ; For colon (copy of token)
compile_area: resb 4096 ; We inline ("compile") here!
data_area: resb 1024    ; All variables go here!

input_buffer_pos: resb 4 ; Save position of read tokens

; Return address for immediate mode execution only
return_addr:   resb 4    ; To "push/pop" return stack

; ----------------------------------------------------------
; DATA - defined values
; ----------------------------------------------------------
section .data

; I'm pretending to get this string from an input source:
; NOTE: This buffer will move to the BSS section when I
; start reading real input.
input_buffer:
    db ': meow "Meow." print ; '
    db ': meow5 meow meow meow meow meow ; '
    db 'morp '
    db 'meow5 '
    db 'newline '
    db 'exit',0

; ----------------------------------------------------------
; MACROS!
; ----------------------------------------------------------

; PRINTSTR "Foo bar."
%macro PRINTSTR 1
    ; Param is the string to print - put it in data section
    ; with macro-local label %%str.  No need for null
    ; termination.
    %strlen mystr_len %1 ; and get length for later
    section .data
        %%mystr: db %1
    ; now the executable part
    section .text
        ; First, make this safe to plop absolutely anywhere
        ; by pushing the 4 registers used.
        push eax ;A
        push ebx ;B
        push ecx ;C
        push edx ;D
        ; Print the string
        mov ebx, STDOUT
        mov edx, mystr_len
        mov ecx, %%mystr
        mov eax, SYS_WRITE
        int 0x80
        ; Restore all registers. (Reverse order)
        pop edx ;D
        pop ecx ;C
        pop ebx ;B
        pop eax ;A
%endmacro ; DEBUG print

%macro DEBUG 2
    PRINTSTR %1
    ; Make this safe to plop absolutely anywhere
    ; by pushing the 4 registers used.
    push eax ;A
    push ebx ;B
    push ecx ;C
    push edx ;D
    ; Second param is the source expression for this
    ; MOV instruction - we'll print this value as a
    ; 32bit (4 byte, dword, 8 digit) hex num.
    ; We must perform the MOV now before the register
    ; values are overwritten by printing the string.
    mov eax, %2
    ; Now print the value. We'll use the stack as a
    ; scratch space to construct the ASCII string of the
    ; hex value. Only 9 bytes are needed (8 digits +
    ; newline), but due to a tricky "fencepost" issue,
    ; I've elected to leave room for 10 bytes and
    ; "waste" the first one.
    lea ebx, [esp - 10]  ; make room for string
    mov    ecx, 8 ; counter - 8 characters
    %%digit_loop:
        mov edx, eax
        and edx, 0x0f   ; just keep lowest 4 bits
        cmp edx, 9      ; bigger than 9?
        jg  %%af        ; yes, print 'a'-'f'
        add edx, '0'    ; no, turn it into ascii number
        jmp %%continue
    %%af:
        add edx, 'a'-10 ; because 10 is 'a'...
    %%continue:
        mov byte [ebx + ecx], dl ; store character
        ror eax, 4               ; rotate 4 bits
        dec ecx                  ; update counter
        jnz %%digit_loop         ; loop
    ; Print hex number string
    mov byte [ebx + 9], 0x0A ; add newline
    lea ecx, [ebx+1]         ; because ecx went 8...1
    mov ebx, STDOUT
    mov edx, 9 ; 8 hex digits + newline
    mov eax, SYS_WRITE
    int 0x80
    ; Restore all registers. (Reverse order)
    pop edx ;D
    pop ecx ;C
    pop ebx ;B
    pop eax ;A
%endmacro ; DEBUG print

%macro CALLWORD 1 ; takes label/addr of word to call
    ; For faking call/ret to word as if 'twas a function
    ; within assembly while creating the meow5 executable.
    ; Note that '%%return_to' is a macro-local label.
        mov dword [return_addr], %%return_to ; CALLWORD
        jmp %1                               ; CALLWORD
    %%return_to:                             ; CALLWORD
%endmacro

%macro DEFWORD 1 ; takes name of word to make
    ; Start a word definition
    %1:
%endmacro

%macro RETURN_CODE 0
    mov eax, [return_addr] ; RETURN
    jmp eax                ; RETURN
%endmacro

%macro ENDWORD 3
    ; End a word definiton with a tail, etc.
    ; params:
    ;   %1 - word name for label (must be NASM-safe)
    ;   %2 - string word name for find
    ;   %3 - 32 bits of flags
    ; Here ends the machine code for the word:
    end_%1:
        ; If we've called this in immediate mode, we'll
        ; This part won't be inlined, so it won't get
        ; in the way of the flow of "compiled" code.
        RETURN_CODE
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

; Gets length of null-terminated string
%macro STRLEN_CODE 0
    pop eax
    mov ecx, 0     ; byte counter will contain len
.find_null:
    cmp byte [eax + ecx], 0 ; null term?
    je .strlen_done         ; yes, done
    inc ecx                 ; no, continue
    jmp .find_null          ; loop
.strlen_done:
    push ecx           ; return len
%endmacro
DEFWORD strlen ; (straddr) strlen (straddr len)
    STRLEN_CODE
ENDWORD strlen, "strlen", (IMMEDIATE | COMPILE)

; Prints a newline to STDOUT, no fuss
%macro NEWLINE_CODE 0
    mov eax, 0x0A      ; newline byte (into 4 byte reg)
    push eax           ; put on stack so has addr
    mov ebx, STDOUT    ; write destination file
    mov edx, 1         ; length = 1 byte
    mov ecx, esp       ; addr of stack (little-endian!)
    mov eax, SYS_WRITE ; syscall
    int 0x80           ; interrupt to linux!
    pop eax            ; clear the newline from stack
%endmacro
DEFWORD newline ; () newline ()
    NEWLINE_CODE
ENDWORD newline, "newline", (IMMEDIATE | COMPILE)

; Prints a null-terminated string by address on stack.
%macro PRINT_CODE 0
    pop eax            ; dup address for strlen
    push eax
    push eax
    STRLEN_CODE        ; (after: straddr, len)
    mov ebx, STDOUT    ; write destination file
    pop edx            ; string address
    pop ecx            ; strlen
    mov eax, SYS_WRITE ; syscall
    int 0x80           ; interrupt to linux!
%endmacro
DEFWORD print ; (straddr) print ()
    PRINT_CODE
ENDWORD print, "print", (IMMEDIATE | COMPILE)


%macro INLINE_CODE 0
    pop esi ; param1: tail of word to inline
    mov edi, [here]    ; destination
    mov eax, [esi + T_CODE_LEN]    ; get len of code
    mov ebx, [esi + T_CODE_OFFSET] ; get start of code
    sub esi, ebx    ; set start of code for movsb
    mov ecx, eax    ; set len of code for movsb
    rep movsb       ; copy [esi]...[esi+ecx] into [edi]
    ;add [here], eax ; save current position
    mov [here], edi ; movsb updates edi for us
%endmacro
DEFWORD inline
    INLINE_CODE
ENDWORD inline, "inline", (IMMEDIATE)

; Given a tail addr, leaves word's flags AND the tail addr
%macro GET_FLAGS_CODE 0
    mov ebp, [esp] ; get tail addr without popping
    mov eax, [ebp + T_FLAGS] ; get flags!
    push eax
%endmacro
DEFWORD get_flags ; (tail_addr) get_flags (tailaddr flags)
    GET_FLAGS_CODE
ENDWORD get_flags, "get_flags", (IMMEDIATE | COMPILE)

; Consumes word flags, leaves truthy/falsy if RUNCOMP
; flag existed. (Non-zero is true!)
%macro IS_RUNCOMP_CODE 0
    pop eax ; param: flags
    and eax, RUNCOMP ; AND mask to leave truthy/falsy
    push eax
%endmacro
DEFWORD is_runcomp ; (flags) is_runcomp (true/false)
    IS_RUNCOMP_CODE
ENDWORD is_runcomp, "is_runcomp", (IMMEDIATE | COMPILE)

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

; Skips any characters space and below from input buffer.
%macro EAT_SPACES_CODE 0
    mov ebx, [input_buffer_pos] ; set input read addr
    mov ecx, 0                  ; position index
.check:
    mov al, [ebx + ecx] ; input addr + position index
    cmp al, 0           ; end of input?
    je .done            ; yes, return
    cmp al, 0x20        ; anything space and below?
    jg .done            ; nope, we're done
    inc ecx             ; 'eat' space by advancing input
    jmp .check          ; loop
.done:
    cmp ecx, 0          ; did we eat anything?
    je .done2           ; nope, just return
    add ebx, ecx        ; new pointer
    mov [input_buffer_pos], ebx ; save it
.done2:
%endmacro
DEFWORD eat_spaces
    EAT_SPACES_CODE
ENDWORD eat_spaces, "eat_spaces", (IMMEDIATE | COMPILE)

%macro GET_TOKEN_CODE 0
    ; Returns (on stack) either:
    ;  * Address of null-termed token string or
    ;  * 0 if we're out of tokens
    ; MUST be proceeded by eat_spaces or you may get false
    ; end of input detection.
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
    cmp al, 0x20        ; end of token (spece or lower?)
    jle .end_of_token   ; yes
    mov [edx + ecx], al ; write character
    inc ecx             ; next character
    jmp .get_char
.end_of_token:
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
%endmacro
DEFWORD get_token
    GET_TOKEN_CODE
ENDWORD get_token, "get_token", (IMMEDIATE)

; Copy null-terminated string.
%macro COPYSTR_CODE 0
    pop edi ; dest
    pop esi ; source
    mov ecx, 0 ; index
.copy_char:
    mov  al, [esi + ecx] ; from source
    mov  [edi + ecx], al ; to dest
    inc  ecx
    cmp al, 0            ; hit terminator?
    jnz .copy_char
%endmacro
DEFWORD copystr ; (sourceaddr, destaddr) copystr ()
    COPYSTR_CODE
ENDWORD copystr, "copystr", (IMMEDIATE | COMPILE)

DEFWORD colon
    mov dword [mode], COMPILE
    ; get name from next token and store it...
    EAT_SPACES_CODE
    GET_TOKEN_CODE
    push token_buffer ; source
    push name_buffer  ; dest
    COPYSTR_CODE      ; copy name into name_buffer
    ; copy the here pointer so we have the start address
    ; of the word
    mov eax, [here]
    push eax ; leave 'here' on stack - the start of the word
ENDWORD colon, ":", (IMMEDIATE)

; This exists just so we can inline it at the end of
; word definitions with the semicolon (;) word.
DEFWORD return
    RETURN_CODE
ENDWORD return, "return", (IMMEDIATE)

; Does what ENDWORD macro does, but into memory
DEFWORD semicolon
    ; End of Machine Code
    ; 'here' currently points to the end of the new word's
    ; machine code. We need to save that.
    mov eax, [here]
    push eax ; push end of machine code to stack
    ; Return Code
    ; Inline 'return' before the tail to allow our new
    ; word to be callable in immdiate mode.
    ; (Future improvement: Don't include this if this is
    ;  not an immediate-capable word!)
    push tail_return ; push what to inline on stack
    INLINE_CODE      ; inline the 'return' machine code
    ; Start of Tail
    ; The above inline will have advanced 'here' again.
    mov eax, [here] ; Current 'here' position
    mov ecx, eax    ; another copy, for tail start calc
    ; Link previous word 'last'
    mov ebx, [last] ; get prev tail pointer 'last'
    mov [eax], ebx ; link it here
    mov [last], eax ; and store this tail as new 'last'
    add eax, 4 ; advance 'here' 4 bytes
    ; Store length of new word's machine code
    pop ebx ; get end of machine code addr pushed above
    pop edx ; get start of machine code addr pushed by ':'
    sub ebx, edx ; calc length of machine code
    mov [eax], ebx
    add eax, 4 ; advance 'here' 4 bytes
    ; Store distance from start of tail to start of machine
    ; code.
    sub ecx, edx ; tail - start of mc
    mov [eax], ecx
    add eax, 4 ; advance 'here' 4 bytes
    ; Store flags
    ; dd %3             ; 32b flags for word
    ; NOTE: Temporarily hard-coded value!
    mov dword [eax], (IMMEDIATE | COMPILE)
    add eax, 4 ; advance 'here' 4 bytes
    push eax ; save a copy of 'here'
    ; Store name string
    ; db %2, 0          ; xxb null-terminated name string
    push name_buffer  ; source
    push eax          ; destination
    COPYSTR_CODE      ; copy name into tail
    ; Call strlen so we know how much string name we
    ; wrote to the tail:
    push name_buffer
    STRLEN_CODE
    pop ebx ; get string len pushed by STRLEN_CODE
    pop eax ; get saved 'here' position
    add eax, ebx ; advance 'here' by that amt
    inc eax      ; plus one for the null
    ; Store here in 'here'
    mov [here], eax
    ; return us to immediate mode now that we're done
    mov dword [mode], IMMEDIATE
ENDWORD semicolon, ";", (COMPILE | RUNCOMP)

; Checks if the next character is a quote. If not, do
; nothing. If it is, copy the string up to the endquote into
; the data_area and then return its address. Update free.
DEFWORD quote
    mov ebp, [input_buffer_pos]
    mov al, [ebp]
    cmp al, '"'         ; next char a quote?
    jne .quote_done     ; nope, do nothing
    inc ebp             ; yup, now move past it
    mov ecx, 0          ; initialize input pos
    mov ebx, [free]     ; get string's new address
    ; If we're in immediate mode, we will push this new
    ; string's address on the stack immediately. But if
    ; we're in compile mode, we need to inline code to push
    ; the string's address at run time!
    cmp dword [mode], IMMEDIATE
    je .immediately
    mov edx, [here]          ; compile mode, compile here
    mov byte [edx], 0x68     ; i386 opcode for PUSH imm32
    mov dword [edx + 1], ebx ; address of string
    add edx, 5               ; update here
    mov [here], edx          ; save it
    jmp .copy_char
.immediately:
    push ebx            ; just put addr on stack now
.copy_char:
    mov al, [ebp + ecx]
    cmp al, '"'         ; look for endquote
    je .end_quote
    mov [ebx + ecx], al ; copy character
    inc ecx             ; next char
    jmp .copy_char      ; loop
.end_quote:
    lea eax, [ebp + ecx + 1]    ; get next input position
    mov [input_buffer_pos], eax ; save it
    mov [ebx + ecx], byte 0     ; terminate str null
    lea eax, [ebx + ecx + 1]    ; calc next free space
    mov [free], eax             ; save it
    EAT_SPACES_CODE             ; advance to next token
.quote_done:
ENDWORD quote, 'quote', (IMMEDIATE | COMPILE)


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
    mov dword [here], compile_area

    ; Free points to the next free space in the data area
    ; where all variables and non-stack data goes.
    mov dword [free], data_area

    ; Store last tail for dictionary searches (note that
	; find just happens to be the last word defined in the
	; dictionary at the moment).
    mov dword [last], LAST_WORD_TAIL

    ; This will probably _really_ get set when we read
    ; more input. But for now, set to start of buffer:
    mov dword [input_buffer_pos], input_buffer

    PRINTSTR "Hello world!"
    NEWLINE_CODE

    DEBUG "[here] starting at 0x", [here]

; ----------------------------------------------------------
; Interpreter!
; ----------------------------------------------------------
get_next_token:
    CALLWORD eat_spaces
    CALLWORD quote      ; handle any string literals
    CALLWORD get_token
    cmp dword [esp], 0  ; check return without popping
    je .end_of_input    ; all out of tokens!
       ; DEBUG "Finding...", [esp]
       ;  push token_buffer
       ;  CALLWORD print
       ;  CALLWORD newline
    CALLWORD find       ; find token, returns tail addr
    cmp dword [esp], 0  ; check return without popping
    je .token_not_found
    cmp dword [mode], IMMEDIATE
    je .exec_word
    ; We're in compile mode...
    CALLWORD get_flags
    CALLWORD is_runcomp
    pop eax    ; get result
    cmp eax, 0 ; if NOT equal, word was RUNCOMP
    jne .exec_word ; yup, RUNCOMP
       ; DEBUG "Inlining...", [esp]
       ;  push token_buffer
       ;  CALLWORD print
       ;  CALLWORD newline
    CALLWORD inline ; nope, "compile" it.
    jmp get_next_token
.exec_word:
       ; DEBUG "Running...", [esp]
       ;  push token_buffer
       ;  CALLWORD print
       ;  CALLWORD newline
    ; Run current word in immediate mode!
    ; We currently have the tail of a found word.
    pop ebx ; addr of word tail left on stack by 'find'
    mov eax, [ebx + T_CODE_OFFSET]
    sub ebx, eax ; set to start of word's machine code
    CALLWORD ebx ; call word with that addr (via reg)
    jmp get_next_token
.end_of_input:
    PRINTSTR 'Ran out of input!'
    CALLWORD newline
    CALLWORD exit
.token_not_found:
    ; Putting strings together this way is quite painful...
    ; "Could not find word "foo" while looking in <mode> mode."
    PRINTSTR 'Could not find word "'
    push token_buffer
    CALLWORD print
    PRINTSTR '" while looking in '
    cmp dword [mode], IMMEDIATE
    je .immediate_not_found
    PRINTSTR 'COMPILE'
    jmp .finish_not_found
.immediate_not_found:
    PRINTSTR 'IMMEDIATE'
.finish_not_found:
    PRINTSTR ' mode.'
    NEWLINE_CODE
    CALLWORD exit
