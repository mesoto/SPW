title.  SoftProbe - SP_Util

SP_UTIL EQU 1
include SP_DEFS.inc

LDATA_SEG       DWORD
PUBDWRD LastTimeStamp   <0,0>
PUBDWRD LogBuffer_Ptr   0
PUBBYTE Log_Falgs       LF_LOGON
LDATA_ENDS

; ---------------------------------------------------------------------------
SCODE_SEG       ; If faults happen, the TOS should have the return address
; ---------------------------------------------------------------------------

PUBPROC ReadTimeStamp
        clc
        db      0fh,31h         ;RDTSC
        mov     ecx, OFFSET32 LastTimeStamp
        mov     0[ecx], eax
        mov     4[ecx], edx
        ret

PUBPROC ReadMSR
        ; ecx = register#
        xor     eax, eax
        xor     edx, edx
        db      0fh,32h         ;RDMSR
        ret

PUBPROC str_len
        or      ecx, -1
strlen1:inc     ecx
        cmp     byte ptr [esi+ecx], 0
        jne     strlen1
        ret

; Case insensitive compare
; In:   ESI, EDI = ptr strings to compare
; Out:  CF:   0=equal, ECX=length
;             1=not-equal, ESI, EDI preserved
;       ESI, EDI are preserved.
PUBPROC lstrncmp
        mov     cl, [esi]
        inc     ecx                     ; include len byte
; Case insensitive compare
; In:   ESI, EDI = ptr strings to compare
;       CL = length (max 255)
; Out:  CF:   0=equal, al=next chr(esi), ah=next chr(edi)
;             1=not-equal
;       ESI, EDI, CL are preserved.
PUBPROC strncmp
        DBGBRK  5
        xor     eax, eax
strcmp1:mov     ch, [esi+eax]
        xor     ch, [edi+eax]
        je      short strcmp2
        cmp     ch, 20h
        jne     short strcmp3
        or      ch, [esi+eax]
        sub     ch, 'a'
        cmp     ch, 'z'-'a'+1
        jae     short strcmp3
strcmp2:inc     eax
        cmp     al, cl
        jb      short strcmp1
        xchg    ecx, eax
        mov     al, [esi+ecx]
        mov     ah, [edi+ecx]
        ret
strcmp3:movzx   ecx, cl
        stc
        ret

; input:        EAX:EBX = selector:offset
;               EAX= >0 for SELECTOR, <0 for SEGMENT
; returns: CF=0 EAX     = base address
;               EBX     = linear address
;               ESI     = access rights (if selector)
;               EDX     = address limit
;          CF=1 selector not available (EAX=EDX=0, EBX=1)
; ECX is preserved.

PUBPROC Get_FlatAddress
        test    eax, eax
        js      short v86_address
        call    Get_Selector
        jc      short no_access_sel

        ; Invert limits if expand down data segment (PLL10EWA)

        movzx   esi, word ptr [esi].AccessRights
        bt      esi, 4                  ;system type
        jnc     short add_to_base       ;yes, jump
        bt      esi, 3                  ;data selector?
        jc      short add_to_base       ;No, jump
        bt      esi, 2                  ;expand-down?
        jnc     short add_to_base       ;No, jump

        ; Expand down selector: inverse the limit

        add     ebx, eax
        inc     edx
        not     edx
        mov     Address_Limit, edx
        not     edx
        add     edx, eax
        mov     Address_Base, edx
        or      edx, -1
        mov     Address_Valid, dl
        ret

no_access_sel:
        xor     eax, eax
        cdq                             ;edx=0
        mov     Address_Valid, al
        stc
        ret

v86_address:
        movzx   eax, ax
        shl     eax, 4
        mov     edx, 0000ffffh
add_to_base:
        mov     Address_Limit, edx
        add     ebx, eax
        add     edx, eax
        jnc     short @f
        or      edx, -1
@@:     mov     Address_Base, eax
        mov     Address_Valid, 1
        ret

sys_cr4:
        db      0fh,20h,0e0h            ; mov eax, CR4
        clc
        ret

sys_cpuid:
        xor     eax, eax
        db      0fh,0a2h                ; CPUID
        ; ecx:edx:ebx=cpuid
        ret

sys_cpuid_info:
        xor     eax, eax
        inc     eax
        db      0fh,0a2h                ; CPUID
        ; eax=version information(type,family,model,stepping)
        ; edx=feature information
        ret

sys_rdpmc:
        ; CF=1:PMC[1], 0:PMC[1]
        sbb     ecx, ecx
        inc     ecx                     ;
        xor     edx, edx
        db      0fh,33h                 ; RDPMC
        ; edx:eax=PMC[ecx]
        ret

; MOVQ qword ptr [edi+8*n],MMXn
SaveMMX macro r
        db 0fh,7fh                      ; MOVQ
        db 47h+r*8,r*8                  ; [modrrrmmm]
        endm

mmx_registers:
        xor     eax, eax
        inc     eax
        db      0fh,0a2h                ; CPUID
        bt      edx, 23                 ; MMX supported?
        jnc     short @f
        SaveMMX 0
        SaveMMX 1
        SaveMMX 2
        SaveMMX 3
        SaveMMX 4
        SaveMMX 5
        SaveMMX 6
        SaveMMX 7
@@:     cmc
        ret

SCODE_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------

arg_table       dd OFFSET32 Skip_Blanks      ; 1 SKIP_BLANK al
                dd OFFSET32 just_ret         ; 2 JUMP_ADDRS
                dd OFFSET32 Scan_Expression  ; 3 SCAN_VAL32 ebx
                dd OFFSET32 Scan_BlockData   ; 4 DATA_BLOCK edx:ebx, ecx
                dd OFFSET32 Scan_BlockCode   ; 5 CODE_BLOCK edx:ebx, ecx
                dd OFFSET32 CheckLineEnd     ; 6 ENDOF_LINE
                dd OFFSET32 Skip_Blanks      ; 7 reserved type

dsp_cmdTable    dd OFFSET32 @@s_el     ;00
                dd OFFSET32 @@s_norm   ;01 a_n
                dd OFFSET32 @@s_bold   ;02 a_b
                dd OFFSET32 @@s_rvrs   ;03 a_r
                dd OFFSET32 @@s_fram   ;04 a_f
                dd OFFSET32 @@s_wtop   ;05 1st scrollable line
                dd OFFSET32 @@s_col    ;06 go column x (change it to mv2)
                dd OFFSET32 @@s_row    ;07 go row x, col 0
                dd OFFSET32 @@s_dup    ;08
                dd OFFSET32 @@s_tab    ;09
                dd OFFSET32 @@s_lf     ;0a scroll output window
                dd OFFSET32 @@s_spc    ;0b
                dd OFFSET32 @@s_window ;0c open full sized window
                dd OFFSET32 @@s_clreol ;0d
                dd OFFSET32 @@s_chr    ;0e

PUBPROC Parse_Line
; In:   ESP+0 = offset FullCmd's...0
;       ESP+4 = offset return address
; Out:   Found: Jump to arg_table[xx]
;    Not found: Jump to inst after FullCmd's...0
; Kills: ebx
        DBGBRK  5
        call    Skip_Blanks
PUBPROC Parse_LineNoSkip
        xchg    edi, [esp]      ; save edi, get &FullCmd
        jmp     short pl_search1
pl_search3:
        mov     bl, ah
pl_search0:
        lea     edi, [edi+ebx+4]
pl_search1:
        xor     ebx, ebx
        mov     ah, [edi]       ;len + type*16
        inc     edi
        and     ah, 15          ;len
        jz      short pl_not_found
pl_search2:
        mov     al, [esi+ebx]
        xor     al, [edi+ebx]
        jz      short pl_search4
        cmp     al, 20h
        jne     short pl_search3
        or      al, [esi+ebx]
        sub     al, 'a'
        cmp     al, 'z'-'a'+1
        jae     short pl_search3
pl_search4:
        inc     ebx
        cmp     bl, ah
        jb      short pl_search2
        DBGBRK  3
        test    byte ptr [edi-1], 80h   ; check for separator?
        jz      short pl_search5
        movzx   eax, byte ptr [esi+ebx]
        bt      Symbol_Character, eax   ; CF=1 if sym char
        jc      short pl_search0
pl_search5:
        add     esi, ebx
        mov     eax, [edi+ebx]
        xor     bl, [edi-1]
        and     bl, 70h
        jz      short pl_rel_go2
        pop     edi
        push    eax
        shr     bl, 2           ;CF=0
        jmp     arg_table[ebx-4]
pl_rel_go2:
        movsx   ebx, ax         ;relative address to ebx
        sar     eax, 16         ;16-bit value to return
        add     ebx, edi
        pop     edi
        jmp     ebx
pl_not_found:
        DBGBRK  5
        xor     eax, eax
        xchg    edi, [esp]      ;restore edi, set ret address
        stc
        ret                     ;not found (CF=1, eax=0)

PUBPROC Skip_Equal
        call    Skip_Blanks
        cmp     al, '='
        jne     short just_ret
        inc     esi
PUBPROC Skip_Blanks
        lods    byte ptr [esi]
        cmp     al, ' '
        je      short Skip_Blanks
        dec     esi
just_ret:
        test    al, al          ;ZF if end of line
        ret

PUBPROC Scan_Dword
        call    Scan_Expression
        jc      syntaxError
        ret

; In:   ESI = input data
; Out:  CF=1    error, EBX=ptr error string
;       CF=0    EDX:EBX=address
;               ESI points to next char
;               AL=next char
PUBPROC Scan_AddressCode
        mov     edx, Code_Data_Ptrs[PNTR_CODE][4]
        jmp     short Scan_AddressDef
PUBPROC Scan_AddressData
        mov     edx, Code_Data_Ptrs[PNTR_DATA][4]
        jmp     short Scan_AddressDef
PUBPROC Scan_AddressDS
        mov     edx, dword ptr [ebp].R_DS
PUBPROC Scan_AddressDef
        DBGBRK  3
        call    Scan_Expression
        jc      short get_addrss0
        cmp     al, ':'
        je      short get_addrss3
        cmp     al, '!'         ; V86 segment
        je      short get_addrss1
        cmp     al, '\'         ; PM selector
        je      short get_addrss2
        clc
        ret

get_addrss0:
        DBGBRK  3
        push    edx
        push    edi
        call    GetAddressFromName
        pop     edi
        jc      short get_addrss4
        mov     [esp], edx
        call    get_dwrd1       ; addr [+|-|... val]
get_addrss4:
        pop     edx
        ret

get_addrss1:
        stc                     ; 1=V86 segment
get_addrss2:
        sbb     edx, edx        ; set as seg/sel
get_addrss3:                    ; incomming type or implied one (ie CS:EIP)
        mov     dx, bx
        inc     esi
        push    edx
        call    Scan_Expression
cnt_failed:
        pop     edx
        ret

value_Neg:
        call    get_value
        jc      short @f
        neg     ebx
        clc
@@:     ret

value_Not:
        call    get_value
        jc      short @f
        not     ebx
        clc
@@:     ret

value_Content:
        push    edx
        call    Scan_AddressDS
        jc      short cnt_failed
        cmp     al, ']'
        stc
        jne     short cnt_failed
        inc     esi
        xchg    eax, edx
        push    esi
        call    Get_FlatAddress         ; ebx=linear address
        xchg    eax, esi                ; eax=access rights
        pop     esi
        jc      short cnt_failed
        pop     edx
        test    ah, 40h                 ; default size=32?
        jnz     short cnt_dword         ; yes, read a dword
        call    read_word_ltd
        xchg    ebx, eax
        ret
cnt_dword:
        call    read_dword_ltd
        xchg    ebx, eax
        ret

value_Group:
        call    Scan_Expression
        jc      short grp_val2
        inc     esi
        cmp     al, ')'
        je      short grp_val2
grp_val3:
        stc
grp_val2:
        ret

get_value:
        xor     ebx, ebx
get_val1:
        lodsb
        cmp     al, ' '
        je      short get_val1
        jb      short grp_val2
        cmp     al, '+'
        je      get_val1
        cmp     al, '-'
        je      value_Neg
        cmp     al, '('
        je      value_Group
        cmp     al, '['
        je      value_Content
        cmp     al, '~'
        je      value_Not
        cmp     al, '.'
        je      short dot_something
        dec     esi
        call    register_value
        jnc     short grp_val2

PUBPROC Scan_Hex
        lodsb
        cmp     al, ' '
        je      short Scan_Hex
        push    esi                     ; save for errors
        xor     ebx, ebx
scn_hex1:
        cmp     al, '0'
        jb      short scn_hex3
        cmp     al, '9'+1
        jb      short scn_hex2
        or      al, 32
        sub     al, 'a'
        cmp     al, 'g'-'a'
        jae     short scn_hex3
        add     al, 10
scn_hex2:
        shl     ebx, 4
        and     al, 0fh
        or      bl, al
        lodsb
        jmp     short scn_hex1

scn_hex3:
scn_dec2:
        dec     esi
        movzx   eax, byte ptr [esi]
        bt      Symbol_Character, eax   ; CF=1 if sym char
        pop     eax                     ; on col1+1
        jc      short get_hd1
        cmp     esi, eax                ; CF=0 if esi>=col1+1
        jae     short get_hd2
get_hd1:dec     eax                     ; back to col1
        xchg    esi, eax
        xor     ebx, ebx                ; return 0 when error
        stc
get_hd2:mov     al, [esi]
        ret

dot_something:
        mov     al, [esi]
        sub     al, '0'
        cmp     al, 10
        jae     short dot_SpecialPos    ;.xP/.xS
        ; .number
PUBPROC Scan_Decimal
        lodsb
        cmp     al, ' '
        je      short Scan_Decimal
        push    esi                     ; save for errors
        xor     ebx, ebx
scn_dec1:
        sub     al, '0'
        cmp     al, 10
        jae     short scn_dec2
        and     eax, 0fh
        imul    ebx, 10
        add     ebx, eax
        lodsb
        jmp     short scn_dec1

PUBPROC Get_Decimal
        xor     ebx, ebx
get_dec1:
        lodsb
        sub     al, '0'
        cmp     al, 10
        jae     short get_dec2
        and     eax, 0fh
        imul    ebx, 10
        add     ebx, eax
        jmp     short get_dec1
get_dec2:
        dec     esi
        xchg    eax, ebx
        ret

dot_SpecialPos:
        ; .x/.xS
        ; '.' is there, check the rest
        call    Parse_LineNoSkip
        FullCmd 'A'   GOTO_REL16  Ind_Data32 <PNTR_EFADR>
        FullCmd 'AS'  GOTO_REL16  Ind_Data16 <PNTR_EFADR + 4>
        FullCmd 'D'   GOTO_REL16  Ind_Data32 <PNTR_DATA>
        FullCmd 'DS'  GOTO_REL16  Ind_Data16 <PNTR_DATA + 4>
        FullCmd 'C'   GOTO_REL16  Ind_Data32 <PNTR_CODE>
        FullCmd 'CS'  GOTO_REL16  Ind_Data16 <PNTR_CODE + 4>
        FullCmd 'W'   GOTO_REL16  Ind_Data32 <PNTR_WATCH>
        FullCmd 'WS'  GOTO_REL16  Ind_Data16 <PNTR_WATCH + 4>
        FullCmd 'M'   GOTO_REL16  Ind_Data32 <PNTR_WORK>
        FullCmd 'MS'  GOTO_REL16  Ind_Data16 <PNTR_WORK + 4>
        FullCmd 'ML'  GOTO_REL16  Dos_Data32 <wrkBufSize>
        db 0
        dec     esi             ;back on '.'
        ret

; ---------------------------------------------------------------------------
; return get_value op get_value ....
PUBPROC Scan_Expression
        call    get_value
        jnc     short get_dwrd1
        ret

value_And:
        push    ebx
        call    get_value
        pop     eax
        jc      short get_dwrd2
        and     ebx, eax
        jmp     short get_dwrd1

value_Or:
        push    ebx
        call    get_value
        pop     eax
        jc      short get_dwrd2
        or      ebx, eax
        jmp     short get_dwrd1

value_Xor:
        push    ebx
        call    get_value
        pop     eax
        jc      short get_dwrd2
        xor     ebx, eax
        jmp     short get_dwrd1

value_Sub:
        push    ebx
        call    get_value
        pop     eax
        jc      short get_dwrd2
        neg     ebx
        jmp     short get_dwrd0

value_Add:
        push    ebx
        call    get_value
        pop     eax
        jc      short get_dwrd2
get_dwrd0:
        add     ebx, eax
get_dwrd1:
        lodsb
        cmp     al, ' '
        je      short get_dwrd1
        jl      short get_dwrd3
        cmp     al, '+'
        je      short value_Add
        cmp     al, '-'
        je      short value_Sub
        cmp     al, '&'
        je      short value_And
        cmp     al, '|'
        je      short value_Or
        cmp     al, '^'
        je      short value_Xor
        cmp     al, '*'
        je      short value_Mul
        cmp     al, '/'
        je      short value_Div
        cmp     al, '<'
        je      short value_Lower
        cmp     al, '>'
        je      short value_Higher
        cmp     al, '='
        je      short value_Equal
        cmp     al, '%'
        je      short value_Mod
get_dwrd3:
        dec     esi
        clc
get_dwrd2:
        ret

value_Mul:
        push    ebx
        call    get_value
        pop     eax
        jc      short get_dwrd2
        push    edx
        mul     ebx
        pop     edx
        xchg    ebx, eax
        jmp     get_dwrd1

value_Div:
        push    ebx
        call    get_value
        pop     eax
        jc      short get_dwrd2
        test    ebx, ebx
        jz      short divide_error
        push    edx
        xor     edx, edx
        div     ebx
        xchg    ebx, eax
        pop     edx
        jmp     get_dwrd1

value_Mod:
        push    ebx
        call    get_value
        pop     eax
        jc      short get_dwrd2
        test    ebx, ebx
        jz      short divide_error
        push    edx
        xor     edx, edx
        div     ebx
        mov     ebx, edx
        pop     edx
        jmp     get_dwrd1

divide_error:
;;      mov     ebx, OFFSET32 err_divide
        stc
        ret

;;err_divide:     db 'Divide error.',0

value_Equal:
        push    ebx
        call    Scan_Expression
        pop     ecx
        jc      short @f
        xor     ebx, ecx                ; c = b ?
        jnz     short ret_false         ; no
        dec     ebx
@@:     ret

value_Lower:
        cmp     byte ptr [esi], '>'
        je      short value_NotEq
        cmp     byte ptr [esi], '='
        jne     short value_Below
        ; <=
        inc     esi
        push    ebx
        call    Scan_Expression
        pop     ecx
        jc      short @f
        cmp     ebx, ecx                ; c <= b ?
        cmc
ret_false:
        sbb     ebx, ebx
        clc
@@:     ret

value_Higher:
        cmp     byte ptr [esi], '='
        jne     short value_Above
        ; >=
        inc     esi
        push    ebx
        call    Scan_Expression
        pop     ecx
        jc      short @f
        cmp     ebx, ecx                ; c >= b ?
        sbb     ebx, ebx                ; 1: b<c, 0: b>=c
        clc
@@:     ret

value_Below:
        push    ebx
        call    Scan_Expression
        pop     ecx
        jc      short @f
        cmp     ecx, ebx                ; c < b ?
        sbb     ebx, ebx
        clc
@@:     ret

value_NotEq:
        inc     esi
        push    ebx
        call    Scan_Expression
        pop     ecx
        jc      short @f
        xor     ebx, ecx                ; c = b ?
        jnz     short ret_true          ; if c <> b
@@:     ret

value_Above:
        push    ebx
        call    Scan_Expression
        pop     ecx
        jc      short @f
        cmp     ebx, ecx                ; c > b ?
        jae     short ret_false         ; if b >= c
ret_true:
        or      ebx, -1
@@:     ret

PUBPROC Scan_BlockCode
        mov     edx, Code_Data_Ptrs[PNTR_CODE][4]
        jmp     short Scan_MemBlock
PUBPROC Scan_BlockData
        mov     edx, Code_Data_Ptrs[PNTR_DATA][4]
PUBPROC Scan_MemBlock
        call    Scan_AddressDef
        jc      addressError
        push    edx
        push    ebx
        call    Skip_Blanks
        or      al, 32
        cmp     al, 'l'
        jne     short get_block2
        inc     esi
        call    Scan_Expression
        pop     ecx
        pop     edx
        jnc     short get_block3
rangeError:
        reportError 'Range Error.'

get_block2:
        call    Scan_Expression
        pop     ecx
        pop     edx
        jc      short rangeError
        sub     ebx, ecx
        jc      short rangeError
        inc     ebx
get_block3:
        xchg    ecx, ebx
        jecxz   short rangeError
got_string:
        ret

; get sequence of bytes terminated by 00,  save it in memory at EBX.

PUBPROC Scan_String
        call    Skip_Blanks
        jz      short got_string
        cmp     al, "'"
        je      short get_string2
        cmp     al, '"'
        je      short get_string2
        push    ebx
        call    Scan_Expression
        jc      syntaxError
;       movsx   eax, bl
;       cmp     eax, ebx
;       je      short get_string1
;       movzx   eax, bl
;       cmp     eax, ebx
;       jne     valueError
;get_string1:
        xchg    eax, ebx
        pop     ebx
        call    write_byte_al
        inc     ebx
        jnc     Scan_String
        jmp     short writeError

get_string2:
        inc     esi
        mov     ah, al
get_string3:
        lodsb
        cmp     al, 0
        je      Display_AllWindows
        cmp     al, ah
        je      Scan_String
        call    write_byte_al
        inc     ebx
        jnc     get_string3
writeError:
        jmp     write_Error

; ---------------------------------------------------------------------------
; Out:  CF = 0: eax = address of variable
;               ebx = value
;               edx = default segment value (if implied)
;               cl  = size: 1=8, 2=16, 3=32
PUBPROC register_value
        xor     ecx, ecx
        call    Parse_Line
        FullCmd 'EAX'  GOTO_REL16  DS_Stack32 <R_EAX>
        FullCmd 'EBX'  GOTO_REL16  DS_Stack32 <R_EBX>
        FullCmd 'ECX'  GOTO_REL16  DS_Stack32 <R_ECX>
        FullCmd 'EDX'  GOTO_REL16  DS_Stack32 <R_EDX>
        FullCmd 'ESI'  GOTO_REL16  DS_Stack32 <R_ESI>
        FullCmd 'EDI'  GOTO_REL16  DS_Stack32 <R_EDI>
        FullCmd 'EBP'  GOTO_REL16  SS_Stack32 <R_EBP>
        FullCmd 'ESP'  GOTO_REL16  SS_Stack32 <R_ESP>
        FullCmd 'EIP'  GOTO_REL16  CS_Stack32 <R_EIP>
        FullCmd 'AX'   GOTO_REL16  XX_Stack16 <R_EAX>
        FullCmd 'BX'   GOTO_REL16  DS_Stack16 <R_EBX>
        FullCmd 'CX'   GOTO_REL16  XX_Stack16 <R_ECX>
        FullCmd 'DX'   GOTO_REL16  XX_Stack16 <R_EDX>
        FullCmd 'SI'   GOTO_REL16  DS_Stack16 <R_ESI>
        FullCmd 'DI'   GOTO_REL16  DS_Stack16 <R_EDI>
        FullCmd 'BP'   GOTO_REL16  SS_Stack16 <R_EBP>
        FullCmd 'SP'   GOTO_REL16  SS_Stack16 <R_ESP>
        FullCmd 'IP'   GOTO_REL16  CS_Stack16 <R_EIP>
        FullCmd 'CS'   GOTO_REL16  LL_Stack16 <R_CS>
        FullCmd 'DS'   GOTO_REL16  LL_Stack16 <R_DS>
        FullCmd 'ES'   GOTO_REL16  LL_Stack16 <R_ES>
        FullCmd 'FS'   GOTO_REL16  LL_Stack16 <R_FS>
        FullCmd 'GS'   GOTO_REL16  LL_Stack16 <R_GS>
        FullCmd 'SS'   GOTO_REL16  LL_Stack16 <R_SS>
        FullCmd 'AL'   GOTO_REL16  XX_Stack08 <R_EAX>
        FullCmd 'AH'   GOTO_REL16  XX_Stack08 <R_EAX+1>
        FullCmd 'BL'   GOTO_REL16  XX_Stack08 <R_EBX>
        FullCmd 'BH'   GOTO_REL16  XX_Stack08 <R_EBX+1>
        FullCmd 'CL'   GOTO_REL16  XX_Stack08 <R_ECX>
        FullCmd 'CH'   GOTO_REL16  XX_Stack08 <R_ECX+1>
        FullCmd 'DL'   GOTO_REL16  XX_Stack08 <R_EDX>
        FullCmd 'DH'   GOTO_REL16  XX_Stack08 <R_EDX+1>
        db 0
        ret

Ind_Data32:
        add     eax, OFFSET32 Code_Data_Ptrs
        mov     edx, [eax+4]            ;default segment is next dword
        mov     ebx, [eax]              ;value to return
        mov     cl, 3                   ;32-bit value
;       clc
        ret

Ind_Data16:
        add     eax, OFFSET32 Code_Data_Ptrs
        movzx   ebx, word ptr [eax]     ;use default segment
        mov     cl, 2                   ;16-bit value
;       clc
        ret

Dos_Data32:
        add     eax, OFFSET32 DosInfo
        mov     ebx, [eax]              ;use default segment
        mov     cl, 3                   ;32-bit value
;       clc
        ret

CS_Stack32:
        mov     edx, [ebp].R_CS         ;default segment
        jmp     short XX_Stack32
SS_Stack32:
        mov     edx, [ebp].R_SS         ;default segment
        jmp     short XX_Stack32
DS_Stack32:
        mov     edx, [ebp].R_DS         ;default segment
XX_Stack32:
        add     eax, ebp                ;ptr memory
        mov     ebx, [eax]
        mov     cl, 3                   ;32-bit value
;       clc
        ret

LL_Stack16:
        mov     edx, [ebp+eax]          ;default segment
        jmp     short XX_Stack16
CS_Stack16:
        mov     edx, [ebp].R_CS         ;default segment
        jmp     short XX_Stack16
SS_Stack16:
        mov     edx, [ebp].R_SS         ;default segment
        jmp     short XX_Stack16
DS_Stack16:
        mov     edx, [ebp].R_DS         ;default segment
XX_Stack16:
        add     eax, ebp                ;ptr memory
        movzx   ebx, word ptr [eax]
        mov     cl, 2
;       clc
        ret

XX_Stack08:
        add     eax, ebp                ;ptr memory
        movzx   ebx, byte ptr [eax]
        mov     cl, 1
;       clc
        ret

; ---------------------------------------------------------------------------
PUBPROC flag_registers
        call    Parse_Line
        FullCmd 'CF', GOTO_REL16, flag_found, 0
        FullCmd 'PF', GOTO_REL16, flag_found, 2
        FullCmd 'AF', GOTO_REL16, flag_found, 4
        FullCmd 'ZF', GOTO_REL16, flag_found, 6
        FullCmd 'SF', GOTO_REL16, flag_found, 7
        FullCmd 'TF', GOTO_REL16, flag_found, 8
        FullCmd 'IF', GOTO_REL16, flag_found, 9
        FullCmd 'DF', GOTO_REL16, flag_found, 10
        FullCmd 'OF', GOTO_REL16, flag_found, 11
        FullCmd 'NT', GOTO_REL16, flag_found, 14
        FullCmd 'RF', GOTO_REL16, flag_found, 16
        FullCmd 'VM', GOTO_REL16, flag_found, 17
        FullCmd 'AC', GOTO_REL16, flag_found, 18
        db      0
flag_found:
        ret

; In:   AX=selector
; Out:  CF=0    EAX=Base, EDX=limit, ESI=address of descriptor
;       CF=1    Selector not available
PUBPROC Get_Selector
        movzx   eax, ax
        lar     edx, eax
        jnz     short get_selNone
        test    dh, dh                  ;present?
        jns     short get_selNone
        lsl     edx, eax
        jnz     short get_selNone

PUBPROC Get_SelectorBase
        test    al, 4                   ;0=GDT, 1=LDT
        jz      short get_GdtSelBase

PUBPROC get_LdtSelBase
        push    eax
        sldt    ax
        call    get_GdtSelBase
        xchg    esi, eax
        pop     eax
        jnc     short get_SelBase1
get_selNone:
        stc
        ret

PUBPROC get_GdtSelBase
        push    esi
        sgdt    fword ptr [esp-2]
        pop     esi                     ; esi = GDT_Base
get_SelBase1:
        and     eax, 0000fff8h
        add     esi, eax
        push    edx
        call    qword_read_@esi
        jc      short @f
        ; eax = base_0_15 : limit_0_15
        ; edx = base_24_31 : Granularity : AccessRights : Base_16_23
        shrd    eax, edx, 8
        rol     edx, 8
        shrd    eax, edx, 8
        clc
@@:     pop     edx
        ret

; ---------------------------------------------------------------------------
PUBPROC Convert_Decimal
        mov     ecx, 10
dispNumbr1:
        cmp     eax, ecx
        jb      short dispNumbr2
        xor     edx, edx
        div     ecx
        push    edx
        call    dispNumbr1
        pop     eax
dispNumbr2:
        or      al, '0'
        stosb
        ret

; ---------------------------------------------------------------------------
; In:   EAX = segment/selector
; Out:  AL = def_segsize
PUBPROC Get_Def_SegSize
        test    eax, eax
        js      short v86_segsize
PUBPROC Get_Def_SelSize
        lar     ecx, eax
        call    Get_Selector
        xchg    eax, ecx                ; access rights
        shr     eax, 16+6               ; b1,0=DEFSEG_ADR32 + DEFSEG_OPR32
        test    ecx, ecx
        jnz     short @f
        or      al, DEFSEG_ZBASE
@@:     mov     def_segsize, al
        ret

v86_segsize:
        mov     al, DEFSEG_V86
        mov     def_segsize, al
        ret

; ---------------------------------------------------------------------------
; Logging support
; ---------------------------------------------------------------------------
PUBPROC Log_FindLine
        DBGBRK  3
        mov     esi, LogBuffer_Beg
logFindNxt:
        movzx   ecx, byte ptr [esi]     ; length of lstring
        inc     esi
        dec     edx
        jz      short logFindRet
        add     esi, ecx
        cmp     esi, LogBuffer_Ptr
        jbe     short logFindNxt
        xor     ecx, ecx
logFindRet:
        ret

; ---------------------------------------------------------------------------
PUBPROC Log_Event
        DBGBRK  3
        pop     edx

        test    SP_flags, SP_ACTIVE
        jnz     short @f

        test    DosInfo.ScreenType, SCR_ALWAYS  ; is it always ON?
        jz      short Log_NoDisplay
@@:
        DBGBRK  4
        test    ScreenFlags, SF_VLOG
        jnz     short Log_DispNext

        call    Win_Printf
        db      d_sub,d_el
        mov     ScreenFlags, SF_VLOG
        jmp     short Log_Update

Log_DispNext:
        call    Printf
        db      d_sub,d_el
        jmp     short Log_Update

Log_NoDisplay:
        call    Printf
        db      d_sub,d_ret

Log_Update:
        DBGBRK  4
        test    Log_Falgs, LF_LOGCMD OR LF_LOGON
        jz      short logFindRet

        mov     esi, OFFSET32 Display_Buffer
PUBPROC Log_AppendToLog
        mov     edx, LogBuffer_Ptr      ; last lstring
Log_LinePos:
        movzx   edi, byte ptr [edx]     ; length of lstring
        inc     edi
        add     edi, edx
Log_Next:
@@s_clreol:
        lodsb
        cmp     al, 0fh
        jae     short Log_PutNext
        and     eax, 0fh
        jmp     dsp_cmdTable[eax*4]

PUBPROC Log_DisplayBuffer
        test    Log_Falgs, LF_LOGCMD OR LF_PRINT
        jz      short Log_Done
        mov     esi, OFFSET32 Display_Buffer
        if      LF_PRINT - 80h
        .err
        endif
        js      PrintLine
        DBGBRK  3
        mov     edx, LogBuffer_Ptr      ; last lstring
        movzx   ecx, byte ptr [edx]     ; length of lstring
        jecxz   short Log_LinePos
        inc     edx
        add     edx, ecx
        mov     [edx], ch
        jmp     short Log_LinePos

@@s_window:
@@s_row:inc     esi
@@s_wtop:
@@s_lf: lea     eax, [edi-1]
        DBGBRK  3
        sub     eax, edx                ; length of string
        and     eax, 7fh                ; max 127 chars
        mov     [edx], al
        inc     edx
        add     edx, eax
        mov     [edx], ah               ; len(new line)=0
        lea     edi, [edx+1]
        jmp     short Log_Next

@@s_dup:stosb
        lodsb
@@s_chr:
@@s_col:
@@s_spc:stosb
        lodsb
Log_PutNext:
@@s_norm:
@@s_bold:
@@s_rvrs:
@@s_fram:
@@s_tab:
        stosb
Log_Move:
        lea     ecx, [edi+4]
        cmp     ecx, LogBuffer_End
        jb      short Log_Next
        DBGBRK  4
        mov     ecx, edi                ; end of the log
        mov     edi, LogBuffer_Beg
        push    esi
        movzx   esi, byte ptr [edi]
        inc     esi                     ; length of message
        sub     edx, esi
        add     esi, edi                ; beg of line 2
        sub     ecx, esi
        rep     movsb
        pop     esi
        jmp     short Log_Move

@@s_el: mov     LogBuffer_Ptr, edx
        lea     eax, [edi-1]
        sub     eax, edx                ; length of string
        mov     [edx], al
        mov     byte ptr [edi], 0
Log_Done:
        ret

; ---------------------------------------------------------------------------
PUBPROC Cmd_LogOff
        and     Log_Falgs, not LF_LOGON
        ret

PUBPROC Cmd_LogOn
        or      Log_Falgs, LF_LOGON
        ret

PUBPROC Cmd_LogClear
        mov     eax, LogBuffer_Beg
        mov     LogBuffer_Ptr, eax
        mov     byte ptr [eax], 0
        ret

; ---------------------------------------------------------------------------
PUBPROC Display_Log
        DBGBRK  3
        call    Win_Printf
        db      d_el
        xor     edx, edx
        call    Log_FindLine
        ; esi=ptr end of log
        ; ecx=length of last line
        neg     edx
        mov     cl, Window_Line[_CMDLINE_]
        sub     edx, ecx                ;lines per screen
        jae     short @f
        xor     edx, edx
@@:     inc     edx
        push    ecx
        push    edx
        DBGBRK  3
        call    Log_FindLine
        mov     edi, OFFSET32 Display_Buffer
        mov     al, s_lf
        stosb
        rep     movsb
        call    Display_Line
        pop     edx
        pop     ecx
        loop    short @b
        mov     ScreenFlags, SF_VLOG
        pop     ebx                     ;prompt
        call    Printf
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,d_text,t_fill+80,d_el
        jmp     ebx

PUBPROC Cmd_VuLog
        xor     edx, edx
        call    Log_FindLine
        ; esi=ptr end of log
        ; ecx=length of last line
        neg     edx
        push    edx                     ;sl_limit
        sub     edx, 22                 ;lines per screen
        jae     short @f
        xor     edx, edx
@@:     push    edx                     ;sl_index
        mov     ecx, LogBuffer_Beg
        sub     esi, ecx                ;used bytes
        shr     esi, 10                 ;bytes to KB
        push    esi
        mov     eax, LogBuffer_End
        sub     eax, ecx
        shr     eax, 10                 ;bytes to KB
        push    eax
        call    scrollLinesNoLog        ;cannot log while viewing
        db      ' LOG SIZE: ',d_deci,'KB,  USED: ',d_deci,'KB',d_sub
        ; will be called by scrollLines
        ; edi = OFFSET32 Display_Buffer
        ; esi = context
        ; edx = ecx = index
        inc     edx
        call    Log_FindLine
        ; esi=ptr beg of log line
        ; ecx=length of line
        DBGBRK  3
        rep     movsb
        ret

fpu_state_struc struc
 fpu_CtrlWord   dw ? ; 00
                dw ? ; 02 reserved
 fpu_StatWord   dw ? ; 04
                dw ? ; 06 reserved
 fpu_TagWord    dw ? ; 08
                dw ? ; 0a reserved
 fpu_EIP        dd ? ; 0c
 fpu_CS         dw ? ; 10
 fpu_Opcode     dw ? ; 12 Opcode bits 10..00
 fpu_OprOff     dd ? ; 14 Data operand offset
 fpu_OprSel     dw ? ; 18 Data operand selector
                dw ? ; 1a reserved
 fpu_STi        dw 5*8 dup( ? ) ; 1c
fpu_state_struc ends

PUBPROC Cmd_Sys
        mov     edx, CR0
        push    edx
        mov     eax, DR0
        push    eax

        str     bx
        push    ebx
        push    eax
        push    esi
        sidt    fword ptr [esp+2]
        pop     esi
        pop     eax
        shr     esi, 16
        push    esi                     ;idtLimit
        push    eax                     ;idtBase

        sldt    ax
        push    eax
        push    eax
        push    esi
        sgdt    fword ptr [esp+2]
        pop     esi
        pop     eax
        shr     esi, 16
        push    esi                     ;gdtLimit
        push    eax                     ;gdtBase
        call    Win_Printf
        db           'GDT:BASE=',d_h32,'  LIMIT=',d_h16,d_spc,3,'LDT=',d_h16
        db      d_lf,'IDT:BASE=',d_h32,'  LIMIT=',d_h16,d_spc,3,'TSS=',d_h16
        db      d_lf
        db      d_lf,'DR0=',d_h32,'  CR0=',d_h32,d_el
        call    sys_cpuid
        jc      short @f
        xchg    eax, ebx
        mov     ebx, OFFSET32 Display_Buffer+160
        mov     [ebx+0], eax
        mov     [ebx+4], edx
        mov     [ebx+8], ecx
        call    Printf
        db      '  CPU=',d_text,12,d_el
        call    sys_cpuid_info
        jc      short @f
        push    edx
        push    eax
        call    Printf
        db      '(',d_h32,',',d_h32,')',d_el
@@:
        mov     eax, DR1
        push    eax
        call    Printf
        db      d_lf,'DR1=',d_h32,'  CR2=',d_r32,R_CR2,d_el
        test    DosInfo.SetupFlags, SET_TIMER
        jz      short @f
        call    ReadTimeStamp
        push    eax
        push    edx
        call    Printf
        db      '  TSC=',d_h32,d_h32,d_el
@@:
        mov     eax, CR3
        push    eax
        mov     eax, DR2
        push    eax
        call    Printf
        db      d_lf,'DR2=',d_h32,'  CR3=',d_h32,d_el
        DBGBRK  3
        stc                             ; PMC[0]
        call    sys_rdpmc
        jc      short @f
        push    eax
        push    edx
        call    Printf
        db      '  PMC[0]=',d_h32,d_h32,d_el
@@:
        mov     eax, DR3
        push    eax
        call    Printf
        db      d_lf,'DR3=',d_h32,d_el
        call    sys_cr4
        jc      short @f
        push    eax
        call    Printf
        db      '  CR4=',d_h32,d_el
@@:     clc                             ; PMC[1]
        call    sys_rdpmc
        jc      short @f
        push    eax
        push    edx
        call    Printf
        db      '  PMC[1]=',d_h32,d_h32,d_el
@@:     mov     eax, DR7
        push    eax
        mov     eax, DR6
        push    eax
        call    Printf
        db      d_lf,'DR6=',d_h32
        db      d_lf,'DR7=',d_h32
        db      d_el

        DBGBRK  3
        mov     eax, CR0
 ;      test    al, 2                   ; MP (Math Present)?
  ;     jz      short @f
        test    DosInfo.SetupFlags, SET_NOFPU
        jz      short Display_FPU_State
;@@:
        ret

tag_word        db 7
                db '       '
                db 'ZERO   '
                db 'SPECIAL'
                db 'EMPTY  '

Display_FPU_State:
        push    eax                     ; save CR0
        and     al, not 001100b         ; TS (task switch) and EM flags off
        mov     CR0, eax
        mov     ebx, OFFSET32 Display_Buffer+160
        fnsave  [ebx]
        fwait                           ; wait for fsave done

        call    Printf
        db      d_lf
        db      d_lf,a_b,'FPU',d_el

        ; Now display MMX registers
        DBGBRK  3
        mov     edi, OFFSET32 Display_Buffer+512-64 ; do not overwrite FPU
        call    mmx_registers
        setc    byte ptr [edi-1]
        jc      short @f
        call    Printf
        db      d_col,45,a_b,'MMX',d_el
@@:
        mov     cl, 00111000b
        and     cl, byte ptr [ebx].fpu_StatWord[1] ; [bcsssccc]
        shr     cl, 2
        ror     dx, cl                  ; put TOS on bits 0,1

        xor     ecx, ecx
disp_STi:
        DBGBRK  3
        push    ecx
        imul    eax, ecx, 10            ; 10 bytes per ST
        lea     esi, [ebx+eax].fpu_STi
        mov     al, dl                  ; tag word
        and     eax, 3
        push    eax                     ; _table
        movzx   edi, word ptr [esi+8]   ; Sign + Exponent
        btr     edi, 15                 ; Sign bit
        mov     ah, '+'
        jnc     short @f
        mov     ah, '-'
@@:     sub     edi, 3fffh              ; normalized exponent
        mov     al, '+'
        jns     short @f
        mov     al, '-'
        neg     edi
@@:     push    edi                     ; exponent
        push    eax                     ; sign of exponent
        xchg    al, ah
        xchg    edi, eax
        lodsd                           ; bits 00..31 of mantisa
        mov     esi, [esi]              ; bits 32..63 of mantisa
        ; b63.b62....b0
        add     eax, eax
        adc     esi, esi
        push    eax
        push    esi
        sbb     eax, eax                ; 1. or 0.
        neg     eax
        push    eax
        push    edi                     ; The sign (+/-)
        push    ecx
        call    Printf
        db      d_lf,'ST(',d_deci,')=',d_chr,d_deci,'.',d_h32,d_h32
        db      ' E',d_chr,d_h16,'  '
        _table  tag_word
        db      d_el
        DBGBRK  3

        pop     ecx
        mov     edi, OFFSET32 Display_Buffer+512-64
        cmp     [edi-1],ch              ; 1 if MMX capable
        jne     short @f
        push    ecx
        lea     esi, [edi+8*ecx]
        lodsd
        push    eax
        push    dword ptr [esi]
        push    ecx
        call    Printf
        db      d_col,45,'MM',d_h04,'=',d_h32,d_h32,d_el
        pop     ecx

@@:     inc     ecx
        shr     edx, 2                  ; next tag
        cmp     ecx, 8
        jb      disp_STi

        DBGBRK  3
        mov     edx, dword ptr [ebx].fpu_TagWord  ; dw 08
        push    edx
        push    dword ptr [ebx].fpu_CtrlWord ; dw 00
        push    dword ptr [ebx].fpu_StatWord ; dw 04

        push    dword ptr [ebx].fpu_OprOff   ; dd 14 Data operand offset
        movzx   eax, [ebx].fpu_OprSel        ; dw 18 Data operand selector
        push    eax
        movzx   eax, [ebx].fpu_Opcode        ; dw 12 Opcode bits 10..00
        and     ah, 7                        ; mask out unused bits
        or      ah, 0D8h                     ; set implicit bits
        push    eax
        push    dword ptr [ebx].fpu_EIP      ; dd 0c
        movzx   eax, [ebx].fpu_CS            ; dw 10
        push    eax
        call    Printf
        db      d_lf
        db      d_lf,' CS:EIP=',d_h48,'  Opcode=',d_h16
        db      d_lf,'Operand=',d_h48
        db      d_lf,' Status=',d_h16,'  Control=',d_h16,'  Tag=',d_h16,d_el

        frstor  [ebx]
        pop     edx
        mov     CR0, edx                ; restore CR0
        ret

PUBPROC Cmd_MSR
        DBGBRK  3
        push    10000h                  ;sl_limit
        movsx   ebx, bx
        add     ebx, 8000h
        push    ebx                     ;sl_Index
        call    scrollLines
        db      'Register  Contents',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        sub     ecx, 8000h
        call    ReadMSR
        jc      short @f
        push    eax
        push    edx
        push    ecx
        call    Printf
        db      '  ',d_h16,d_spc,4,d_h32,d_h32
        db      d_ret
        ret
@@:     push    ecx
        call    Printf
        db      '  ',d_h16,d_spc,4,d_dup,16,'*'
        db      d_ret
        ret

PUBPROC Cmd_Hex
        DBGBRK  3
        call    Scan_Dword
        push    ebx
        cmp     al, 0
        je      short @f
        call    Scan_Dword
@@:     pop     edi

        mov     eax, edi
        mul     ebx
        push    eax     ;A*B (lo)
        push    edx     ;A*B (hi)
        mov     eax, edi
        or      eax, ebx
        push    eax     ;A|B

        mov     eax, edi
        xor     edx, edx
        test    ebx, ebx
        jz      short hex_cal1
        div     ebx
hex_cal1:       
        push    edx     ;A%B
        mov     ecx, edi
        sub     ecx, ebx
        push    ecx     ;A-B

        mov     ecx, edi
        xor     ecx, ebx
        push    ecx     ;A^B
        mov     ecx, edi
        and     ecx, ebx
        push    ecx     ;A&B
        push    eax     ;A/B
        lea     ecx, [ebx+edi]
        push    ecx     ;A+B

        mov     eax, ebx
        neg     eax
        push    eax     ;-B
        mov     eax, ebx
        not     eax
        push    eax     ;~B
        push    ebx     ;B
        push    ebx     ;B

        mov     eax, edi
        neg     eax
        push    eax     ;-A
        mov     eax, edi
        not     eax
        push    eax     ;~A
        push    edi     ;A
        push    edi     ;A
        call    PrintfMainScr
        db d_lf,'  A=',d_h32,'  A=.',d_deci,d_col,29,'~A=',d_h32
        db '   -A=',d_h32
        db d_lf,'  B=',d_h32,'  B=.',d_deci,d_col,29,'~B=',d_h32
        db '   -B=',d_h32
        db d_lf,'A+B=',d_h32,'  A/B=',d_h32
        db '  A&B=',d_h32,'  A^B=',d_h32
        db d_lf,'A-B=',d_h32,'  A%B=',d_h32
        db '  A|B=',d_h32,'  A*B=',d_h32,d_h32
        db d_el
        ret

PUBPROC Cmd_ASC
        movzx   eax, bl
        cmp     eax, ebx
        je      short @f
        xor     eax, eax
@@:     push    64                      ;sl_limit
        and     al, 3fh
        push    eax                     ;sl_Index
        call    scrollLines
        db      'HEX  DEC  CHR',d_col,20
        db      'HEX  DEC  CHR',d_col,40
        db      'HEX  DEC  CHR',d_col,60
        db      'HEX  DEC  CHR',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        xchg    eax, ecx
        add     al, 0c0h
        push    eax
        push    eax
        push    eax

        sub     al, 40h
        push    eax
        push    eax
        push    eax

        sub     al, 40h
        push    eax
        push    eax
        push    eax

        push    edx
        push    edx
        push    edx
        call    Printf
        db           ' ',d_h08,'  ',d_numb,NM_RJZRO+3,d_col,11,d_chr
        db      d_col,21,d_h08,'  ',d_numb,NM_RJZRO+3,d_col,31,d_chr
        db      d_col,41,d_h08,'  ',d_numb,NM_RJZRO+3,d_col,51,d_chr
        db      d_col,61,d_h08,'  ',d_numb,NM_RJZRO+3,d_col,71,d_chr
        db      d_ret
        ret

LCODE_ENDS
END

