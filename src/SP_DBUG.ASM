title.  SoftProbe - Debugging support.

; ---------------------------------------------------------------------
; Written by: Mehdi Sotoodeh
;
; THIS SOFTWARE IS PROVIDED BY THE AUTHORS ''AS IS'' AND ANY EXPRESS
; OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
; ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE
; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
; BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
; OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
; EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
; ---------------------------------------------------------------------

SP_DBUG EQU 1
INCLUDE SP_DEFS.INC 
INCLUDE DEBUGSYS.INC            ; From Win95 DDK
INCLUDE SP_KRNL.INC 

; ---------------------------------------------------------------------------
LDATA_SEG
; ---------------------------------------------------------------------------

Prev_Out_Debug_String   dd ?
Prev_Out_Debug_Chr      dd ?
Prev_Is_Debug_Chr       dd ?
Prev_In_Debug_Chr       dd ?
IFDEF   _W95_
Prev__Debug_Printf_Service dd ?
Prev__Trace_Out_Service    dd ?
Prev__Debug_Out_Service    dd ?
Win386_Query_Regs       SaveRegs_Struc<>
ENDIF
PUBDWRD SPWIN_P16Int21Ptr 0
PUBDWRD SPWIN_P16Selector 0

LDATA_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------

; ***************************************************************************
;
; Protected mode Debugger (int 41h) services:
;
; AX=00 Output a char           DS:DX=char*
; AX=01 Input a char            on exit: AL=char
; AX=0D Task going out          no arg, task=current task
; AX=0E Task comming in         no arg, task=current task
; AX=12 Output string           DS:SI(3.0)/ES:SI(3.1)=far *string
; AX=50 Load segment            ES:DI=module name (ASCIIZ)
;                               CX=selector     
;                               SI=segment flags
;                               BX=segment number
;                               DX=hInstance
; AX=51 Move segment
; AX=52 Free segment            BX=selector
; AX=56 register "Dump Global Heap" handler  CX:BX=address
; AX=57 register "Dump Free Heap" handler    CX:BX=address
; AX=58 register "Dump LRU Heap" handler     CX:BX=address
; AX=59 Load task               CX:BX=CS:IP of new task
; AX=5C Free segment            BX=selector
;       Same as 52, except called only when KERNEL starts up.
;       Called once for CS and once for DS alias to CS.
; AX=60 End of segment load
; AX=61 End of segment discard
; AX=62 App terminating         byte at [SP+6]=exit code
; AX=63 Async stop (Ctrl-Alt-SysReq)
; AX=64 DLL loaded              CX:BX=CS:IP entry point
;                               SI=Module handle (SI:0=NE header)
; AX=65 Module removed          ES=Module handle (ES:0=NE header)
;
; Following functions are extracted from windows itself.
;
; AX=4F Debugger present        EAX=0F386h
; AX=5A BurgerMaster            BX=30A (version?)
;                               DX:CX=&KERNEL!THHOOK (DS:218)
; AX=02
; AX=70 Register 32-bit dot command
; AX=71
; AX=72 Deregister dot command
; AX=73 printf32
; AX=74
; AX=75 get registers
; AX=76 set registers
; AX=77 get char from command line
; AX=78 evaluate expression
; AX=79 verify memory address
; AX=7A display registers
; AX=7B stack dump
; AX=7C-8B
; AX=5D
; AX=0F
; AX=150
; AX=152
; AX=40
; AX=F003
;
; ===========================================================================
PUBPROC Int41_Trap
        DBGBRK  4
        push    eax                     ; as R_Fault
        call    Save_CPU_Registers
        call    CollectKernelInfo
        call    i41_Dispatch
        call    Restore_CPU_Registers
        add     esp, 4
IF DBG
        db      0eah                    ; jmp xxxx:xxxxxxxx
ELSE
        iretd
ENDIF
Int41_oldVector dd 0,0

i41_identify:
        mov     word ptr [ebp].R_EAX, DS_DebPresent ; 0F386h
        ret

i41_KernelInfo: ; Return burgerMaster selecor:handle
        ; DX:CX=&KERNEL!THHOOK
        DBGBRK  3
        mov     eax, [ebp].R_ECX
        mov     word ptr THHOOK_PTR[0], ax
        mov     eax, [ebp].R_EDX
        mov     word ptr THHOOK_PTR[4], ax
        ret

i41_CheckFault:
; EXIT: AX == 0, handle fault normally
;       AX != 0, handled by debugger
        DBGBRK  3
        movzx   eax, word ptr [ebp].R_EBX ; BX=fault number
        cmp     al, 1                   ; Int 1
        je      short i41_ChkFlt1
        test    byte ptr [ebp].R_ECX, DEBUG_FAULT_TYPE_PM
        jz      short i41_ChkFltDone
        xor     ecx, ecx                ; as faulting CS
        call    Map_Faults
        jnc     short i41_ChkFltDone
IFE     DBG
        mov     al, handle_fault
        mov     byte ptr [ebp].R_EAX, al
ENDIF
        not     handle_fault
i41_ChkFltDone:
        ret

i41_ChkFlt1:
        DBGBRK  3
        or      SP_flags, SP_CLIENT     ; trap it with Client break
        ret

i41_TrapFault:
; IN:   BX     = falut number
;       CX:EDX = faulting CS:EIP
;       EDI    = faulting flags
;       ESI    = fault error code
; EXIT: CD:EDX = replacement CS:EIP
        DBGBRK  3
        mov     handle_fault, 0
        movzx   eax, word ptr [ebp].R_EBX ; BX=fault number
        movzx   ecx, word ptr [ebp].R_ECX ; faulting CS
        mov     edx, [ebp].R_EDX          ; faulting EIP
        jmp     Map_Faults

i41_AsyncStop:
        pop     eax                     ; return address
        call    SPWIN_MouseTrap
        db      'Async Stop',d_sub

i41_InChar:
        DBGBRK  4
        call    SPW_Screen
        call    Display_Log
        db      ' Input requested...',0
        ; Flush keyboard
        DBGBRK  4
@@:     call    key_check
        jnz     short @b
        call    key_read
        mov     byte ptr [ebp].R_EAX, al
        DBGBRK  4
        test    SP_flags, SP_ACTIVE
        jz      Usr_Screen              ; Restore user screen
        ret

i41_IsChar:
        call    key_check
        mov     byte ptr [ebp].R_EAX, al
        ret

i41_OutChar:
        ; DEBUGSYS.INC says DL=char
        ; Undoc windows says DS:DX=&char
        DBGBRK  3
        lea     esi, [ebp].R_EDX        ; points to the char
        mov     cl, 1                   ; max length of string=1
        push    ds
        call    convert_and_log         ; push address of filter proc
        ; The filter function
        stosb                           ; no transformation
        ret

i41_OutStr16:
        db      0a8h                    ; TEST AL,xx    (CF=0)
i41_OutStr32:
        stc
        sbb     esi, esi
        mov     si, -1                  ; ffffffff or 0000ffff
        and     esi, [ebp].R_ESI
        push    ds
        call    convert_and_log_max     ; push address of filter proc
        ; The filter function
        stosb                           ; no transformation
        ret

convert_and_log_max:
        mov     cl, 250                 ; max length of string
convert_and_log:
        push    ecx                     ; max length
        ; PARAM1 = max length
        ; PARAM2 = &filter proc
        mov     edi, OFFSET32 Display_Buffer + 160
        mov     eax, [ebp].R_DS         ; ax:esi=DS:ESI=&string
        call    ConvertUserString
        pop     ecx                     ; remove length
        pop     esi                     ; remove filter function
        pop     ds
        mov     byte ptr [edi], 0
        mov     ebx, OFFSET32 Display_Buffer + 160
        cmp     byte ptr [ebp].R_EAX, DS_Printf
        jne     short @f
        sub     edi, ebx
        mov     [ebp].R_EAX, edi        ; return number of chars printed
@@:     ; ebx = string
        call    Log_Event
        db      d_text,80
        _jsr    Repeat_If_More          ; loop on multi-line messages
        db      d_sub

i41_FreeSeg_32:
        ; bx=segment number
        ; dx:edi ptr module name
        DBGBRK  2
        mov     ebx, [ebp].R_EDI
        movzx   eax, word ptr [ebp].R_EDX
        call    Get_FlatAddress
        movzx   eax, word ptr [ebp].R_EBX
        push    eax                     ; logical segment number
        call    Log_Event
        db      'Free32',d_tab,d_text,8,'(',d_deci,')',d_lf,d_sub

Repeat_If_More:
        DBGBRK  3
        mov     al, [ebx-1]
        cmp     al, s_el
        je      short i41_return1
        cmp     al, s_col
        jne     short @f
        stosb
        mov     al, [ebx]
        inc     ebx
@@:     stosb
        sub     esi, 5                  ; backup 'd_text,80,jsr xxxx'
i41_return1:
        ret

i41_LoadSeg_32:
        ; dx:ebx = ptr D386_Device_Params struc
        DBGBRK  3
        call    applyBreaks             ; to enable BRK_ON_MOD

        mov     ebx, [ebp].R_EBX
        movzx   eax, word ptr [ebp].R_EDX
        call    Get_FlatAddress         ;ebx=linear address
        jc      short i41_return1

        push    [ebx].DD_length
        push    [ebx].DD_base
        movzx   ecx, [ebx].DD_actual_sel
        push    ecx
        movzx   edi, [ebx].DD_logical_seg
        push    edi                     ; logical segment number
        movzx   eax, word ptr [ebx].DD_sym_name[4]
        mov     ebx, dword ptr [ebx].DD_sym_name[0]
        call    Get_FlatAddress         ;ebx=linear address
IFDEF   _W95_
        ; Find the selector for the 1st segment of kernel32.
        jc      short @f
        mov     esi, ebx
        call    qword_read_@esi
        jc      short @f
        cmp     eax, 'nrek'             ;'kernel32'
        jne     short @f
        cmp     edx, '23le'             ;'kernel32'
        jne     short @f
        DBGBRK  3
        mov     esi, OFFSET32 Kernel32_CodeSelector
        dec     edi                     ;1st segment=code
        jz      short setKernel32Sel
        cmp     edi, 4-1                ;segemnts 4,5,6 are data
        jnz     short @f
        mov     esi, OFFSET32 Kernel32_DataSelector
        mov     eax, [esp+8]            ;.DD_base of seg# 4 of kernel32
        mov     [esi+4], eax
setKernel32Sel:
        mov     [esi], ecx
@@:
ENDIF
        call    Log_Event
        db      'Load32',d_tab,d_text,8,'(',d_deci,') Addr=',d_h48
        db      ' Len=',d_h32,d_lf,d_sub

i41_LoadSegment:
        ; DX=hInstance
        ; SI=segment flags
        ; CX=selector
        ; BX=segment number

        call    applyBreaks             ; to enable BRK_ON_MOD
        movzx   ebx, word ptr [ebp].R_EDI
        mov     eax, [ebp].R_ES         ; ES:DI=module name
        call    Get_FlatAddress
        movzx   eax, word ptr [ebp].R_EBX ; BX=segment number
        inc     eax
        push    eax
        call    Log_Event
        db      'Load16',d_tab,d_text,8,'(',d_deci
        db      ') Sel=',d_r16,R_ECX,' Flags=',d_r16,R_ESI
        db      ' hInst=',d_r16,R_EDX,d_lf,d_sub

i41_FreeSegment:
        ; BX=selector
        ; disable breaks in this segment
        mov     edi, OFFSET32 breakTable
        DBGBRK  4
rmvBrk16Loop:
        test    [edi].brk_Flags, BRK_ACTIVE
        jz      short rmvBrk16Next
        test    [edi].brk_TypeInfo, BRKTYPE_I3 OR BRKTYPE_DRX OR BRKTYPE_MOD
        jz      short rmvBrk16Next

        ; check if we have any breaks set in this segment
        movzx   eax, word ptr [ebp].R_EBX
        xor     eax, [edi].brk_Address[4] ;
        and     eax, not 3              ; ignore PL
        jnz     short rmvBrk16Next
        DBGBRK  3
        call    Remove_Break
        ; CF=1 if failed
        ; failed or not, deactivate it
        and     [edi].brk_Flags, not (BRK_APPLY OR BRK_HIT1)
        test    [edi].brk_TypeInfo, BRKTYPE_I3 ; BRKTYPE_DRX OR BRKTYPE_MOD
        jz      short rmvBrk16Next
        and     [edi].brk_Flags, not BRK_ACTIVE
        test    [edi].brk_Flags, BRK_TEMP
        jz      short rmvBrk16Next
        mov     [edi].brk_Flags, 0      ; free it
rmvBrk16Next:
        add     edi, BreakInfoSize
        cmp     edi, OFFSET32 breakTable + TOTAL_BREAKS*BreakInfoSize
        jb      short rmvBrk16Loop

        mov     eax, [ebp].R_EBX
        call    ModuleNameFromSelector
        push    esi
        call    Log_Event
        db      'Free16',d_tab,'Segment ',d_r16,R_EBX
        db      ' ',d_fname,d_lf,d_sub

i41_DllLoad:
        call    applyBreaks             ; to enable BRK_ON_MOD
        ; CX:BX=CS:IP entry point
        ; si=module handle (SI:0=NE header)
        mov     eax, [ebp].R_ESI
        call    ModuleNameFromHandle
        push    esi
        call    Log_Event
        db      'LoadDLL',d_tab,d_fname,' hModule=',d_r16,R_ESI
        db      ' Entry=',d_r16,R_ECX,':',d_r16,R_EBX,d_lf,d_sub

i41_ModRemove:
        mov     eax, [ebp].R_ES         ; ES=Module handle (ES:0=NE header)
        call    ModuleNameFromHandle
        push    esi
        call    Log_Event
        db      'Remove',d_tab,d_fname
        db      ' handle=',d_r16,R_ES,d_lf,d_sub

i41_LoadTask:
        ; CX:BX=CS:IP entry point
        call    applyBreaks             ; to enable BRK_ON_MOD
        call    GetCurrentTask
        ; ax=module handle
        push    eax
        call    ModuleNameFromHandle
        push    esi
        call    Log_Event
        db      'Task16',d_tab,d_fname,' hModule=',d_h16
        db      ' Entry=',d_r16,R_ECX,':',d_r16,R_EBX,d_lf,d_sub

i41_TaskIn:
        call    GetCurrentTask
        ; ax=module handle
        push    eax
        call    ModuleNameFromHandle
        push    esi
        call    Log_Event
        db      'TaskIn',d_tab,d_fname,' hModule=',d_h16,d_lf,d_sub

i41_TaskOut:
        call    GetCurrentTask
        ; ax=module handle
        push    eax
        call    ModuleNameFromHandle
        push    esi
        call    Log_Event
        db      'TaskOut',d_tab,d_fname,' hModule=',d_h16,d_lf,d_sub

i41_Printf:
        ; ds:esi=format
        ; es:edi=args
        DBGBRK  4
        mov     esi, [ebp].R_ESI        ; format
        mov     edx, [ebp].R_EDI        ; args

        push    ds
        call    convert_and_log_max     ; push address of filter proc
        ; The filter function will be called on every char
        cmp     al, '%'
        je      short printf_fmtchar
        cmp     al, '\'
        jne     short printf_put

        ; should support \r, \t, \n, \a, \b
        lodsb
        cmp     al, 'n'                 ; '\n' = d_lf
        jne     short @f
        mov     al, d_lf
        stosb
        ret

@@:     cmp     al, 'r'                 ; '\r' = d_col,0
        jne     short @f
        mov     al, d_col
        stosb
        mov     al, 0
        stosb
        ret

;@@:     cmp     al, 'a'                 ; '\a' =
;@@:     cmp     al, 'b'                 ; '\b' =

@@:     cmp     al, 't'                 ; '\t' = d_tab
        jne     short @f
        mov     al, d_tab
        stosb
        ret

@@:     cmp     al, '\'                 ; '\\' = '\'
        je      short printf_put
        dec     esi
        mov     al, '\'
printf_put:
        stosb
        ret

printf_fmtsize:
        mov     ecx, [edx]              ; get parameter from arg list
        add     edx, 4
        cmp     ecx, 81
        jb      short printf_fmtnext
printf_fmtchar:
        DBGBRK  4
        push    80
        pop     ecx                     ; default size
printf_fmtnext:
        lodsb
        cmp     al, '%'                 ; '%%' = '%'
        je      short printf_put
        cmp     al, '-'
        je      short printf_fmtnext
        cmp     al, '+'
        je      short printf_fmtnext
        cmp     al, '0'
        je      short printf_fmtnext
        cmp     al, ' '
        je      short printf_fmtnext
        cmp     al, '#'
        je      short printf_fmtnext
        cmp     al, '*'
        je      short printf_fmtsize
        dec     esi
        call    Get_Decimal             ;get the width
        test    eax, eax
        jz      short @f
        xchg    ecx, eax                ;new width
@@:     lodsb
        cmp     al, '.'                 ;.precision?
        jne     short @f
        call    Get_Decimal             ;get the width
printf_fmtattr:
        lodsb
@@:     or      al, 20h
        cmp     al, 'l'
        je      short printf_fmtattr
        cmp     al, 'h'
        je      short printf_fmtattr
        cmp     al, 'p'
        je      short printf_fmtattr
        cmp     al, 'n'
        je      short printf_fmtattr
        cmp     al, 'a'
        je      short printf_fmtattr
        cmp     al, 'f'
        je      short printf_fmtattr
        cmp     al, 'r'
        je      short printf_fmtattr
        cmp     al, 'z'
        je      short printf_fmtattr
        mov     ebx, [edx]              ; get parameter from arg list
        add     edx, 4
        cmp     al, 's'
        je      Display_Text            ; DS:EBX=string, ECX=max len
        cmp     al, 'd'
        xchg    eax, ebx
        je      short printf_deci
        cmp     bl, 'c'
        je      short printf_char
        cmp     bl, 'u'
        jne     hex_32                  ; hex as default format
printf_deci:
        push    edx
        call    Convert_Decimal
        pop     edx
printf_fmterror:
        ret

printf_char:
        cmp     al, 20h
        jae     short @f
        mov     byte ptr [edi], s_chr
        inc     edi
@@:     stosb
        ret

;i41_RegLRUHeap:
; AX=58 register "Dump LRU Heap" handler     CX:BX=address
;       DBGBRK  1
;       ret

;i41_RegFreeHep:
; AX=57 register "Dump Free Heap" handler    CX:BX=address
;       DBGBRK  1
;       ret

;i41_RegGlbHeap:
; AX=56 register "Dump Global Heap" handler  CX:BX=address
;       DBGBRK  1
;       ret

;i41_UserVars:
; AX=5D bx=windows version
;       cx=number of words in the array
;       ds:si=ptr an array of offsets
;             00 - 0=Retail, 1=debug
;             02 - offset to hHmenuSel
;             04 - offset to hHwndSel
;             06 - offset to pclsList
;             08 - offset to pdceFirst
;             0A - offset to hwndDesktop
;       DBGBRK  1
;       ; copy the array
;       ret

i41_Fnc macro n, a
        dw n
        dw OFFSET32 a - $
        endm

i41_Functions:
 i41_Fnc DS_FreeSeg_32   i41_FreeSeg_32  ; 152 BX=seg#, DX:EDI=mod name
 i41_Fnc DS_LoadSeg_32   i41_LoadSeg_32  ; 150 SI=type, DX:EBX=struc
 i41_Fnc DS_TrapFault    i41_TrapFault   ; 83 bx=fault#, cx:edx=addr, edi=flg
 i41_Fnc DS_CheckFault   i41_CheckFault  ; 7f bx=fault#, cx=type mask
 i41_Fnc DS_Printf       i41_Printf      ; 73 ds:esi=format, es:edi=args
 i41_Fnc DS_DELMODULE    i41_ModRemove   ; 65
 i41_Fnc DS_LOADDLL      i41_DllLoad     ; 64
 i41_Fnc DS_INT2         i41_AsyncStop   ; 63 Async stop (Ctrl-Alt_SysReq)
;i41_Fnc DS_User_Vars    i41_UserVars    ; 5D bx=win ver, ds:si=.., cx=#words
 i41_Fnc DS_ReleaseSeg   i41_FreeSegment ; 5C 52+Break restore
 i41_Fnc DS_Kernel_Vars  i41_KernelInfo  ; 5Ah
 i41_Fnc DS_StartTask    i41_LoadTask    ; 59 starting new task
;i41_Fnc DS_DLL          i41_RegLRUHeap  ; 58 CX:BX=address
;i41_Fnc DS_DFL          i41_RegFreeHep  ; 57 CX:BX=address
;i41_Fnc DS_DGH          i41_RegGlbHeap  ; 56 CX:BX=address
 i41_Fnc DS_FreeSeg      i41_FreeSegment ; 52 BX=segment value
 i41_Fnc DS_LoadSeg      i41_LoadSegment ; 50
 i41_Fnc DS_DebLoaded    i41_identify    ; 4Fh
 i41_Fnc DS_Out_Str16    i41_OutStr16    ; 12 DS:SI=string
 i41_Fnc DS_SWITCHIN     i41_TaskIn      ; 0E Task comming in (curr)
 i41_Fnc DS_SWITCHOUT    i41_TaskOut     ; 0D Task going out (curr)
 i41_Fnc DS_Is_Char      i41_IsChar      ; 03 Non blocking In_Chr
 i41_Fnc DS_Out_Str      i41_OutStr32    ; 02 DS:ESI=string
 i41_Fnc DS_In_Char      i41_InChar      ; 01 AL=Char
 i41_Fnc DS_Out_Char     i41_OutChar     ; 00 DL=char

i41_Dispatch:
        mov     eax, [ebp].R_EAX
        mov     edi, OFFSET32 i41_Functions - 2
i41_Next:
        inc     edi
        inc     edi
        scasw
        jb      i41_Next
        jne     short i41_unknown
        movsx   eax, word ptr [edi]
        add     eax, edi
        push    eax
IF DBG
        ret

i41_unknown:
        DBGBRK  3
        call    Log_Event
        db      'I41: EAX=',d_r16,R_EAX,' EBX=',d_r32,R_EBX
        db      ' ECX=',d_r32,R_ECX,' EDX=',d_r32,R_EDX,d_lf,d_sub
ELSE
i41_unknown:
        ret
ENDIF

IFDEF   _W95_
; In:   ebx points to modulename.ext
PUBPROC Log_Exec32
        push    ebx
        call    Log_Event
        db      'Exec32',d_tab,d_fname,' Entry=',d_r16,R_CS,':'
        db      d_r32,R_EIP,d_lf,d_sub
ENDIF

; ***************************************************************************
;
;   Debug support
;
;   DESCRIPTION:
;
;   ENTRY:
;       EBX = Current VM handle
;       EBP = Client Registers
;
;   EXIT:
;
; ===========================================================================

PUBPROC SPWIN_Out_Debug_String
        DBGBRK  4
        pushfd                          ; as EFLAGS, also save IF
        push    cs
        push    [esp+8]                 ; caller EIP
        push    esi                     ; as R_Fault
        mov     esi, [esp+5*4].Pushad_ESI ; for #ESI expressions
        call    Save_CPU_Registers
        call    LogEvent_OutDbgStr
        call    Restore_CPU_Registers
        pop     esi
        add     esp, 2*4
        popfd                           ; restore IF
        ret

LogEvent_OutDbgStr:
        mov     esi, [ebp].R_Fault      ; ptr string
        push    ds
        call    convert_and_log_max     ; push address of filter proc
        ; The filter function will be called on every char
        cmp     al, '#'
        je      short SPWODS_Reg
        cmp     al, '?'
        je      short SPWODS_Addr
SPWODS_Put:
        stosb
SPWODS_Ret:
        ret

SPWODS_Addr:
        DBGBRK  3
        push    ecx
        call    Scan_AddressDS
        pop     ecx
        mov     al, '?'
        jc      short SPWODS_Put
        push    esi
        push    ecx
        ; edx:ebx=address
        push    edx
        push    ebx
        call    SectionNameFromAddress
        pop     ebx
        pop     eax
        pop     ecx
        pop     esi
        jnc     short SPWODS_Ret
        call    hex_16
        mov     al, ':'
        stosb
        xchg    eax, ebx
SPWODS_Hex32:
        jmp     hex_32

SPWODS_Hex:
        cmp     al, 2
        xchg    eax, ebx
        ja      short SPWODS_Hex32
        je      hex_16
        jmp     hex_08

SPWODS_Reg:
        push    ecx
        call    register_value
        ; ebx=value, ecx=size (1=8, 2=16, 3=32 bit long)
        xchg    eax, ecx
        pop     ecx
        jnc     short SPWODS_Hex
        mov     al, '#'
        stosb
        ret

PUBPROC SPWIN_Out_Debug_Chr
        DBGBRK  4
        push    eax
        push    edx
        xchg    edx, eax
        xor     eax, eax                ; DS_Out_Char
if      DS_Out_Char
        .err
endif
        int     41h
        pop     edx
        pop     eax
IF      DBG
        jmp     cs:Prev_Out_Debug_Chr
ELSE
        ret
ENDIF

PUBPROC SPWIN_Is_Debug_Chr
        push    ds
        push    VXD_DATASELECTOR
        pop     ds
        pushfd
        cli
        call    key_check
        popfd
        pop     ds
        test    al, al
        ret

PUBPROC SPWIN_In_Debug_Chr
        DBGBRK  4
        push    DS_In_Char
        pop     eax
        int     41h
        DBGBRK  4
        cmp     al, 1bh                 ; ESCAPE?
        ret

IFDEF   _W95_
; Win95 only debug services

PUBPROC SPWIN__Debug_Printf_Service
        DBGBRK  4
        push    esi
        push    edi
        mov     esi, [esp+0ch]          ; ds:esi=format
        mov     edi, [esp+10h]          ; es:edi=args
        push    DS_Printf
        pop     eax
        int     41h
        pop     edi
        pop     esi
        ret

; Display a message and break
PUBPROC SPWIN__Debug_Out_Service
        DBGBRK  4
        pushfd
        pushad
        mov     esi, [esp+4*10]         ; offset string
        call    SPWIN_Out_Debug_String
        call    Setup_Intr1_Here
        popad
        test    cs:DebugOutFlags, 1
        jz      short @f
        bts     dword ptr [esp], 8      ; TF=1
@@:     popfd
        ret     4

; MS documnetation for this service is not correct, esi is not used
; Push    msg
; VMMCall _Trace_Out_Service
PUBPROC SPWIN__Trace_Out_Service
        DBGBRK  4
        pushfd
        pushad
        mov     esi, [esp+4*10]         ; offset string
        call    SPWIN_Out_Debug_String
        popad
        popfd
        ret     4
ENDIF

; ---------------------------------------------------------------------------
; DOT command support
; ---------------------------------------------------------------------------
IFDEF   _W95_
win386_not_found:
        reportError 'Win386 Error.'

PUBPROC Cmd_QueryVxd
        DBGBRK  4
        jz      syntaxError
        xor     eax, eax
        push    ebp
        int     Win386_Query_Int        ; int 22h
        pop     ebp
        xor     ax, Win386_Q_Ack        ; 0F386h
        jnz     win386_not_found

        ; esi points to the vxd name
        mov     edi, OFFSET32 Win386_Query_Regs
        mov     ebx, [ebp].R_EAX
        mov     [edi].Debug_EAX, ebx
        mov     ebx, [ebp].R_EBX
        mov     [edi].Debug_EBX, ebx
        mov     ebx, [ebp].R_ECX
        mov     [edi].Debug_ECX, ebx
        mov     ebx, [ebp].R_EDX
        mov     [edi].Debug_EDX, ebx
        mov     ebx, [ebp].R_ESP
        mov     [edi].Debug_ESP, ebx
        mov     ebx, [ebp].R_EBP
        mov     [edi].Debug_EBP, ebx
        mov     ebx, [ebp].R_ESI
        mov     [edi].Debug_ESI, ebx
        mov     ebx, [ebp].R_EDI
        mov     [edi].Debug_EDI, ebx
        mov     ebx, [ebp].R_ES
        mov     [edi].Debug_ES , bx
        mov     ebx, [ebp].R_SS
        mov     [edi].Debug_SS , bx
        mov     ebx, [ebp].R_DS
        mov     [edi].Debug_DS , bx
        mov     ebx, [ebp].R_FS
        mov     [edi].Debug_FS , bx
        mov     ebx, [ebp].R_GS
        mov     [edi].Debug_GS , bx
        mov     ebx, [ebp].R_EIP
        mov     [edi].Debug_EIP, ebx
        mov     ebx, [ebp].R_CS
        mov     [edi].Debug_CS , bx
        mov     ebx, [ebp].R_EFLAGS
        mov     [edi].Debug_EFlags, ebx

        inc     eax                     ; eax=1 (Win386_Query)
        push    ebp
        int     Win386_Query_Int        ; int 22h
        pop     ebp
        DBGBRK  4
        ret
ENDIF

; PMode INT 41 handler
PM_Int41_Handler:
        int     41h
        iretd

PM_Int21_Terminate:
        mov     ah, 4ch
        int     21h

LCODE_ENDS

; ---------------------------------------------------------------------------
ICODE_SEG
; ---------------------------------------------------------------------------
PUBPROC Debug_Critical_Init
        ; ES:EDI = IDT to use
        call    Setup_PM_Int
        db      41h
        dd      OFFSET32 Int41_oldVector
        dd      OFFSET32 Int41_Trap
        dd      0ee000000h + VXD_CODESELECTOR
        ret

PUBPROC Debug_Service_Init
        ; Redirect Debug i/o
        ; These hooks cannot be done before Sys_Critical_Init

        Hook_Service Out_Debug_String
        Hook_Service Out_Debug_Chr
        Hook_Service Is_Debug_Chr
        Hook_Service In_Debug_Chr

IFDEF   _W95_
        ; Win95 only debug services
        Hook_Service _Debug_Printf_Service
        Hook_Service _Trace_Out_Service
        Hook_Service _Debug_Out_Service
ENDIF
        ret

PUBPROC Debug_Device_Init
        VMMcall _BuildDescriptorDWORDs, <<OFFSET32 PM_Int41_Handler>, 1fh, 0fbh, 40h, 0>
        VMMcall _Allocate_GDT_Selector, <edx, eax, 0>
        mov     word ptr SPWIN_P16Selector, ax
        xchg    ecx, eax
        jecxz   short @f
        mov     eax, 41h
        xor     edx, edx
        VMMcall Set_PM_Int_Vector
@@:     mov     SPWIN_P16Int21Ptr, PM_Int21_Terminate - PM_Int41_Handler

        ret

ICODE_ENDS
END

