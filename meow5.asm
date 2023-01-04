; +--------------------------------------------------------+
; |       >o.o<   Meow5: A very conCATenative language     |
; +--------------------------------------------------------+

; Meow5 Constants
%assign INPUT_SIZE 1024 ; size of input buffer
%assign COMPILE   00000001b ; flag: can be compiled
%assign IMMEDIATE 00000010b ; flag: can be called
%assign RUNCOMP   00000100b ; flag: runs in comp mode

; Linux Constants
%assign STDIN 0
%assign STDOUT 1
%assign STDERR 2
%assign SYS_EXIT 1
%assign SYS_READ 3
%assign SYS_WRITE 4
%assign SYS_OPEN 5
%assign SYS_CLOSE 6

; TODO add SYS_CREATE 8

; ----------------------------------------------------------
; BSS - reserved space
; ----------------------------------------------------------
section .bss
mode: resb 4            ; IMMEDATE or COMPILE
var_radix: resb 4       ; decimal=10, hex=16, etc.
input_file: resb 4      ; input file desc. (STDIN, etc.)
last: resb 4            ; Pointer to last defined word tail
here: resb 4            ; Will point to compile_area
free: resb 4            ; Will point to data_area
stack_start: resb 4     ; Will point to first stack addr
token_buffer: resb 32   ; For get_token
name_buffer:  resb 32   ; For colon (copy of token)
compile_area: resb 4096 ; We inline ("compile") here!
data_area: resb 1024    ; All variables go here!

input_buffer: resb INPUT_SIZE ; input from user (or file?)
input_buffer_end: resb 4      ; current last addr of input
input_buffer_pos: resb 4      ; current position in input
input_eof: resb 4             ; flag 1=EOF reached

; Return address for immediate mode execution only
return_addr:   resb 4    ; To "push/pop" return stack

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
        pusha ; preserve all registers
        ; Print the string
        mov ebx, STDOUT
        mov edx, mystr_len
        mov ecx, %%mystr
        mov eax, SYS_WRITE
        int 0x80
        popa ; restore all registers
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

%macro EXIT_CODE 0
    pop ebx ; param1: exit code
    mov eax, SYS_EXIT
    int 0x80
%endmacro
DEFWORD exit
    EXIT_CODE
ENDWORD exit, "exit", (COMPILE | IMMEDIATE) 

; Gets length of null-terminated string
%macro STRLEN_CODE 0
    pop eax
    mov ecx, 0     ; byte counter will contain len
%%find_null:
    cmp byte [eax + ecx], 0 ; null term?
    je %%strlen_done         ; yes, done
    inc ecx                 ; no, continue
    jmp %%find_null         ; loop
%%strlen_done:
    push ecx           ; return len
%endmacro
DEFWORD strlen ; (straddr) strlen (straddr len)
    STRLEN_CODE
ENDWORD strlen, "strlen", (IMMEDIATE | COMPILE)

; Prints a string by address and length
%macro LEN_PRINT_CODE 0
    pop edx            ; strlen from stack
    pop ecx            ; string address from stack
    mov ebx, STDOUT    ; write destination file
    mov eax, SYS_WRITE ; syscall
    int 0x80           ; interrupt to linux!
%endmacro

; Prints a null-terminated string by address on stack.
%macro PRINT_CODE 0
    pop eax
    push eax ; one for strlen
    push eax ; one for write
    STRLEN_CODE  ; (after: straddr, len)
    LEN_PRINT_CODE
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

%macro FIND_CODE 0
    pop ebp ; param1 - start of word string to find
    ; in-word register use:
    ;   al  - to-find name character being checked
	;   ebx - start of dict word's name string
	;   ecx - byte offset counter (each string character)
    ;   edx - dictionary list pointer
    ; search backwards from last word
    mov edx, [last]
%%test_word:
    cmp edx, 0  ; a null pointer (0) is end of list
    je %%not_found
    ; First, see if this word is for the mode we're
    ; currently in (IMMEDIATE vs COMPILE):
    mov eax, [mode]
    and eax, [edx + T_FLAGS] ; see if mode bit is set in word tail
    cmp eax, 0
    jz %%try_next_word ; bit wasn't set to match this mode
    ; Now we'll compare name to find vs this dictionary name
    ; (ebx vs edx) byte-by-byte until a mismatch or one hits
    ; a 0 terminator first.  Only having all correct letters
    ; AND hitting 0 at the same time is a match.
    lea ebx, [edx + T_NAME] ; set dict. word name pointer
    mov ecx, 0          ; reset byte offset counter
%%compare_names_loop:
	mov al, [ebp + ecx] ; get next to-find name byte
    cmp al, [ebx + ecx] ; compare with next dict word byte
    jne %%try_next_word  ; found a mismatch!
    cmp al, 0           ; both hit 0 terminator at same time
    je %%found_it
	inc ecx
	jmp %%compare_names_loop
%%try_next_word:
    mov edx, [edx]   ; follow the tail! (linked list)
    jmp %%test_word
%%not_found:
    push 0   ; return 0 to indicate not found
    jmp %%done
%%found_it:
    push edx ; return  pointer to tail of dictionary word
%%done:
%endmacro
DEFWORD find
    FIND_CODE
ENDWORD find, "find", (IMMEDIATE)

; Gets input from a file, filling input_buffer and resetting
; input_buffer_pos.
%macro GET_INPUT_CODE 0
    pusha ; preserve all reg
    ; Fill input buffer via linux 'read' syscall
    mov ebx, [input_file] ; file descriptor (default STDIN)
    mov ecx, input_buffer ; buffer for read
    mov edx, INPUT_SIZE   ; max bytes to read
    mov eax, SYS_READ     ; linux syscall 'read'
    int 0x80              ; syscall interrupt!
    cmp eax, 0            ; 0=EOF, -1=error
    jg %%normal
    mov dword [input_eof], 1  ; set EOF reached
%%normal:
    lea ebx, [input_buffer + eax] ; end of current input
    mov dword [input_buffer_end], ebx ; save it
;    cmp eax, INPUT_SIZE   ; we read less than full buffer?
;    jge %%done            ; No, continue
;    mov byte [input_buffer + eax], 0 ; Yes, null-terminate
;%%done:
    mov dword [input_buffer_pos], input_buffer ; reset pos
    popa ; restore all reg
%endmacro
DEFWORD get_input
    GET_INPUT_CODE
ENDWORD get_input, "get_input", (IMMEDIATE | COMPILE)

; Skips any characters space and below from input buffer.
%macro EAT_SPACES_CODE 0
.reset:
    mov esi, [input_buffer_pos] ; set input index
    cmp dword [input_eof], 1
    je .done ; we hit eof at some point, we're done
    mov ebx, [input_buffer_end] ; store for comparison
.check:
    cmp esi, ebx    ; have we hit end pos?
    jl .continue    ; no, keep going
    GET_INPUT_CODE  ; yes, get some
    jmp .reset      ; got more input, reset and continue
.continue:
    mov al, [esi]   ; input addr + position index
    cmp al, 0       ; end of input (null terminator)?
    je .done        ; yes, return
    cmp al, 0x20    ; anything space and below?
    jg .done        ; nope, we're done
    inc esi         ; 'eat' space by advancing input
    jmp .check      ; loop
.done:
    mov [input_buffer_pos], esi ; save input index
%endmacro
DEFWORD eat_spaces
    EAT_SPACES_CODE
ENDWORD eat_spaces, "eat_spaces", (IMMEDIATE | COMPILE)

; Gets a space-separated "token" of input.
; Returns a null-terminated string OR 0 if we're out of
; input.
%macro GET_TOKEN_CODE 0
; was:
;  ebx = input   <-- esi
;  edx = output  <-- edi
    mov esi, [input_buffer_pos] ; input source index
    mov edi, token_buffer       ; destination index
.get_char:
    cmp esi, [input_buffer_end] ; need to get more input?
    jl .skip_read               ; no, keep going
    GET_INPUT_CODE              ; yes, get some
    cmp dword [input_eof], 1
    je .return ; we hit eof, we're done
    mov esi, [input_buffer_pos] ; reset source index
.skip_read:
    mov al, [esi]       ; input addr + position index
    cmp al, 0x20        ; end of token (spece or lower?)
    jle .end_of_token   ; yes
    mov byte [edi], al  ; write character
    inc esi ; next source
    inc edi ; next destination
    jmp .get_char
.end_of_token:
    cmp edi, token_buffer ; did we write anything?
    jg .return_token      ; yes, push the token addr
    push DWORD 0          ; no, push 0 ("no token")
    jmp .return
.return_token:
    mov [input_buffer_pos], esi ; save position
    mov byte [edi], 0           ; null-terminate token str
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
%%copy_char:
    mov  al, [esi + ecx] ; from source
    mov  [edi + ecx], al ; to dest
    inc  ecx
    cmp al, 0            ; hit terminator?
    jnz %%copy_char
%endmacro
DEFWORD copystr ; (sourceaddr, destaddr) copystr ()
    COPYSTR_CODE
ENDWORD copystr, "copystr", (IMMEDIATE | COMPILE)

DEFWORD colon
    mov dword [mode], COMPILE
    ; get name from next token and store it...
    EAT_SPACES_CODE
    GET_TOKEN_CODE     ; leaves source addr for copystr
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

; Does what ENDWORD macro does, but into memory at runtime.
%macro SEMICOLON_CODE 0
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
%endmacro
DEFWORD semicolon
    SEMICOLON_CODE
ENDWORD semicolon, ";", (COMPILE | RUNCOMP)

; Takes an addr and number from stack, writes string
; representation (not null-terminated) of number to the
; address and returns number of bytes (characters) written.
%macro NUM2STR_CODE 0
    pop ebp ; address of string destination
    pop eax ; number
    mov ecx, 0 ; counter of digit characters
    mov ebx, [var_radix]
%%divide_next:    ; idiv divides
    mov edx, 0   ; div actually divides edx:eax / ebx!
    div ebx      ; eax / ebx = eax, remainder in edx
    cmp edx, 9   ; digit bigger than 9? (radix allows a-z)
    jg %%toalpha  ; yes, convert to 'a'-'z'
    add edx, '0' ; no, convert to '0'-'9'
    jmp %%store_char
%%toalpha:
    add edx, ('a'-10) ; to convert 10 to 'a'
%%store_char:
    push edx ; put on stack (pop later to reverse order)
    inc ecx
    cmp eax, 0        ; are we done converting?
    jne %%divide_next  ; no, loop
    mov eax, ecx      ; yes, store counter as return value
    mov ecx, 0        ; now we'll count up
%%store_next:
    pop edx  ; popping to reverse order
    mov [ebp + ecx], edx  ; store it at addr!
    inc ecx
    cmp ecx, eax      ; are we done storing?
    jl %%store_next
    push eax  ; return num chars written
%endmacro
DEFWORD num2str ; (num addr -- bytes_written)
    NUM2STR_CODE
ENDWORD num2str, "num2str", (IMMEDIATE | COMPILE)

; Checks if the next character is a quote. If not, do
; nothing. If it is, copy the string up to the endquote into
; the data_area and then return its address. Update free.
DEFWORD quote
    mov esi, [input_buffer_pos] ; source
    inc esi             ; yup, now move past it
    mov edi, [free]     ; get string's new address
    ; If compile mode, compile the instruction to push the
    ; string's address.
    cmp dword [mode], COMPILE ; compile mode?
    jne .copy_char            ; no, skip it
    mov edx, [here]           ; yes, compile here
    mov byte [edx], 0x68      ; i386 opcode for PUSH imm32
    mov dword [edx + 1], edi  ; address of string
    add edx, 5                ; update here
    mov [here], edx           ; save it
.copy_char:
    cmp esi, [input_buffer_end] ; need to get more input?
    jl .skip_read               ; no, keep going
    GET_INPUT_CODE              ; yes, get some
    cmp dword [input_eof], 1
    je .quote_done ; we hit eof, we're done
    mov esi, [input_buffer_pos] ; reset source index
.skip_read:
    mov al, [esi]       ; get char from source
    cmp al, '"'         ; look for endquote
    je .end_quote
    cmp al, '\'         ; escape sequence
    je .insert_esc
    mov [edi], al         ; copy char to desination
    inc esi             ; next source char
    inc edi             ; next desination pos
    jmp .copy_char      ; loop
.insert_esc:
    ; read the next character to determine what to do:
    inc esi
    mov al, [esi]
    cmp al, '\' ; literal backslash
    jne .esc2
        mov byte [edi], '\'
        inc esi
        inc edi
        jmp .copy_char
    .esc2:
    cmp al, '$' ; literal $
    jne .esc3
        mov byte [edi], '$'
        inc esi
        inc edi
        jmp .copy_char
    .esc3:
    cmp al, 'n' ; newline
    jne .esc4
        mov byte [edi], 0xa
        inc esi
        inc edi
        jmp .copy_char
    .esc4:
.end_quote:
    lea eax, [esi + 1]          ; get next input position
    mov [input_buffer_pos], eax ; save it
    mov [edi], byte 0             ; terminate str null
    lea eax, [edi + 1]          ; calc next free space
    cmp dword [mode], IMMEDIATE ; immediate mode?
    jne .quote_skip_push        ; no, skip it
    push dword [free]           ; yes, push string addr
.quote_skip_push:
    mov [free], eax             ; save it
    EAT_SPACES_CODE             ; advance to next token
.quote_done:
ENDWORD quote, 'quote', (IMMEDIATE | COMPILE)

; Attempts to parse num from string using radix.
; Doesn't handle negative sign. Leaves just 0
; (false) on stack if not successful.
%macro STR2NUM_CODE 0 ; (str_addr -- [num] success)
    pop ebp ; address of input token
    mov eax, 0 ; result
    mov ebx, 0 ; char conversion
    mov ecx, 0 ; char counter/pointer
    mov edx, [var_radix]
.next_char:
    mov bl, [ebp + ecx] ; put char in bl
    cmp bl, 0           ; null terminator?
    je .return_num      ; yup, return value
    inc ecx
    ; Multiply the current value by the radix to prepare for
    ; the next, less significant digit. If we're starting
    ; out, the current value is 0, which is no problem.
    imul eax, edx
    cmp bl, '0'         ; ASCII less than '0' is invalid
    jl .error
    cmp bl, '9'         ; is it '0'-'9'?
    jg .try_upper       ; no, try 'A'-'Z'
    sub bl, '0'         ; yes, convert ASCII '0' to 0
    jmp .add_value
.try_upper:
    cmp bl, 'A'
    jl .error
    cmp bl, 'Z'
    jg .try_lower
    sub bl, ('A'-10) ; it's uppercase, convert 'A' to 10
    jmp .add_value
.try_lower:
    cmp bl, 'z'
    jg .error
    sub bl, ('a'-10) ; it's lowercase, convert 'a' to 10
    jmp .add_value
.add_value:
    ; Make sure the number is within the radix
    cmp bl, dl ; edx has radix
    jg .error  ; greater than radix
    add eax, ebx   ; bl has converted char's value
    jmp .next_char ; loop
.error:
    push 0         ; failure code (false)
    jmp .str2num_done
.return_num:
    cmp ecx, 0     ; did we actually get any chars?
    je .error      ; no, empty token string! error
    push eax       ; push number
    push 1         ; success (true)
.str2num_done:
%endmacro
DEFWORD str2num ; (str_addr -- [num] success)
    STR2NUM_CODE
ENDWORD str2num, 'str2num', (IMMEDIATE | COMPILE)

%macro RADIX_CODE 0
    pop eax
    mov [var_radix], eax
%endmacro
DEFWORD radix
    RADIX_CODE
ENDWORD radix, 'radix', (IMMEDIATE | COMPILE)
DEFWORD hex
    mov dword [var_radix], 16
ENDWORD hex, 'hex', (IMMEDIATE | COMPILE)
DEFWORD oct
    mov dword [var_radix], 8 
ENDWORD oct, 'oct', (IMMEDIATE | COMPILE)
DEFWORD bin
    mov dword [var_radix], 2
ENDWORD bin, 'bin', (IMMEDIATE | COMPILE)
DEFWORD decimal
    mov dword [var_radix], 10
ENDWORD decimal, 'decimal', (IMMEDIATE | COMPILE)

; see if token starts with number. if it does, parse it
DEFWORD number
    GET_TOKEN_CODE
    STR2NUM_CODE
    pop eax              ; return value from str2num
    cmp eax, 0           ; did it fail?
    je .invalid_number
    cmp dword [mode], COMPILE
    je .compile_number
    ; We got number in IMMEDIATE mode, so just keep the
    ; value on the stack and keep going!
    jmp .done
.compile_number:
    ; like 'quote' and 'var', this writes a raw x86
    ; opcode to push an immediate value on the stack
    ; at runtime
    pop eax ; get number from stack
    mov edx, [here]          ; compile var code here
    mov byte [edx], 0x68     ; i386 opcode for PUSH imm32
    mov dword [edx + 1], eax ; the number literal
    add edx, 5               ; update here
    mov [here], edx
    jmp .done
.invalid_number:
    ; If we got here, there was a token that started with a
    ; digit, but could not be parsed as a number. We're
    ; defining that as a fatal error.
    PRINTSTR 'Error parsing "'
    push token_buffer
    CALLWORD print
    PRINTSTR `" as a number.\n`
    EXIT_CODE
.done:
ENDWORD number, 'number', (IMMEDIATE | COMPILE)

; Call with num to to be printed on the stack
%macro PRINTNUM_CODE 0
    ; param2 address desination for number str
    mov eax, [free] ; use free space temporarily
    push eax ; addr for num2str
    NUM2STR_CODE ; leaves length of string
    pop ebx
    mov eax, [free]
    push eax ; addr
    push ebx ; len
    LEN_PRINT_CODE
%endmacro
DEFWORD printnum
    PRINTNUM_CODE
ENDWORD printnum, 'printnum', (IMMEDIATE | COMPILE)

%macro PRINT_FMT_CODE 0
    pop esi ; string addr from stack is source pointer
    mov ecx, 0   ; length of string to print
.examine_char:
    mov al, [esi + ecx]  ; get next char
    cmp al, '$'
    je .print_num
    cmp al, 0 ; regular end of string!
    je .print_the_rest
    inc ecx              ; neither, keep going
    jmp .examine_char
.print_num:
    ; first print the string segment before the num
    pop eax  ; get number to print from stack
    push esi ; str addr (save a copy)
    push ecx ; str len  (save a copy)
    push eax ; num to print
    push esi ; str addr
    push ecx ; str len
    LEN_PRINT_CODE
    PRINTNUM_CODE ; print number from stack
    pop ecx ; restore str len
    pop esi ; restore str addr
    ; reset string to *after* the '$' placeholder and
    ; keep printing
    lea esi, [esi + ecx + 1]
    mov ecx, 0
    jmp .examine_char
.print_the_rest:
    ; now we just need to print a "normal" string at
    ; the end, so push the start address and print!
    push esi ; print just needs start address
    PRINT_CODE
%endmacro
DEFWORD print_fmt
    PRINT_FMT_CODE
ENDWORD print_fmt, 'print$', (IMMEDIATE | COMPILE)

DEFWORD say
    PRINT_FMT_CODE
    mov eax, [free]
    mov byte [eax], 0xa ; '\n'
    push eax    ; addr of string
    push 1      ; length to print
    LEN_PRINT_CODE
ENDWORD say, 'say', (IMMEDIATE | COMPILE)

; Given a mode (dword) on the stack, prints the matching
; modes (immediate/compile/runcomp).
%macro PRINTMODE_CODE 0
    pop eax ; get mode dword
    mov ebx, eax
    and ebx, IMMEDIATE
    jz %%try_compile
    push eax ; save
    PRINTSTR 'IMMEDIATE '
    pop eax ; restore
%%try_compile:
    mov ebx, eax
    and ebx, COMPILE
    jz %%try_runcomp
    push eax ; save
    PRINTSTR 'COMPILE '
    pop eax ; restore
%%try_runcomp:
    mov ebx, eax
    and ebx, RUNCOMP
    jz %%done
    push eax ; save
    PRINTSTR 'RUNCOMP '
    pop eax ; restore
%%done:
%endmacro
DEFWORD printmode
    PRINTMODE_CODE
ENDWORD printmode, 'printmode', (IMMEDIATE | COMPILE)

%macro PRINTSTACK_CODE 0
    mov ecx, [stack_start]
    sub ecx, esp ; difference between start and current
%%dword_loop:
    cmp ecx, 0           ; reached start?
    jl %%done            ; yup, done
    mov eax, [esp + ecx] ; no, print this value
    push ecx ; preserve
    push eax ; print this value
    PRINTNUM_CODE
    PRINTSTR " "
    pop ecx  ; restore
    sub ecx, 4 ; reduce stack index by dword
    jmp %%dword_loop
%%done:
    PRINTSTR `\n`
%endmacro
DEFWORD printstack
    PRINTSTACK_CODE
ENDWORD printstack, 'ps', (IMMEDIATE | COMPILE)

; Takes word tail addr, prints meta-info (from tail)
%macro INSPECT_CODE 0
    pop esi ; get tail addr
    lea eax, [esi + T_NAME]
    push esi ; preserve tail
    push eax
    PRINT_CODE 
    PRINTSTR ": "
    pop esi ; restore tail
    mov eax, [esi + T_CODE_LEN]
    push esi ; preserve tail
    ; param 1: num to be stringified
    push eax
    PRINTNUM_CODE
    PRINTSTR " bytes "
    pop esi ; restore tail
    mov eax, [esi + T_FLAGS]
    push eax
    PRINTMODE_CODE
    PRINTSTR `\n`
%endmacro
DEFWORD inspect
    INSPECT_CODE
ENDWORD inspect, 'inspect', (IMMEDIATE)

; inspects everything in reverse order, starting with the
; last thing defined (because that's how the linked list
; works).
DEFWORD inspect_all
    mov eax, [last] ; tail addr of last word defined
.inspect_loop:
    mov ebx, [eax]  ; tail of prev word in linked list
    push ebx ; save next addr pointer
    push eax ; inspect this one
    INSPECT_CODE
    pop eax  ; get saved next addr pointer
    cmp eax, 0        ; done?
    jne .inspect_loop ; nope, keep going!
ENDWORD inspect_all, 'inspect_all', (IMMEDIATE)

; Print all word names
DEFWORD all_names
    mov esi, [last] ; tail addr of last word defined
.print_loop:
    lea eax, [esi + T_NAME] ; name
    mov esi, [esi] ; get prev tail pointer
    push esi       ; preserve it
    push eax ; name for print
    PRINT_CODE
    PRINTSTR " " ; space between names
    pop esi ; restore tail
    cmp esi, 0        ; done?
    jne .print_loop ; nope, keep going!
    PRINTSTR `\n`
ENDWORD all_names, 'all', (IMMEDIATE)

DEFWORD add
    pop eax
    pop ebx
    add eax, ebx
    push eax
ENDWORD add, '+', (IMMEDIATE | COMPILE)

DEFWORD sub
    pop ebx
    pop eax
    sub eax, ebx
    push eax
ENDWORD sub, '-', (IMMEDIATE | COMPILE)

DEFWORD mul
    pop eax
    pop ebx
    imul eax, ebx
    push eax
ENDWORD mul, '*', (IMMEDIATE | COMPILE)

DEFWORD div
    mov edx, 0
    pop ebx
    pop eax
    idiv ebx
    push edx ; remainder
    push eax ; answer (quotient)
ENDWORD div, '/', (IMMEDIATE | COMPILE)

DEFWORD inc
    pop ecx
    inc ecx
    push ecx
ENDWORD inc, 'inc', (IMMEDIATE | COMPILE)

DEFWORD dec
    pop ecx
    dec ecx
    push ecx
ENDWORD dec, 'dec', (IMMEDIATE | COMPILE)

; 'var' reserves a new space in memory (4 bytes for now) and
; creates a new word that puts the ADDRESS of that memory on
; the stack when it is called.
DEFWORD var
    mov dword [mode], COMPILE
    ; get name from next token and store it...
    EAT_SPACES_CODE
    GET_TOKEN_CODE
    push name_buffer  ; dest
    COPYSTR_CODE      ; copy name into name_buffer
    mov eax, [free]   ; get current free space addr
    ; Identical to 'quote' - so probably consolidate
    ; into a macro if it works reliably
    mov edx, [here]           ; compile var code here
    push edx ; save it for semicolon!
    mov byte [edx], 0x68      ; i386 opcode for PUSH imm32
    mov dword [edx + 1], eax  ; address of var space
    add edx, 5                ; update here
    mov [here], edx
    add eax, 4                ; update free pointer
    mov [free], eax
    SEMICOLON_CODE
ENDWORD var, 'var', (IMMEDIATE | COMPILE)

DEFWORD setvar
    pop edi ; address from stack
    pop eax ; value from stack
    mov [edi], eax ; set it!
ENDWORD setvar, 'set', (IMMEDIATE | COMPILE)

DEFWORD getvar
    pop esi ; address from stack
    mov eax, [esi] ; get it!
    push eax ; put it on the stack
ENDWORD getvar, 'get', (IMMEDIATE | COMPILE)


; *******************************************
; *     Attempt to write an ELF header!     *
; *******************************************

section .data
%assign elf_va 0x08048000 ; elf virt mem start address
elf_header:
    ; ELF Identification (16 bytes)
    db 0x7F,'ELF' ; Magic String
    db          1 ; "File class" 32 bit
    db          1 ; "Data encoding" 1=LSB (x86 little endian)
    db          1 ; "File version" ELF version (1="current")
    times 9 db  0 ; padding (to fill up 16 bytes)
    ; Section Header Table
    dw          2 ; type      - 2="Executable file"
    dw          3 ; machine   - 3="Intel 80386"
    dd          1 ; version   - 1="Current"
    dd elf_va + elf_size ; entry - execution start address
    dd phdr - elf_header ; phoff - bytes to program header
    dd          0 ; shoff     - 0 for no section header
    dd          0 ; flags     - processor-specific flags
    dw   hdr_size ; ehsize    - this header bytes, see below
    ; We want the "program header" because that says how to
    ; layout stuff in memory when we run. we do NOT need the
    ; "section header" because that's more for compilers and
    ; linkers.
    dw  phdr_size ; phentsize - program header size
    dw          1 ; phnum     - program header count
    dw          0 ; shentsize - section header size (none)
    dw          0 ; shnum     - section header count
    dw          0 ; shstrndx  - section header offset
    hdr_size equ $ - elf_header ; calulate elf header size

    ; This program header is for the compiled (inlined) word
    ; machine code that we'll be writing out to make the
    ; program. So the "file size" and "mem size" should be
    ; equal.

phdr: ; Program Header
    dd         1 ; p_type   - 1=PT_LOAD, map file to memory
    dd         0 ; p_offset - bof to first byte of segment
    dd    elf_va ; p_vaddr  - virt addr of 1st byte of segment
    dd         0 ; p_paddr  - phys addr (can probably ignore)

    ; TODO: Before writing out this elf header, these two
    ; bytes/sizes need to be written.

prog_bytes1:
    dd         0 ; p_filesz - bytes file image of segment
prog_bytes2:
    dd         0 ; p_memsz  - bytes memory image of segment
    dd         5 ; p_flags  -
    dd         0 ; p_align  - no alignment required
    phdr_size equ $ - phdr ; calculate program header size

    ; TODO: I'm pretty sure I need another program header
    ; for the data segment, which I think fits both the
    ; initialized and uninitialized memory for storage.
    ;
    ; Don't forget to update the 'phnum' from 1 to 2.
    elf_size equ $ - elf_header


section .text

DEFWORD make_elf
    EAT_SPACES_CODE
    GET_TOKEN_CODE ; get address of next token's string
    FIND_CODE      ; get tail of word matching token
    ; TODO: handle failure of 'find'
    pop esi ; addr of tail (and keep in esi the whole time)
    mov eax, [esi + T_CODE_LEN]    ; get len of code
    ; Overwrite the placeholder program size values in the
    ; ELF header data section with this word's code size.
    mov [prog_bytes1], eax
    mov [prog_bytes2], eax
DEBUG "prog bytes: ", eax

    ; From open(2) man page:
    ;   A call to creat() is equivalent to calling open()
    ; with flags equal to O_CREAT|O_WRONLY|O_TRUNC.
    ; I got the flags by searching all of /usr/include and
    ; finding /usr/include/asm-generic/fcntl.h
    ; That yielded (along with bizarre comment "not fcntl"):
    ;   #define O_CREAT   00000100
    ;   #define O_WRONLY  00000001
    ;   #define O_TRUNC   00001000
    ; which are apparently octal values???
    ; Hence this flag value for 'open':
    mov ecx, (0100o | 0001o | 1000o)
    ; ebx contains null-terminated word name (see above)
    mov edx, 755o ; mode (permissions)
    mov eax, SYS_OPEN
    int 80h ; now eax will contain the new file desc.

    DEBUG "new fd: ", eax
    ; TODO: if open failed, print an error message and
    ;       skip to the end.


    ;
    ; Write ELF header
    mov edx, elf_size ; bytes to write
    mov ecx, elf_header      ; source address
    mov ebx, eax ; the fd for writing (opened/created above)
    mov eax, SYS_WRITE
    int 80h

    ;
    ; Write word (program)
    mov edx, [esi + T_CODE_LEN] ; bytes to write
    mov eax, [esi + T_CODE_OFFSET] ; for source addr
    mov ecx, esi ; tail addr
    sub ecx, eax ; source addr (code offset from tail)
    mov eax, SYS_WRITE ; ebx still has fd
    int 80h

    ;
    ; Close file (ebx still has fd)
    mov eax, SYS_CLOSE
    int 80h
ENDWORD make_elf, 'make_elf', (IMMEDIATE)

; ----------------------------------------------------------
; PROGRAM START!
; ----------------------------------------------------------
global _start
_start:
    cld    ; use increment order for certain cmds

    ; Start in immediate mode - execute words immediately!
    mov dword [mode], IMMEDIATE

    ; Default to input file descriptor STDIN. We can change
    ; this to make get_input read from different sources.
    mov dword [input_file], STDIN

	; Here points to the current spot where we're going to
	; inline ("compile") the next word.
    mov dword [here], compile_area

    ; Free points to the next free space in the data area
    ; where all variables and non-stack data goes.
    mov dword [free], data_area

    ; Store the first stack address so we can reference it
    ; later (such as printing contents of stack). Subtract 4
    ; so that we mark the *next* position as the first (sich
    ; it's the first position to which we'll push a value).
    lea eax, [esp - 4]
    mov [stack_start], eax

    ; Store last tail for dictionary searches (note that
	; find just happens to be the last word defined in the
	; dictionary at the moment).
    mov dword [last], LAST_WORD_TAIL

    ; In order to signal that we need to read input on
    ; start, set both the current read index and the end
    ; location to the start of the buffer.  Currently, the
    ; 'eat_spaces' word will see that and read more input.
    mov dword [input_buffer_pos], input_buffer
    mov dword [input_buffer_end], input_buffer
    mov dword [input_eof], 0 ; EOF flag

    ; Start off parsing and printing numbers as decimals.
    mov dword [var_radix], 10


; ----------------------------------------------------------
; Interpreter!
; ----------------------------------------------------------
get_next_token:
    mov eax, [input_eof]
    CALLWORD eat_spaces ; skip whitespace
    cmp dword [input_eof], 1 ; end of input?
    je .end_of_input ; yes, time to die
    ; Get the next character in the input stream to see what
    ; it is. Check for end of input, quotes, and numbers.
    mov esi, [input_buffer_pos] ; source
    mov al, [esi]               ; first char
.try_quote:
    cmp al, '"'         ; next char a quote?
    jne .try_num        ; nope, continue
    CALLWORD quote      ; yes, get string, leaves addr
    jmp get_next_token
.try_num:
    cmp al, '0'
    jl .try_token ; nope!
    cmp al, '9'
    jg .try_token ; nope!
    CALLWORD number     ; parse number, leaves value
    jmp get_next_token
.try_token:
    CALLWORD get_token
    pop eax    ; get_token returns address or 0
    cmp eax, 0
    je .end_of_input    ; all out of tokens!
    push token_buffer   ; for find
    CALLWORD find       ; find token, returns tail addr
    pop eax             ; find's return value
    cmp eax, 0          ; did find fail?
    je .token_not_found ; yup
    push eax ; find successful, put result back
    cmp dword [mode], IMMEDIATE
    je .exec_word
    ; We're in compile mode...
    CALLWORD get_flags
    CALLWORD is_runcomp
    pop eax    ; get result
    cmp eax, 0 ; if NOT equal, word was RUNCOMP
    jne .exec_word ; yup, RUNCOMP
    CALLWORD inline ; nope, "compile" it.
    jmp get_next_token
.exec_word:
    ; Run current word in immediate mode!
    ; We currently have the tail of a found word.
    pop ebx ; addr of word tail left on stack by 'find'
    mov eax, [ebx + T_CODE_OFFSET]
    sub ebx, eax ; set to start of word's machine code
    CALLWORD ebx ; call word with that addr (via reg)
    jmp get_next_token
.end_of_input:
    PRINTSTR `Goodbye.\n`
    push 0 ; exit status
    CALLWORD exit
.token_not_found:
    ; Putting strings together this way is quite painful...
    ; "Could not find word "foo" while looking in <mode> mode."
    PRINTSTR 'Could not find word "'
    push token_buffer
    CALLWORD print
    PRINTSTR '" while looking in '
    mov eax, [mode]
    push eax
    PRINTMODE_CODE
    PRINTSTR ` mode.\n`
    jmp get_next_token
