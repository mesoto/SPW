        name    SPWIN

        INCLUDE INT2FAPI.INC
        INCLUDE DEBUGSYS.INC            ; From Win95 DDK
        _16BIT_ EQU 1
        INCLUDE SP_DEFS.INC
        INCLUDE SP_COMM.INC

.8086
_TEXT   segment word public 'CODE'
        assume  cs:_TEXT
        assume  ds:_TEXT
        assume  es:_TEXT

code_start:
; ---------------------------------------------------------------------------
; This offset is assumed to be 0000h by SP_INIT.
; ---------------------------------------------------------------------------
VxD_Info_Beg    db 256*(SIZE VXD_INFO_STRU) dup( 0 )
VxD_Info_End    label byte

; ---------------------------------------------------------------------------
Exec_Params     dw 0     ; use parent environment
                dw 80h,0 ; use incomming command line
                dw 5ch,0 ; FCB1
                dw 6ch,0 ; FCB2

WinPath         db 80 dup(0)

IF DBG
  IFDEF _W95_
;dbgWinPath      db  'd:\make\spw\spw95.EXE',0
dbgWinPath      db  'c:\winice\win95\WINICE.EXE',0
  ELSE
;dbgWinPath      db  'd:\make\spw\spw31.EXE',0
dbgWinPath      db  'c:\winice\WINICE.EXE',0
  ENDIF
ENDIF
                align 4
                db  256 dup (0) ; stack area
stack_bot       equ this word

; ---------------------------------------------------------------------------
; This entry is called in protected mode and should stay at non-zero offset!
; ---------------------------------------------------------------------------
        db      0eah                    ; align only
D386_PM_callback:                       ; **** Executed with a 32-bit CS ****
        db      9ah                     ; call ssss:oooooooo
spw_Seg1_Start  dd 0
                dw VXD_CODESELECTOR
IF      DBG
prevPM_Callback df 0
ENDIF
VxD_Info_Seg    dw ?
VxD_Info_Ptr    dw offset VxD_Info_Beg
v86_terminate   dw offset int21_call
xms_address     dd 0
xms_size        dw 64           ; KB's

; ---------------------------------------------------------------------------
        even
InstData Win386_Startup_Info_Struc <>

int21_call:
        int     21h
        iret

.386p

; ---------------------------------------------------------------------------
handle2f proc
IF      DBG
        cmp     word ptr cs:Prev_D386_RM[2], 0
        jne     short hndl2f_2
;;      int     60h
        push    ax
        push    ds
        xor     ax, ax
        mov     ds, ax
        mov     ax, word ptr ds:[4*68h+2]
        cmp     ax, 0f000h
        je      short hndl2f_1
        mov     word ptr cs:Prev_D386_RM[2], ax
        mov     ax, word ptr ds:[4*68h+0]
        mov     word ptr cs:Prev_D386_RM[0], ax
        mov     word ptr ds:[4*68h+0], offset D386_RM_hook
        mov     word ptr ds:[4*68h+2], cs
hndl2f_1:
        pop     ds
        pop     ax
hndl2f_2:
ENDIF
        cmp     ax, 1605h
        jnz     short @f
        mov     word ptr cs:InstData.SIS_Next_Ptr[0], bx
        mov     word ptr cs:InstData.SIS_Next_Ptr[2], es
        push    cs
        pop     es
        mov     bx, offset InstData
@@:     db      0eah                    ; jmp   DWORD PTR [oldint]
oldi2f  dd      0
handle2f endp

; ---------------------------------------------------------------------------
; defines the actual segment/selector for a loaded segment to allow for
; symbol processing
; INPUT:
;    ES:DI points to D386_Device_Params struc
;
; RETURN:
;    AL = 1, if successful, else 0

D386_RM_Load_Segment:
        pushad
        mov     si, cs:VxD_Info_Ptr
        cmp     si, offset VxD_Info_End
        jae     short RMLS_Done
        push    ds
        push    es
        push    es
        pop     ds
        push    cs
        pop     es
        cld
        xchg    si, di
        mov     ax, [si].DD_logical_seg
        stosw                   ; vi_SegNumber
        mov     eax, [si].DD_base
        stosd                   ; vi_Start
        add     eax, [si].DD_length
        stosd                   ; vi_End
        lds     esi, [si].DD_name
        movsd                   ; vi_name
        movsd
        mov     cs:VxD_Info_Ptr, di

IF DBG
  IFDEF _W95_
        cmp     dword ptr ds:[si-8][0], '9WPS'  ; SPW95D?
        jne     short @f
        cmp     dword ptr ds:[si-8][3], 'D59'   ; SPW95D?
  ELSE
        cmp     dword ptr ds:[si-8][0], '3WPS'  ; SPW31D?
        jne     short @f
        cmp     dword ptr ds:[si-8][3], 'D13'   ; SPW31D?
  ENDIF
ELSE
  IFDEF _W95_
        cmp     dword ptr ds:[si-8][0], '9WPS'  ; SPW95?
        jne     short @f
        cmp     dword ptr ds:[si-8][2], '59W'   ; SPW95?
  ELSE
        cmp     dword ptr ds:[si-8][0], '3WPS'  ; SPW31?
        jne     short @f
        cmp     dword ptr ds:[si-8][2], '13W'   ; SPW31?
  ENDIF
ENDIF
        jne     short @f
        cmp     es:[di - SIZE VXD_INFO_STRU].vi_SegNumber, 1
        jne     short @f
        mov     eax, es:[di - SIZE VXD_INFO_STRU].vi_Start
        mov     dword ptr cs:[spw_Seg1_Start], eax
@@:     pop     es
        pop     ds
RMLS_Done:
        popad
IFE     DBG
        mov     al, 1
        iret
ELSE
        jmp     dword ptr cs:Prev_D386_RM
ENDIF

; ---------------------------------------------------------------------------
D386_RM_hook    proc
        cmp     ax, D386_Load_Segment*100h + ST_device_data
        je      D386_RM_Load_Segment
        cmp     ah, D386_Prepare_PMode
        je      short PM_Prepare
IFE     DBG
        cmp     ah, D386_Identify
        jne     short D386_RM_Ret

; ---------------------------------------------------------------------------
; Kernel level debug present?
; In:   AH=43
; Out:  AX=0F386
        mov     ax, D386_Id             ; signature
D386_RM_Ret:
        iret
ELSE
        db      0eah                    ; jmp to the debugger
ENDIF
Prev_D386_RM    dd 0

D386_RM_hook    endp

; ---------------------------------------------------------------------------
; In:   AH=44
;       AL=0 - retail version of Win386
;          1 - debugging version
;       BX  a valid selector that gives access to all of memory
;       CX  first of 2 selectors reserved for WDeb386 to use
;       DX  is GDT selector
;       DS:SI pointer to working copy of GDT
;       ES:DI pointer to working copy of IDT
;
; Out:
;       ES:EDI points to a protected mode procedure (selector:offset32) that
;       can be called to set the IDT when it has been created.
;       Takes a function number in AL. See the PMINIT equates.

PM_Prepare:
IF      DBG
        push    ds
        pusha
        pushf
        call    dword ptr cs:Prev_D386_RM
        mov     dword ptr cs:prevPM_Callback[0], edi
        mov     word ptr cs:prevPM_Callback[4], es
        popa
        pop     ds

ENDIF
        ; Set two descriptors at DS:SI+CX
        push    VXD_CODESELECTOR
        pop     es
        mov     edi, offset D386_PM_callback
callBack_Offset equ $-4
        iret

; ---------------------------------------------------------------------------
winExec:mov     ah, 4ah                 ; shrink memory
        int     21h

        push    cs
        pop     es
        mov     bx, offset Exec_Params
IF DBG
        mov     dx, offset dbgWinPath
ELSE
        mov     dx, offset WinPath
ENDIF
        mov     ax, 4b00h
        int     21h
        mov     ax, cs
        mov     ss, ax
        mov     sp, offset stack_bot
        lds     dx, dword ptr cs:oldi2f ; old vector
        mov     ax, 252fh               ; restore vector
        int     21h
IFE DBG
        lds     dx, dword ptr cs:Prev_D386_RM ; old vector
        mov     ax, 2500h + D386_RM_Int ; restore vector
        int     21h
ENDIF
        mov     ah,0dh                  ;UnLock Extended memory
        call    xms_handle
        mov     ah, 0ah                 ;Free Extended memory
        call    xms_handle

        mov     ax, 4c00h
        int     21h                     ; will be changed to NOP's if learn

; ---------------------------------------------------------------------------
xms_handle:     mov dx, 64              ;initial value=KB of LOG memory
xms_call:       db  09ah                ;call far ptr xms_handler
xms_entry       dd  0
                ret

end_of_resident_code:

        even
mem_needed      equ ($-code_start+100h+15)/16
; ---------------------------------------------------------------------------

xms_symBuff_beg dd 0
xms_symBuff_end dd 0
PathPtr         dw offset zero,0
PathStr         db 'PATH='
zero            db 0

; ---------------------------------------------------------------------------
.8086

disp_msg:
        push    cs
        pop     ds
        mov     dx, si
        cld
@@:     lodsb
        cmp     al, 0
        jne     @b
        lea     cx, [si-1]
        sub     cx, dx
        mov     ah, 40h
        mov     bx, 1                   ;stdout
        int     21h
        ret

message:pop     si
        call    disp_msg
        jmp     si

msg_quit:
        pop     si
        call    disp_msg
        lodsb
        mov     ah, 4ch
        int     21h

SPWIN:  mov     ax, cs
        mov     ss, ax
        mov     sp, offset stack_bot
        DBGBRK  2, 60H
        push    es                      ;PSP

        call    message
        db      'SoftProbe/W Release ',VER_STR,13,10
        db      'Copyright (C) Mehdi Sotoodeh 1995.  '
        db      'All rights reserved.',13,10,0

        call    get_Dos_Info
        call    Is_Window_Running
        call    Is_386Cpu
.386p
        call    Is_Xms_Loaded
        pop     ax                      ; PSP

        mov     Exec_Params[04], ax
        mov     Exec_Params[08], ax
        mov     Exec_Params[12], ax
        mov     word ptr PathPtr[2], cs ;no-path points to zero

        call    Get_Env_Data

        ; Locate WIN.COM file.
        call    Find_WinDir

        DBGBRK  4, 60H
        ; Process configuration file or default settings.
        call    Load_File
        db      'INI'                   ; d:\...\SPWIN.INI
        jcxz    short @f
        call    Cnv_File
@@:
        ; XMS memory is used by:
        ;       Log buffer
        ;       Capture
        ;       Symbolic info

        movzx   eax, word ptr xms_size  ;Kbytes of memory for logging
        add     ax, word ptr DosInfo.capBufSize
        mov     dx, ax
        shl     eax, 10                 ;KB to bytes
        mov     xms_symBuff_beg, eax
        add     dx, word ptr DosInfo.symBufSize
        movzx   eax, dx
        shl     eax, 10                 ;KB to bytes
        mov     xms_symBuff_end, eax

        mov     word ptr xms_size, dx   ;Kbytes of memory to allocate
        mov     ah, 9                   ;Allocate Extended memory
        call    xms_call                ;dx=Kbytes of memory to allocate
        dec     ax                      ;successful ?
        jnz     short himem_err1

        mov     word ptr xms_MoveBlk[10], dx ; destination handle for move
        mov     word ptr ds:[xms_handle+1], dx
        DBGBRK  2, 60H
        mov     ah, 0ch                 ;Lock Extended memory (DX=handle)
        call    xms_call
        dec     ax                      ;successful ?
        jz      short himem_ok

himem_err2:
        mov     ah, 0ah                 ;Free Extended memory
        call    xms_handle
himem_err1:
        call    msg_quit
        db      13,10,'Error allocating XMS memory.',0,6

; In:   dx:ax   seg:off for the source
;       cx      length in bytes
;       edi     destination offset
Copy_To_Xms:
        push    cs
        pop     ds
        mov     si, offset xms_MoveBlk
        inc     cx
        and     cl, not 1               ;length must be even
        mov     [si+0], cx              ;lo-word of length of block
        mov     [si+6], ax              ;source offset
        mov     [si+8], dx              ;source segment
        mov     dword ptr [si+12], edi  ;destination offset
        mov     ah, 0bh                 ;Move Extended memory block
        call    xms_call
        dec     ax                      ;successful ?
        jnz     short himem_err3
        ret

himem_err3:
        mov     ah,0dh                  ;UnLock Extended memory
        call    xms_handle
        jmp     himem_err2

himem_ok:
        ; dx:bx=linear address
        mov     word ptr xms_address[0], bx
        mov     word ptr xms_address[2], dx

        mov     ax, offset xms_Data_beg
        mov     dx, cs
        mov     cx, xms_Data_len
        xor     edi, edi                ; destination offset
        call    Copy_To_Xms

        DBGBRK  4, 60H
        mov     ax, sym_File_Ptr
        shr     ax, 4
        inc     ax
        mov     dx, cs
        add     ax, dx
        mov     word ptr Sym_Save_Seg, ax
        mov     bx, offset sym_File_List
symLoad1:
        DBGBRK  2, 60H
        push    cs
        pop     es
        cmp     bx, sym_File_Ptr
        jae     short symLoadDone
        mov     di, offset IO_Buffer
        cmp     byte ptr [bx+1], ':'
        je      short symLoad2
        mov     si, offset WinPath
        call    str_cat
        sub     di, 7                   ;remove 'WIN.COM'
        push    di
        push    bx
        mov     si, bx
        call    str_cat
        mov     dx, offset IO_Buffer
        mov     ax, 4300h
        int     21h
        pop     bx
        pop     di
        jnc     short symLoad3
        mov     si, offset system_dir
        call    str_cat
symLoad2:
        mov     si, bx
        call    str_cat
symLoad3:
        DBGBRK  4, 60H
        push    si
        call    Sym_Load
        pop     bx
        jmp     short symLoad1

system_dir      db 'SYSTEM\',0

symLoadDone:
        test    DosInfo.SetupFlags, SET_NOFPU
        jnz     short @f
        fninit                          ;initialize fpu
@@:     xor     eax, eax
        mov     ax, cs
        mov     VxD_Info_Seg, ax
        shl     eax, 4
        add     dword ptr ds:[callBack_Offset], eax
        mov     ax, 352fh
        int     21h                     ; get old vector
        mov     WORD PTR oldi2f, bx     ; save old vector here
        mov     WORD PTR oldi2f+2, es

        mov     dx, offset handle2f
        mov     ax, 252fh               ; vector to hook
        int     21h                     ; hook that vector

IFE DBG
        mov     ax, 3500h + D386_RM_Int
        int     21h                     ; get old vector
        mov     WORD PTR Prev_D386_RM, bx ; save old vector here
        mov     WORD PTR Prev_D386_RM+2, es

        mov     dx, offset D386_RM_hook
        mov     ax, 2500h + D386_RM_Int ; vector to hook
        int     21h                     ; hook that vector
ENDIF

        mov     es, word ptr Exec_Params[04] ;PSP
        mov     bx, mem_needed          ; # of paragraphs to reserve
        jmp     winexec

        even
xms_MoveBlk     dw xms_Data_len, 0      ; #bytes to move (even)
                dw 0                    ; source handle (0:next dd=seg:off)
                dw xms_Data_beg, ?      ; offset into src block
                dw ?                    ; destination handle
                dd 0                    ; offset into destination

; ---------------------------------------------------------------------------
ChkCmd  macro c, t, a
        local t1, t2
        db    t2
t1      db    c
t2      equ   ($-t1)+16*t
        dw    a
        endm

C_RETURN0 = 0
C_RETURN1 = 1
C_RETURN2 = 2
C_RETURN3 = 3
C_RETURN4 = 4
C_RETURN5 = 5
C_NOTHING = 6
C_PRVCHAR = 7
C_ENDLINE = 8
C_ISEQUAL = 9

        even
arg_table       dw offset return_0      ; C_RETURN0
                dw offset return_1      ; C_RETURN1
                dw offset return_2      ; C_RETURN2
                dw offset return_3      ; C_RETURN3
                dw offset return_4      ; C_RETURN4
                dw offset return_5      ; C_RETURN5
                dw offset just_ret      ; C_NOTHING
                dw offset prev_char     ; C_PRVCHAR
                dw offset line_skip     ; C_ENDLINE
                dw offset is_equal      ; C_ISEQUAL

return_0:
return_1:
return_2:
return_3:
return_4:
return_5:
        mov     ax, bx
        shr     ax, 1
just_ret:
        ret

line_skip:
        lodsb
        cmp     al, 0dh
        je      short line_ends
        cmp     al, 0ah
        je      short line_ends
        cmp     al, 1ah
        jne     short line_skip
line_ends:
        dec     si
        ret

blank_skip:
        lodsb
        cmp     al, 9
        je      short blank_skip
        cmp     al, ' '
        je      short blank_skip
prev_char:
        dec     si
        ret

is_equal:
        call    blank_skip
        inc     si
        cmp     al, '='
        je      just_ret

syntax_error:
        call    cfg_error
        db      13,10,'Syntax error "',0

cfg_error:
        pop     bx                      ; error msg
        push    si
        call    line_skip
        mov     byte ptr [si], 0

        mov     si, bx
        call    disp_msg

        pop     si
        std                             ; go reverse (line start)
        call    line_skip
        cld
        add     si, 3
        call    disp_msg
        call    msg_quit
        db      '".',0,1

; ---------------------------------------------------------------------------
decimal_val:
        call    blank_skip
        xor     ebx, ebx
        mov     ah, 1
get_val1:
        lodsb
        sub     al, '0'
        cmp     al, 10
        jae     get_val2
        and     eax, 0fh
        imul    ebx, 10
        add     ebx, eax
        jmp     short get_val1

get_val2:
        dec     si
        shr     ah, 1                   ; CF=1 if no digit found
        mov     ax, bx
        ret

; ---------------------------------------------------------------------------
str_cat:lodsb
        stosb
        cmp     al, 0
        jne     str_cat
        dec     di                      ;back on \0
        ret

; ---------------------------------------------------------------------------
DecodeLine:
        call    blank_skip
        pop     di
        jmp     short pl_search1
pl_search3:
        mov     bl, ah
        lea     di, [di+bx+2]
pl_search1:
        xor     bx, bx
        mov     ah, [di]        ;len + type*16
        inc     di
        and     ah, 15          ;len
        jz      short pl_not_found
pl_search2:
        mov     al, [si+bx]
        xor     al, [di+bx]
        jz      short pl_search4
        cmp     al, 20h
        jne     short pl_search3
        mov     al, [si+bx]
        sub     al, 'a'
        cmp     al, 'z'-'a'+1
        jae     short pl_search3
pl_search4:
        inc     bx
        cmp     bl, ah
        jb      short pl_search2
        add     si, bx
        push    word ptr [di+bx]
        xor     bl, [di-1]
        shr     bl, 3
        jmp     word ptr arg_table[bx]

pl_not_found:
        DBGBRK  4, 60H
        stc
        jmp     di

INIT_Ptr        dw offset IO_Buffer
IO_Buffer_End   dw offset IO_Buffer

; ---------------------------------------------------------------------------
Cnv_File:
        mov     si, offset IO_Buffer
        add     IO_Buffer_End, cx       ; end of buffer
        mov     bx, cx
        mov     byte ptr [si+bx], 1ah
Cfg_Decode:
        call    DecodeLine
        ChkCmd  '#'       C_ENDLINE  cfg_nxtLine
        ChkCmd  <0dh>     C_NOTHING  Cfg_Decode
        ChkCmd  <0ah>     C_NOTHING  Cfg_Decode
        ChkCmd  <1ah>     C_NOTHING  End_Decode
        ChkCmd  '[SETUP]' C_ENDLINE  SETUP_section
        ChkCmd  '[INIT]'  C_ENDLINE  INIT_section
        ChkCmd  '[SYM]'   C_ENDLINE  Symb_section
        ChkCmd  '[END]'   C_ENDLINE  End_Decode
        db 0

        call    cfg_error
        db      13,10,'Undefined section error "',0

cfg_nxtLine:
        call    NextLine
        jmp     Cfg_Decode

SETUP_nxtLine:
        call    NextLine
SETUP_section:
        call    DecodeLine
        ChkCmd  'LOG'       C_ISEQUAL  log_size     ; LOG=64  (KB)
        ChkCmd  'CAP'       C_ISEQUAL  cap_size     ; CAP=8   (KB)
        ChkCmd  'SYM'       C_ISEQUAL  sym_size     ; SYM=32  (KB)
        ChkCmd  'WRK'       C_ISEQUAL  wrk_size     ; CAP=8   (KB)
        ChkCmd  'MEM'       C_ISEQUAL  mem_size     ; MB of physical memory
        ChkCmd  'NOFPU'     C_ENDLINE  fpu_Off      ; No fpu check
        ChkCmd  'EARLYBRK'  C_ENDLINE  brk_Early    ; Break before init
        ChkCmd  '['         C_PRVCHAR  Cfg_Decode
        ChkCmd  '#'         C_ENDLINE  SETUP_nxtLine
        ChkCmd  <0dh>       C_NOTHING  SETUP_section
        ChkCmd  <0ah>       C_NOTHING  SETUP_section
        ChkCmd  <1ah>       C_NOTHING  End_Decode
        db 0

        jmp     syntax_error

log_size:
        call    decimal_val
        cmp     ax, 8
        jae     short @f
        mov     al, 8                   ; minimum 8K space needed
@@:     mov     word ptr ds:[xms_size], ax
        jmp     SETUP_section

cap_size:
        call    decimal_val
        cmp     ax, 1
        jae     short @f
        mov     al, 1                   ; minimum 1K space
@@:     mov     word ptr DosInfo.capBufSize, ax
        jmp     SETUP_section

wrk_size:
        call    decimal_val
        mov     word ptr DosInfo.wrkBufSize, ax
        jmp     SETUP_section

sym_size:
        call    decimal_val
        cmp     ax, 16
        jae     short @f
        mov     al, 16                  ; minimum 16K space
@@:     mov     word ptr DosInfo.symBufSize, ax
        jmp     SETUP_section

mem_size:
        call    decimal_val
        mov     word ptr DosInfo.PhyMemSize, ax
        jmp     SETUP_section

brk_Early:
        or      DosInfo.SetupFlags, SET_BRKEARLY
        jmp     SETUP_section

fpu_Off:or      DosInfo.SetupFlags, SET_NOFPU
        jmp     SETUP_section

get_PortAddress:
        push    ds
        xchg    bx, ax
        shl     bx, 1
        mov     ax, 40h
        mov     ds, ax
        mov     ax, ds:[bx]
        pop     ds
        test    ax, ax
        ret

INIT_nxtLine:
        call    NextLine
INIT_section:
        call    DecodeLine
        ChkCmd  '['       C_PRVCHAR  Cfg_Decode
        ChkCmd  '#'       C_ENDLINE  INIT_nxtLine
        ChkCmd  <0dh>     C_NOTHING  INIT_section
        ChkCmd  <0ah>     C_NOTHING  INIT_section
        ChkCmd  <1ah>     C_NOTHING  End_Decode
        db 0

        mov     di, INIT_Ptr
CnvFile1:
        lodsb
        cmp     al, 1ah                 ; EOF?
        je      short CnvFile4
        cmp     al, 0ah                 ; LF
        je      short CnvFile2
        cmp     al, 0dh                 ; CR?
        jne     short CnvFile3
CnvFile2:
        mov     al, K_CR
        stosb
        mov     INIT_Ptr, di
        jmp     INIT_section

CnvFile3:
        stosb
        cmp     si, IO_Buffer_End
        jb      short CnvFile1
        jmp     Cfg_Decode

CnvFile4:
        mov     INIT_Ptr, di
End_Decode:
        mov     al, 0
        mov     cx, offset IO_Buffer + 2000h
        mov     di, INIT_Ptr
        sub     cx, di
        jc      short ret_01
        rep     stosb
ret_01: ret

NextLine:
        lodsb
        cmp     al, 10                  ; ignore LF
        je      short ret_01
        cmp     al, 13                  ; CR?
        je      short ret_01
        cmp     al, 1ah                 ; EOF?
        jne     short NextLine
        pop     di                      ; remove ret address
        jmp     short End_Decode

Symb_nxtLine:
        call    NextLine
Symb_section:
        call    DecodeLine
        ChkCmd  '['       C_PRVCHAR  Cfg_Decode
        ChkCmd  '#'       C_ENDLINE  Symb_nxtLine
        ChkCmd  <0dh>     C_NOTHING  Symb_section
        ChkCmd  <0ah>     C_NOTHING  Symb_section
        ChkCmd  <1ah>     C_NOTHING  End_Decode
        db 0

        DBGBRK  4, 60H
        mov     di, sym_File_Ptr
symFile1:
        lodsb
        stosb
        cmp     al, 21h
        jae     symFile1
        dec     si
        mov     word ptr [di-1], 0      ;1st 0 for filename, 2nd for list
        mov     sym_File_Ptr, di
        jmp     Symb_section

Sym_Buffer      equ IO_Buffer           ;use as temp buffer

        INCLUDE SPSYM.ASM

Load_File:
        lds     si, dword ptr InstData.SIS_Virt_Dev_File_Ptr
        mov     dx, offset IO_FileName
        push    cs
        pop     es
        mov     di, dx
@@:     lodsb
        stosb
        cmp     al, 0
        jne     @b
        ; Full file path is copied:  'd:\...\SPWIN.EXE',0
        sub     di, 4                   ; back to 'EXE',0
        pop     si
        push    cs
        pop     ds
        movsw                           ; New extention
        movsb
        push    si
        mov     ax, 3d00h
        int     21h
        mov     cx, 0
        jc      short @f
        xchg    bx, ax
        mov     ah, 3fh
        mov     cx, 2000h
        mov     dx, offset IO_Buffer
        int     21h
        cmc
        sbb     cx, cx
        and     cx, ax                  ; 0=error, else=length
        mov     ah, 3eh
        int     21h
@@:     ret                             ; return cx as length

; ---------------------------------------------------------------------------
NUL_device      db 'NUL     '

win_dot_com     db 'win.com',0

windir_not_found:
        call    msg_quit
        db      13,10,'Cannot locate WIN.COM.',0,4

Find_WinDir:
        lds     si, dword ptr PathPtr
        push    cs
        pop     es
        mov     di, offset WinPath
        cld
        mov     cx, 66
        lodsb
        cmp     al, 0
        je      windir_not_found
        cmp     al, ';'
        jne     Add_Path2
Add_Path1:
        lodsb
        cmp     al, ';'
        je      Add_Name1
        cmp     al, 0
        je      Add_Name1
Add_Path2:
        stosb
        loop    Add_Path1
        inc     si
Add_Name1:
        dec     si
        push    cs
        pop     ds
        mov     word ptr PathPtr[0], si

        mov     al, [di-1]
        cmp     al, '\'
        je      Add_Name2
        cmp     al, '/'
        je      Add_Name2
        cmp     al, ':'
        je      Add_Name2
        mov     al, '\'
        stosb
Add_Name2:
        mov     si, offset win_dot_com
        mov     cl, 4           ; len( 'WIN.COM\0' ) = 8
        rep     movsw
        mov     dx, offset WinPath
        mov     ax, 4300h
        int     21h
        jc      Find_WinDir
        ret

; ---------------------------------------------------------------------------
; In:   AX = PSP
Get_Env_Data:
        mov     es, ax
        mov     ax, es:[2ch]            ;environment segment
        mov     word ptr InstData.SIS_Virt_Dev_File_Ptr[2], ax ;ENV

        mov     es, ax
        xor     di, di
        cld
        xor     ax, ax
Find_Env_Path:
        scasb
        je      Found_Prog_Path
        dec     di
        mov     si, offset PathStr      ; 'PATH='
        mov     bx, di
        mov     cx, 5
        repe    cmpsb
        je      Found_Env_Path
        mov     di, bx
        mov     ch, 80h
        repne   scasb
        je      Find_Env_Path

Found_Env_Path:
        mov     word ptr PathPtr[0], di
        mov     word ptr PathPtr[2], es

; get a pointer to the pathname of SPWIN.EXE in the environment seg.

        mov     ch, 80h                 ;big number
Find_Prog_Path:
        repne   scasb                   ;get past one null and stop
        scasb                           ;another null
        jnz     Find_Prog_Path         ;no.

Found_Prog_Path:
        scasw                           ;skip the word before the name.

; prepare part of the instance data list. Stuff in pointer to the file name
; and refernce data 

        mov     word ptr InstData.SIS_Version, 3
        mov     word ptr InstData.SIS_Virt_Dev_File_Ptr, di
        mov     word ptr InstData.SIS_Instance_Data_Ptr[0], ax
        mov     word ptr InstData.SIS_Instance_Data_Ptr[2], ax
        mov     word ptr InstData.SIS_Reference_Data[0], cs
;;      mov     word ptr InstData.SIS_Reference_Data[2], ax
        ret

; ---------------------------------------------------------------------------
Is_Xms_Loaded:
        mov     ax, 4300h
        int     2fh
        cmp     al, 80h
        je      short @f
        call    msg_quit
        db      13,10,'XMS memory not available.',0,5

@@:     mov     ax, 4310h
        int     2fh
        mov     word ptr xms_entry[0], bx
        mov     word ptr xms_entry[2], es
        ret

.8086
; ---------------------------------------------------------------------------
Is_386Cpu:
        ; Make sure we are running on 386 or better CPU
        mov     cx, 0f070h
        pushf
        pop     ax
        or      ah, ch
        push    ax
        popf
        pushf
        pop     ax
        and     ah, ch
        cmp     ah, cl
        je      short cpu_ok

        call    msg_quit
        db      13,10,'80386 or higher CPU required.',0,2

cpu_ok: ret
.386p

; ---------------------------------------------------------------------------
Is_Window_Running:
        mov     ax, 1600h
        int     2fh                     ; check if we already running
                                        ; under win3.x
        test    al, 7fh
        jz      short @f

        call    msg_quit
        db      13,10,'Windows is already running!.',0,3

@@:     ret

; ---------------------------------------------------------------------------
get_Dos_Info:
        mov     ax, 3000h
        int     21h
        xchg    al, ah
        mov     DosInfo.DosVersion, ax

        mov     ah, 52h
        int     21h
;       mov     word ptr DosInfo.listPtr[0], bx
;       mov     word ptr DosInfo.listPtr[2], es
        mov     ax, es:[bx-2]
        mov     DosInfo.FirstMemBlock, ax
        cld
finddev:inc     bx
        mov     si, offset NUL_device
        lea     di, 10[bx]
        mov     cx, 8
        repe    cmpsb
        jne     short finddev
        mov     word ptr DosInfo.NullDevicePtr[0], bx
        mov     word ptr DosInfo.NullDevicePtr[2], es
        mov     es, cx
        mov     cx, word ptr es:[408h]
        jcxz    short @f                ; use 3bc if 0
        mov     DosInfo.PrinterPort, cx
@@:
        mov     ax, 4
        call    get_PortAddress
        mov     DosInfo.PrinterPort, ax ; LPT1 as default printer
        mov     ax, 5
        call    get_PortAddress
        mov     DosInfo.ParaPort, ax    ; LPT2 as default ParaPort
        xor     ax, ax
        call    get_PortAddress
        mov     DosInfo.SerialPort, ax  ; COM1 as default SerialPort

        mov     ax, 1a00h
        int     10h
        cmp     al, 1ah
        je      short getVgaInfo
        ret

getVgaInfo:
        mov     ax, 1130h
        mov     bh, 6                   ; get address of 8x16 ROM chars
        int     10h
        ; es:bp = ptr 8x16 Fonts
        xor     eax, eax
        mov     ax, es
        shl     eax, 4
        movzx   ebx, bp
        add     eax, ebx
        mov     DosInfo.VgaFont8x16, eax

        push    ds
        pop     es
        cld
        ret

        even
Sym_Save_Seg    dw 0
sym_File_Ptr    dw offset sym_File_End
xms_Data_beg    label byte
DosInfo         DosInfoStru <>
IO_Buffer       label byte
                ; Default setting when SPWIN.INI not present.
                db  'SET F1=?;',0
                db  'SET F4=VS;',0
                db  'SET F5=Q;',0
                db  'SET F7=G.C;',0
                db  'SET F8=T;',0
                db  'SET F9=BP.C;',0
                db  'SET F10=P;',0
                db  'SET ^F1=CM1;',0
                db  'SET ^F2=CM2;',0
                db  'SET ^F3=CM3;',0
                db  'SET ^F4=CM4;',0
                db  'SET ^F5=CM5;',0
                db  'SET ^F6=CM6;',0
                db  'SET ^F7=CM7;',0
                db  'SET ^F8=CM8;',0
                db  'SET ^F9=CM9;',0
                db  'SET ^F10=CM0;',0
                db  'SET @F1=DM1;',0
                db  'SET @F2=DM2;',0
                db  'SET @F3=DM3;',0
                db  'SET @F4=DM4;',0
                db  'SET @F5=DM5;',0
                db  'SET @F6=DM6;',0
                db  'SET @F7=DM7;',0
                db  'SET @F8=DM8;',0
                db  'SET @F9=DM9;',0
                db  'SET @F10=DM0;',0
                db  'SET @TAB=D.A;',0
                db  'SET ^TAB=D.W;',0
                db  'SET FIVE=U EIP;',0
                db  'SET ~FIVE=U.D;',0
                db  'SET PLUS=T;',0
                db  'SET MINUS=P;',0
                db  'SET ^PGDN=MC 9;',0
                db  'SET ^PGUP=MC-9;',0
                db  'SET ^UP=MD-4;',0
                db  'SET ^DOWN=MD 4;',0
                db  'SET ~RIGHT=D.D+1;',0
                db  'SET ~LEFT=D.D-1;',0

IO_FileName     db 128 dup (0)
                db (IO_Buffer + 2000h - $) dup (0)

                even
xms_Data_len    equ ($-xms_Data_beg)
sym_File_List   label byte              ;default symbol files
                db 'KRNL386.EXE',0
                db 'USER.EXE',0
                db 'GDI.EXE',0
                db 'SYSTEM.DRV',0
                db 'KEYBOARD.DRV',0
                db 'SHELL.DLL',0
                db 'TOOLHELP.DLL',0
IFDEF _W95_
                db 'KERNEL32.DLL',0
                db 'GDI32.DLL',0
                db 'USER32.DLL',0
                db 'ADVAPI32.DLL',0
ELSE
                db 'PROGMAN.EXE',0
ENDIF
sym_File_End    label byte              ;default symbol files
                db 0

_TEXT   ends
        end     SPWIN

