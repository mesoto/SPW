title.  SoftProbe - Breakpoint support

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

SP_BRKS EQU 1
include SP_DEFS.inc

; ---------------------------------------------------------------------------
LDATA_SEG
; ---------------------------------------------------------------------------
Prev_Enable_Local_Trapping   dd 0
Prev_Disable_Local_Trapping  dd 0
Prev_Enable_Global_Trapping  dd 0
Prev_Disable_Global_Trapping dd 0

IF DBG
PUBDWRD         int_flags 0
ELSE
PUBDWRD         int_flags 1110b         ; BI1, BI3 and NMI
ENDIF
                dd 224/32 dup (0)

; ---------------------------------------------------------------------------
@@nbrk  = TOTAL_BREAKS-1
        call    Interrupt_Hook
PUBBYTE breakTable here
        REPT    @@nbrk
        BreakInfoStru <>
        call    Interrupt_Hook
        ENDM
        BreakInfoStru <>

DR_BreakPtr      dd 4 dup(0)
DR3_BreakAddress dd 0

; ---------------------------------------------------------------------------

HwBreak_Flags   dd 0fh
SS1_Context     dd 0
SS1_ReturnAddr  dd OFFSET32 Temp_Break_Hit
SS1_PICMask     db 0ffh
                db 0
PUBWORD cap_Port     <0,0,0>    ;ports to be captured
PUBDWRD cap_Length   0          ;number of entries left
PUBBYTE cap_PortVal  <4 dup(0)> ;3 ports values + INIT flags
PUBBYTE cap_BreakNum <0,0,0>    ;holds break numbers associated with CAP

LDATA_ENDS

; ---------------------------------------------------------------------------
SCODE_SEG
; ---------------------------------------------------------------------------
; in:   bl = int #
; out:  eax:edx = access:selector:offset32
PUBPROC getIntVector
        push    ecx
        sidt    fword ptr [esp-2]
        pop     ecx                     ; IDT_Base
        movzx   ebx, bl
        mov     edx, [ecx+ebx*8+4]      ; edx=off16_31:acc:resv
        mov     eax, [ecx+ebx*8+0]      ; eax=selector:off00_15
        xchg    ax, dx
        ror     eax, 16
        ret

PUBPROC Setup_Intr1_Here
        or      SP_flags, SP_I1ON       ; Int1 comes here
PUBPROC Setup_Intr1
        and     SP_flags, not SP_SS1BREAK
        mov     bl, 1
        mov     edx, OFFSET32 Int01_Handler
        mov     eax, 0ee000000h         ; 386 int gate
PUBPROC setIntVectorCS
        mov     ax, cs                  ; VXD_CODESELECTOR
PUBPROC setIntVector
        ; in:   bl = int #
        ;       eax:edx = access:selector:offset32
        push    ecx
        sidt    fword ptr [esp-2]
        pop     ecx                     ; IDT_Base
        movzx   ebx, bl
        rol     eax, 16
        xchg    ax, dx
        mov     [ecx+8*ebx+0], eax
        mov     [ecx+8*ebx+4], edx
        ret

PUBPROC Apply_IntBreak

        mov     bl, [edi].brk_IntNumber ;int number
        cmp     bl, 60h
        jae     short applyIntBrk1

        ; If break already applied, leave it
        test    [edi].brk_Flags, BRK_APPLY
        jnz     short applyIntBrk1

        DBGBRK  3
        call    getIntVector
        mov     [edi].brk_IntVector[0], edx
        mov     [edi].brk_IntVector[4], eax

        lea     edx, [edi-5]
        rol     eax, 8
        and     al, 0f0h
        or      al, 00eh
        ror     eax, 8
        call    setIntVectorCS
applyIntBrk1:
        jmp     short breakApplied

; In:   edi = break info
; Out:  CF=0 :  break applied
;       CF=1 :  failed
PUBPROC Apply_Break
        mov     al, [edi].brk_TypeInfo

        test    al, BRKTYPE_DRX         ;BRK_CAP_IO, BRK_ON_EXEC,...
        jnz     short Apply_HwBreak

        test    al, BRKTYPE_IO          ;BRK_ON_IO
        jnz     short Apply_IoBreak
        cmp     al, BRK_ON_INT
        je      short Apply_IntBreak
        cmp     al, BRK_INT3
        je      short Apply_Int3Break
        cmp     al, BRK_ON_MOD
        jne     short applyFailed

PUBPROC Apply_ModBreak
        ; If break already applied, leave it
        test    [edi].brk_Flags, BRK_APPLY
        jnz     short breakApplied
        DBGBRK  4
        lea     esi, [edi].brk_ModuleName[1] ; (lstring -> asciiz)
        push    edi                     ; save the pointer
        call    GetP16ModuleFromName
        pop     edi                     ; restore edi
        jc      short applyFailed
        call    Mod16_EntryPoint
        jc      short applyFailed

        mov     [edi].brk_Address[0], eax
        mov     [edi].brk_Address[4], edx

PUBPROC Apply_Int3Break
        ; If break already applied, leave it
        test    [edi].brk_Flags, BRK_APPLY
        jnz     short breakApplied

        mov     ebx, [edi].brk_Address[0]
        mov     eax, [edi].brk_Address[4]
        call    Get_FlatAddress         ; ebx=linear address
        jc      short applyFailed
        mov     [edi].brk_LinAddress, ebx
IFDEF   _W95_
        mov     eax, CurMemoryContext
        mov     [edi].brk_MemContext, eax
ENDIF
        mov     al, [ebx]               ; can generate fault
        cmp     al, 0cch                ;
        je      short applyFailed
        mov     byte ptr [ebx], 0cch    ; can generate fault
        cmp     byte ptr [ebx], 0cch    ; written?
        jne     short applyFailed
        mov     [edi].brk_I3OrgInst, al
breakApplied:
        or      [edi].brk_Flags, BRK_APPLY
        ret

PUBPROC Apply_IoBreak
        DBGBRK  3
        ; If break already applied, leave it
        test    [edi].brk_Flags, BRK_APPLY
        jnz     short breakApplied

        mov     edx, [edi].brk_Address[0] ;port number
        call    SetIoBitMap
        setc    [edi].brk_TssIoState    ;save original value
        jmp     short breakApplied

PUBPROC Apply_HwBreak
        DBGBRK  3

        mov     ebx, [edi].brk_Address[0]
        cmp     [edi].brk_TypeInfo, BRK_ON_PIO
        je      short set_DR4
        cmp     [edi].brk_TypeInfo, BRK_CAP_IO
        je      short set_DR4
        mov     eax, [edi].brk_Address[4]
        call    Get_FlatAddress         ; ebx=linear address
        jnc     short set_hwaddr
applyFailed:
        stc
        ret

; To enable h/w breakpoint on port I/O (all rings), CR4.DE should be set.
set_DR4:db      0fh,20h,0e0h            ; mov eax, CR4
        or      al, 8                   ; CR4.DE=1 (debug extensions)
        db      0fh,22h,0e0h            ; mov CR4, eax

; DR7: [S3|T3|S2|T2|S1|T1|S0|T0|00|GD|001|GE|LE|G3|L3|G2|L2|G1|L1|G0|L0]
;       Sn = 00-one, 01-two, 11-four byte length
;       Tn = 00-inst only, 01-data write, 10-i/o 11-data r/w
;       GE = Exact Global data breakpoint match enable
;       LE = Exact local data breakpoint match enable
;       GD = Debug register protection (BD flag in DR6)
;       Gn = Global enable
;       Ln = Local enable

set_hwaddr:
        mov     [edi].brk_LinAddress, ebx
IFDEF   _W95_
        xor     eax, eax
        mov     [edi].brk_MemContext, eax
ENDIF
        movzx   eax, [edi].brk_DR7Value ; al=sstt00nn
        mov     dl, 03h
        and     edx, eax                ; DR0..3
        and     al, 0fch                ; al=sstt0000
        mov     ecx, DR7
        mov     DR_BreakPtr[edx*4], edi ; ptr BreakInfoStru
        call    dword ptr set_hw_break_reg[4*edx]
        mov     ah, 2                   ; GE=1
        or      ecx, eax
        mov     DR7, ecx
        DBGBRK  3
        ret

set_DR0:mov     DR0, ebx
        shl     eax, 12
        mov     al, 2
        ret
set_DR1:mov     DR1, ebx
        shl     eax, 16
        mov     al, 8
        ret
set_DR2:mov     DR2, ebx
        shl     eax, 20
        mov     al, 20h
        ret
set_DR3:test    cl, cl                  ; is temp hw break used?
        js      short @f
        mov     DR3, ebx
        shl     eax, 24
@@:     mov     al, 80h
        ret

PUBPROC Remove_Break

        mov     al, [edi].brk_TypeInfo
        test    al, BRKTYPE_DRX         ; BRK_CAP_IO, BRK_ON_EXEC,...
        jnz     short Remove_HwBreak
        cmp     al, BRK_ON_INT
        je      short Remove_IntBreak
        test    al, BRKTYPE_IO          ; BRK_ON_IO
        jnz     short Remove_IoBreak
        test    al, BRKTYPE_I3 + BRKTYPE_MOD ; BRK_INT3 or BRK_ON_MOD
        jz      short removeFailed

PUBPROC Remove_ModBreak
PUBPROC Remove_Int3Break
        ; If break already removed, leave it.
        test    [edi].brk_Flags, BRK_APPLY
        jz      short breakRemoved

        mov     ebx, [edi].brk_LinAddress
IFDEF   _W95_
;        test    ebx, 0ffc00000h
;        jz      short @f                ; if ebx <  00400000h
;        js      short @f                ; if ebx >= 80000000h
;        mov     eax, CurMemoryContext
;        cmp     eax, [edi].brk_MemContext
;        jne     short removeFailed
;@@:
ENDIF
        cmp     byte ptr [ebx], 0cch    ; can generate fault
        jne     short removeFailed
        mov     al, [edi].brk_I3OrgInst
        mov     [ebx], al               ; can generate fault
Remove_HwBreak:
breakRemoved:
        and     [edi].brk_Flags, not BRK_APPLY
        ret

removeFailed:
        stc
        ret

PUBPROC Remove_IntBreak
        mov     bl, [edi].brk_IntNumber ;int number
        cmp     bl, 60h
        jae     short breakRemoved

        ; If break already removed, leave it.
        test    [edi].brk_Flags, BRK_APPLY
        jz      short breakRemoved

        DBGBRK  3
        call    getIntVector
        add     edx, 5
        cmp     edx, edi
        jne     short removeFailed
        mov     edx, [edi].brk_IntVector[0]
        mov     eax, [edi].brk_IntVector[4]
        call    setIntVector
        jmp     short breakRemoved

PUBPROC Remove_IoBreak
        DBGBRK  3
        ; If break already removed, leave it.
        test    [edi].brk_Flags, BRK_APPLY
        jz      short breakRemoved

        cmp     [edi].brk_TssIoState, 0 ;saved original value
        jnz     short breakRemoved      ;if it was set, leave it set
        str     ax
        call    Get_Selector
        jc      short removeFailed
        xchg    ebx, eax
        ; ebx=base, edx=limit

        movzx   eax, [ebx].TSS_IOPORTS  ;can generate fault

        mov     esi, [edi].brk_Address[0] ;port number
        shr     esi, 3                  ;bit# to byte offset
        add     esi, eax
        cmp     esi, edx                ;outside TSS limit?
        jae     short breakRemoved
        mov     edx, [edi].brk_Address[0] ;port number
        btr     [ebx+eax], edx          ;ebx+eax=lin address of TSS:IO_MAP
        jmp     short breakRemoved

SCODE_ENDS

; ---------------------------------------------------------------------------
; * pmCode starts here ------------------------------------------------------
; ---------------------------------------------------------------------------
LCODE_SEG

        align   4
set_hw_break_reg label dword
        dd OFFSET32 set_DR0
        dd OFFSET32 set_DR1
        dd OFFSET32 set_DR2
        dd OFFSET32 set_DR3

; ---------------------------------------------------------------------------
; This routine is called by VMM before changing IDT
SPWIN_Set_PM_Exec_Mode:
        DBGBRK  3
        pushfd
        db      68h                     ; push xxxx
Prev_Set_PM_Exec_Mode dd 0
        jmp     short IDT_Switcher

SPWIN_Set_V86_Exec_Mode:
        DBGBRK  3
        pushfd
        db      68h                     ; push xxxx
Prev_Set_V86_Exec_Mode dd 0
IDT_Switcher:
        cli
        cld
        pushad
        mov     ch, 0ffh                ; keep 1st HIT state
        mov     cl, 0                   ; do not free temp breaks
        call    RemoveBreaks
        popad
        call    dword ptr [esp]
        add     esp, 4
        pushad
        call    applyBreaks
        popad
        popfd
        ret

; ---------------------------------------------------------------------------
Interrupt_Hook:
        DBGBRK  4, 3
        call    Save_CPU_Registers

        mov     edi, [ebp].R_Fault      ;ptr BreakInfoStru

        ; Backup client EIP to the INT xx instruction.
        mov     eax, [ebp].R_CS
        mov     ebx, [ebp].R_EIP
        call    Get_FlatAddress         ;ebx=linear address
        jc      short @f
        dec     ebx
        dec     ebx
        call    read_word_ax
        jc      short @f
        cmp     al, 0cdh
        jne     short @f
        cmp     ah, [edi].brk_IntNumber ;int number
        jne     short @f
        sub     [ebp].R_EIP, 2          ;backup to the int xx
@@:
        call    Evaluate_BreakCondition
        jnc     short break_On_This_Int

        call    Remove_IntBreak         ;restores int vector
        ; Setup a Hw break at the int handler
        call    Single_Step_Once
        ; edi preserved.

        ; Restore the int breakpoint
        call    Apply_IntBreak

PUBPROC Return_After_Restore
        call    Restore_CPU_Registers
        add     esp, 4
IRet_Only:
        iretd

break_On_This_Int:
        call    Restore_CPU_Registers

        ; Create an int frame then push ptr BreakInfoStru
        push    cs
        push    OFFSET32 IRet_Only
        pushfd
        xchg    eax, [esp]
        xchg    eax, [esp+12]           ;ptr BreakInfoStru
        xchg    eax, [esp]

        call    Save_CPU_Registers
        ; Do a single stepped IRETD to return to the INT xx frame
        call    Single_Step_Once

        call    SPWIN_MouseTrap
        db      'INT Break',d_sub

; --------------------------------------------------------------------------
; In:   EBP = Saved Register frame
;       EDI = ptr BreakInfoStru
; Out:  CF  = 0: Break, 1:Skip
;       EDI = ptr BreakInfoStru

PUBPROC Evaluate_BreakCondition
        btr     dword ptr [edi].brk_Flags, BRK_HIT1_BIT
        jc      short eval_SkipBreak

PUBPROC Evaluate_BreakConditionNoHit
        ; evaluate the expression
        lea     esi, [edi].brk_Condition
        cmp     byte ptr [esi], 0
        je      short eval_CountBreak
        call    Scan_Expression
        jc      short eval_SkipBreak
        test    ebx, ebx
        jz      short eval_SkipBreak
eval_CountBreak:
        dec     [edi].brk_Counter
        jnz     short eval_SkipBreak
        ; Break now
        mov     ax, [edi].brk_MaxCount
        mov     [edi].brk_Counter, ax
        or      [edi].brk_Flags, BRK_HIT1
        ; CF=0
        ret
eval_SkipBreak:
        stc
        ret

; --------------------------------------------------------------------------
; IN:   ebx = linear address
;       ch  = break types (BRKTYPE_I3 OR BRKTYPE_DRX)
; OUT:  CF  = 0 if found
;       edi = address of breakInfoStru
;       cl  = break#
PUBPROC FindCodeBreak
        mov     edi, OFFSET32 breakTable
        DBGBRK  3
        mov     cl, 0
findBreak1:
        inc     ecx                     ; break #
        test    [edi].brk_Flags, BRK_INUSE
        jz      short findBreak2
        test    [edi].brk_TypeInfo, ch
        jz      short findBreak2
IFDEF   _W95_
        cmp     ebx, [edi].brk_LinAddress
        jne     short findBreak2
        test    ebx, 0ffc00000h
        jz      short findBreak3        ; if ebx <  00400000h
        js      short findBreak3        ; if ebx >= 80000000h
        ; Only soft breaks use context
        test    [edi].brk_TypeInfo, BRKTYPE_I3
        jz      short findBreak3
        mov     eax, CurMemoryContext
        cmp     eax, [edi].brk_MemContext
        je      short findBreak3
ELSE
        cmp     ebx, [edi].brk_LinAddress
        je      short findBreak3
ENDIF
findBreak2:
        add     edi, BreakInfoSize
        cmp     cl, TOTAL_BREAKS
        jb      short findBreak1
        stc
findBreak3:
        ret

; --------------------------------------------------------------------------
; IN:   edx:ebx = address
;       al  = break type
;       ah  = flags
; OUT:  CF  = 0 if found
;       edi = address of breakInfoStru
;       ecx = break number
PUBPROC FindUnusedBreak
        DBGBRK  3
        mov     edi, OFFSET32 breakTable
        xor     ecx, ecx
addBreak1:
        inc     ecx                     ;break number
        test    [edi].brk_Flags, BRK_INUSE
        jz      short SetupBreak
        add     edi, BreakInfoSize
        cmp     ecx, TOTAL_BREAKS
        jb      short addBreak1
        stc
        ret

PUBPROC SetupBreak
        mov     [edi].brk_Address[0], ebx
        mov     [edi].brk_Address[4], edx
        mov     [edi].brk_MaxCount, 1   ;default count
        mov     [edi].brk_Counter, 1    ;default count
        mov     [edi].brk_Flags, ah
        mov     [edi].brk_TypeInfo, al
        mov     [edi].brk_Condition[0], 0 ;0=no expression
        ret

; --------------------------------------------------------------------------
PUBPROC applyBreaks
        DBGBRK  3
        mov     edi, OFFSET32 breakTable
applyBreakLoop:
        test    [edi].brk_Flags, BRK_ACTIVE
        jz      short @f

        call    Apply_Break

@@:     add     edi, BreakInfoSize
        cmp     edi, OFFSET32 breakTable + TOTAL_BREAKS*BreakInfoSize
        jb      short applyBreakLoop
        ret

; --------------------------------------------------------------------------
; In:   CL = flags for release (BRK_TEMP)
;       CH = flags to clear
PUBPROC removeBreaks
        DBGBRK  3
        mov     edi, OFFSET32 breakTable + TOTAL_BREAKS*BreakInfoSize
rmvBreakLoop:
        sub     edi, BreakInfoSize
        test    [edi].brk_Flags, BRK_INUSE
        jz      short @f

        push    ecx
        call    Remove_Break
        pop     ecx
        jc      short rmvBreakNext      ; do not free if failed

@@:     test    [edi].brk_Flags, cl     ; remove BRK_TEMP?
        jz      short @f
        mov     [edi].brk_Flags, 0      ; Free it
@@:     and     [edi].brk_Flags, ch     ; mainly for BRK_HIT1
rmvBreakNext:
        cmp     edi, OFFSET32 breakTable + BreakInfoSize
        jae     short rmvBreakLoop

        DBGBRK  3
        mov     edi, OFFSET32 DR_BreakPtr
        xor     eax, eax
        stosd                           ; mov     DR_BreakPtr[0], eax
        stosd                           ; mov     DR_BreakPtr[4], eax
        stosd                           ; mov     DR_BreakPtr[8], eax
        stosd                           ; mov     DR_BreakPtr[12], eax
        stosd                           ; mov     DR3_BreakAddress, eax
        mov     DR6, eax
        mov     DR7, eax
        ret

; --------------------------------------------------------------------------
; In:   ESI = ptr command line
;       EDI = ptr default address
PUBPROC GetBreakPointAddress
        DBGBRK  3
        mov     ebx, [edi+0]
        mov     edx, [edi+4]
        call    Skip_Blanks
        jz      short @f
        call    Scan_AddressDS
        jc      addressError
@@:     call    GetBreakPointCondition
IFDEF   _W95_
        mov     eax, CurMemoryContext
        mov     [edi].brk_MemContext, eax
ENDIF
        mov     ebx, [edi].brk_Address[0]
        mov     eax, [edi].brk_Address[4]
        call    Get_FlatAddress         ;ebx=linear address
        jc      addressError
        mov     [edi].brk_LinAddress, ebx
        ret

; --------------------------------------------------------------------------
; In:   ESI = ptr command line
;       EDX:EBX = breakpoint address
PUBPROC GetBreakPointCondition
        DBGBRK  3
        xor     eax, eax                ; we set the type later
        call    FindUnusedBreak
        jc      short all_breaks_used
        ; EDI points to breakpoint struc

        call    Skip_Blanks
        jz      short cond_done
        mov     ax, [esi]
        or      al, 20h
        xor     ax, 3d6eh               ; n=
        jnz     short @f
        inc     esi
        inc     esi
        call    Scan_Decimal            ;get the count
        jc      syntaxError
        mov     [edi].brk_MaxCount, bx
        mov     [edi].brk_Counter, bx
        call    Skip_Blanks
        jz      short cond_done
@@:     push    esi
        call    Scan_Dword              ;check syntax
        call    CheckLineEnd            ;end of line?
        pop     esi
        lea     eax, [edi].brk_Condition
        xchg    edi, eax
        mov     ecx, 30
        rep     movsb
        xchg    edi, eax
cond_done:
        ret

all_breaks_used:
        reportError 'All Breakpoints Used.'

; NOTE: All registers except EAX should be restored by this routine.
PUBPROC Restore_Int_Controller
        btr     dword ptr SP_flags, SP_PIC_OFF_BIT
        jnc     short @f
        mov     al, SS1_PICMask
        out     21h, al
@@:     ret

; --------------------------------------------------------------------------
; INT 3 Break support
; --------------------------------------------------------------------------
IFDEF   _W95_

CheckP32ModuleBreak:
        mov     eax, [ebp].R_EAX        ; address of the entrypoint
        mov     [ebp].R_EIP, eax        ; eax is the address for the module

        push    eax                     ; PARAM1=entry address
        call    CheckP32ModuleFromEntryPoint ; get the owner for this address
        pop     eax
        DBGBRK  3
        jc      Return_After_Restore
        ; ebx points to modulename.ext
        push    ebx
        call    Log_Exec32
        pop     ebx

        mov     edx, OFFSET32 breakTable
chkModBreakLoop:
        test    [edx].brk_Flags, BRK_ACTIVE
        jz      short @f
        test    [edx].brk_TypeInfo, BRK_ON_MOD
        jz      short @f

        lea     edi, [edx].brk_ModuleName ; (lstring)
        mov     cl, [edi]
        inc     edi
        mov     esi, ebx                ; ptr module.ext
        call    strncmp
        jc      short @f
        cmp     al, '.'
        je      short break_on_mod_load

@@:     add     edx, BreakInfoSize
        cmp     edx, OFFSET32 breakTable + TOTAL_BREAKS*BreakInfoSize
        jb      short chkModBreakLoop
        jmp     Return_After_Restore

ENDIF
break_on_mod_load:
        call    SPWIN_MouseTrap
        db      'Module Break',d_sub

break_On_Int03:
        cmp     [edi].brk_TypeInfo, BRK_ON_MOD
        je      short break_on_mod_load
        call    SPWIN_MouseTrap
        db      'Break Hit',d_sub

PUBPROC Int03_Handler
        DBGBRK  3
        pushfd                          ;as R_Fault (becomes int#)
        call    Save_CPU_Registers
        mov     eax, [ebp].R_CS
        mov     ebx, [ebp].R_EIP
        dec     ebx                     ;back 1 for INT 3
IFDEF   _W95_
        cmp     eax, Kernel32_CodeSelector
        jne     short @f
        dw      0fb81h          ;cmp ebx,xxxx
PUBDWRD Kernel32_LoaderHookAddr 10abcfh
        je      CheckP32ModuleBreak
@@:
ENDIF
        call    Get_FlatAddress         ;ebx=linear address
IF      DBG
        jnc     short @f
        DBGBRK  1
        DBGBRK  1
@@:
ENDIF
        mov     ch, BRKTYPE_I3 + BRKTYPE_MOD ; BRK_INT3 or BRK_ON_MOD
        call    FindCodeBreak
        jc      short PrevInt03         ;not in our active list
        test    [edi].brk_Flags, BRK_ACTIVE
        jz      short PrevInt03         ;not active?

        ; One of our breaks
        dec     [ebp].R_EIP             ;backup for INT 03

        test    [edi].brk_Flags, BRK_TEMP
        jnz     Temp_Break_Hit

        mov     byte ptr [ebp].R_Fault, cl ;breakpoint#
        call    Evaluate_BreakCondition
        jnc     short break_On_Int03

        ; Restore the instruction
        call    Remove_Int3Break
        jc      short @f
        call    Single_Step_Once
        ; Restore the breakpoint
        call    Apply_Int3Break
@@:     call    Restore_CPU_Registers
        add     esp, 4                  ;remove dummy R_Fault
        iretd

PrevInt03:
        test    byte ptr int_flags, 8   ;I3HERE?
        jnz     short Embeded_Int03
        call    Restore_CPU_Registers
        popfd                           ;R_Fault also restore flgs
        db 0eah
PrevInt03Vector dd OFFSET32 Int03_Handler, 0ee000000h

Embeded_Int03:
        call    SPWIN_MouseTrap
        db      'Embeded INT 3',d_sub

; --------------------------------------------------------------------------

; --------------------------------------------------------------------------
PUBPROC Single_Step_Once

        mov     SS1_Context, edi

        in      al, 21h
        mov     SS1_PICMask, al

        mov     ebx, [ebp].R_EIP
        mov     eax, [ebp].R_CS
        DBGBRK  3
        call    Get_FlatAddress         ;ebx=linear address
        jc      short SS1_TraceIt

        DBGBRK  3
        call    TraceInstType
        ; It returns to the caller in special cases (emulated trace)
        DBGBRK  3
        jc      short SS1_TraceIt

        ; ebx = linear address
        mov     eax, 000000280h ;clear LEN, RW fields (1byte, inst)
        mov     DR3, ebx
        mov     DR7, eax
        jmp     short SS1_Go

SS1_TraceIt:
        or      byte ptr [ebp].R_EFLAGS[1], 1 ; Set TF=1
SS1_Go: call    Setup_Intr1_Here
        ; Disable all interrupts (using PIC)
        or      SP_flags, SP_PIC_OFF + SP_SS1BREAK ; Make sure we break on it
        mov     al, 0ffh                ;All INTs off
        out     21h, al

        pop     SS1_ReturnAddr
        call    Restore_CPU_Registers
        add     esp, 4                  ; remove dummy R_Fault
        iretd

Embeded_Int01:
        call    SPWIN_MouseTrap
        db      'Embeded INT 1',d_sub

normal_int1:
        test    byte ptr int_flags, 2   ;I1HERE?
        jnz     short Embeded_Int01
PrevInt01:
        call    Restore_CPU_Registers
        popfd                           ;R_Fault also restore flgs
        db      0eah
PrevInt01Vector dd 0,0

Int01_SS1Break:
        xor     eax, eax
        mov     DR7, eax
        mov     DR6, eax
        mov     DR3, eax
        and     byte ptr [ebp].R_EFLAGS[1], not 1 ; TF=0 (trace off)
        ; Restore int controller
        call    Restore_Int_Controller
        mov     edi, SS1_Context
        jmp     SS1_ReturnAddr

; --------------------------------------------------------------------------
; INT 01 support
; --------------------------------------------------------------------------
PUBPROC Int01_Handler
        pushfd                          ;as R_Fault
        call    Save_CPU_Registers
        btr     dword ptr SP_flags, SP_SS1BREAK_BIT ; Did I do that?
        jc      short Int01_SS1Break
        btr     dword ptr SP_flags, SP_CLIENT_BIT ; Client break?
        jc      short Client_Break

        mov     eax, DR6                ;[...bt,bs,bd,...,b3,b2,b1,b0]
        DBGBRK  3, 3
        test    al,0fh                  ;any of B0-B3?
        jnz     short hw_break_trap
        shl     ah, 1
        jc      short task_break        ;BT (Task switch break bit 7)?
        jns     short normal_int1       ;if its a normal int 1
        ;Single step break (BS=bit6)

        test    SP_flags, SP_I1ON       ;do we take care of it?
        jz      short PrevInt01         ;no, let others take care of it
task_break:
Client_Break:                           ;or 'GC' command
Temp_Break_Hit:
        xor     eax, eax
        mov     DR6, eax
        mov     DR7, eax
        call    SPWIN_MouseTrap
        db      d_sub

hw_break_trap:
        DBGBRK  3, 3
        ; Is it a temp DR3 break?
        test    al, 8
        jz      short @f
        mov     edi, DR3
        cmp     edi, DR3_BreakAddress
        je      Temp_Break_Hit
@@:
        ; Find the break for this DR
        DBGBRK  3, 3
        bsf     ecx, eax
        mov     edi, DR_BreakPtr[ecx*4] ;ptr BreakInfoStru
        test    edi, edi
        jz      PrevInt01

        cmp     [edi].brk_TypeInfo, BRK_CAP_IO
        je      short Cap_IOBreak

        cmp     [edi].brk_TypeInfo, BRK_ON_EXEC
        jne     short @f
        or      byte ptr [ebp].R_EFLAGS[2], 1 ;set resume flag (RF)
@@:
        call    Evaluate_BreakConditionNoHit
        DBGBRK  3, 3
        jc      NextInt01
        call    SPWIN_MouseTrap
        db      'H/w Break Hit',d_sub

Cap_IOBreak:
        DBGBRK  3, 3
        ; Find operation type (IN/OUT)
        mov     ebx, [ebp].R_EIP
        mov     eax, [ebp].R_CS
        ; eax:ebx=instruction address
        call    Get_FlatAddress         ;ebx=linear address
        DBGBRK  2
        jc      short NextInt01

        xor     eax, eax
        call    read_byte_al_m1         ; al = ds:[ebx-1]
        jc      short NextInt01

        DBGBRK  1, 3
        cmp     eax, [edi].brk_Address  ; same as port address?
        jne     short cap_ChkOpcode     ; should be the opcode

        dec     ebx                     ; back up the port number
        call    read_byte_al_m1         ; al = ds:[ebx-1]
        jc      short NextInt01
cap_ChkOpcode:
        mov     esi, cap_Length
        cmp     esi, DosInfo.capBufSize ; number of captures (qwords)
        jae     short NextInt01
        shl     esi, 3                  ; *8
        add     esi, CapBuffer_Beg

        mov     ecx, [edi].brk_Address[4] ; port index number (0..2)
        and     ecx, 3                  ; better be sure
        mov     edx, [ebp].R_EAX
        mov     cap_PortVal[ecx+1], dl  ; byte 1,2,3

        ; e4/e5/e6/e7 (in/out b/w xx)
        ; 6c/6d/6e/6f (ins/outs b/w)
        ; ec/ed/ee/ef (in/out b/w dx)
        and     eax, 2                  ; 0=IN, 2=OUT
        shl     al, 1                   ; 0=IN, 4=OUT
        or      eax, dword ptr cap_PortVal ;
        or      al, cl                  ; AL=[III00Wnn]
        mov     [esi], eax
        mov     al, 20h
        shl     al, cl                  ; AL=[III00000] (new)
        or      cap_PortVal, al

        VMMcall Get_System_Time
        mov     [esi+4], eax            ;msec since windows started

        inc     cap_Length
NextInt01:
        xor     eax, eax
        mov     DR6, eax
        call    Restore_CPU_Registers
        add     esp, 4                  ;remove dummy R_Fault
        iretd

PUBPROC NMI_Handler
        DBGBRK  3
        pushfd                          ;as R_Fault
        call    Save_CPU_Registers
        test    byte ptr int_flags, 4   ;I2HERE?
        jz      short Prev_NMIHandler
        call    SPWIN_MouseTrap
        db      'NMI',d_sub

Prev_NMIHandler:
        call    Restore_CPU_Registers
        popfd                           ;R_Fault also restore flags
        db 0eah
PrevNMIVector dd OFFSET32 NMI_Handler, 0ee000000h

; --------------------------------------------------------------------------
bad_vector:
        reportError 'Bad Int Number.'

PUBPROC Cmd_IntBreak
        DBGBRK  3
        movzx   eax, bl
        cmp     eax, ebx
        jnz     bad_vector

        or      al, 3
        cmp     al, 3                   ; int 1-3?
        je      short I1_I3_Enable

        bt      int_flags, ebx
        jc      short break_is_there

        ; no need for any address to save
        push    ebx
        call    GetBreakPointCondition
        pop     ecx
        mov     [edi].brk_IntNumber, cl
        mov     [edi].brk_Flags, BRK_INUSE + BRK_ACTIVE
        mov     [edi].brk_TypeInfo, BRK_ON_INT
Enable_Int_Break:
        bts     int_flags, ecx
        ret

break_is_there:
        reportError 'Break Already Set.'

PUBPROC Cmd_NMIBreak
        push    2                       ; 2 for NMI
        pop     ebx
I1_I3_Enable:
        mov     ecx, ebx                ; 1, 2 or 3
        call    Parse_Line
        FullCmd 'ON'   JUMP_ADDRS  <OFFSET32 Enable_Int_Break>
        FullCmd 'OFF'  JUMP_ADDRS  <OFFSET32 Disable_Int_Break>
        db 0
        btc     int_flags, ecx
        setnc   al
        push    eax
        push    ecx
        call    PrintfMainScr
        db      d_lf,'Break On INT ',d_h04,' Is Now '
        _table  ON_OFF_Table
        db      d_el
        ret

Disable_Int_Break:
        btr     int_flags, ecx
        ret

Walk_Breaks:
        mov     ebx, OFFSET32 breakTable
        xor     edi, edi
walkBreak1:
        inc     edi                     ; break #
        test    [ebx].brk_Flags, BRK_INUSE
        jnz     short walkBreak3
walkBreak2:
        add     ebx, BreakInfoSize
        cmp     edi, TOTAL_BREAKS
        jb      short walkBreak1
        ret

walkBreak3:
        loop    short walkBreak2
        ret

mem_break_types db 2
        db      'X '  ; 8:BPX - break on excution        BRK_ON_EXEC
        db      'IO'  ; 9:BPIO- break on port I/O        BRK_ON_PIO
        db      'BW'  ; a:BPB - break on byte read/write BRK_ON_BW
        db      'B '  ; b:BPB - break on byte write      BRK_ON_BRW
        db      'WW'  ; c:BPB - break on byte read/write BRK_ON_WW
        db      'W '  ; d:BPB - break on byte write      BRK_ON_WRW
        db      'DW'  ; e:BPB - break on byte read/write BRK_ON_DW
        db      'D '  ; f:BPB - break on byte write      BRK_ON_DRW

no_break_inuse:
        reportError 'No Breakpoint Set.'

PUBPROC Cmd_BreakList
        DBGBRK  3
        xor     ecx, ecx
        call    Walk_Breaks
        jecxz   short no_break_inuse
        neg     ecx
        push    ecx                     ;sl_limit
        push    0                       ;sl_index
        call    scrollLines
        ;         xx   BPIO  0000:00000000  Yes  BR1  C=n
        db      'No.   Type  Address',d_col,27,'Enabled',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        inc     ecx
        call    Walk_Breaks
        ; edi=break#
        movzx   eax, [ebx].brk_TypeInfo
        cmp     al, BRK_INT3            ;break type mask
        jne     short breakList1

        ; BP addr  ON/OFF  C=n

        push    dword ptr [ebx].brk_Address[0]
        push    dword ptr [ebx].brk_Address[4]
        push    edi                     ;break number
        call    Printf
        db      ' ',d_deci,d_col,6,'BP    ',d_h48,d_ret
        jmp     breakList4

breakList1:
        test    al, BRKTYPE_DRX         ; BRK_ON_EXEC
        jz      short breakList2

        cmp     al, BRK_ON_PIO
        je      short breakList_BPIO
        cmp     al, BRK_CAP_IO
        je      short breakList_BPIO
        ; BPxx addr ON/OFF  DRn  C=n

        push    dword ptr [ebx].brk_Address[0]
        push    dword ptr [ebx].brk_Address[4]
        sub     al, BRK_ON_EXEC
        push    eax                     ;break type
        push    edi                     ;break number
        call    Printf
        db      ' ',d_deci,d_col,6,'BP'
        _table  mem_break_types
        db      '  ',d_h48,d_ret
        jmp     short breakList4

breakList_BPIO:
        ; BPIO port ON/OFF  DRn  C=n

        push    dword ptr [ebx].brk_Address[0]
        push    edi                     ;break number
        call    Printf
        db      ' ',d_deci,d_col,6,'BPIO  ',d_h16,d_ret
        jmp     short breakList4

breakList2:
        cmp     al, BRK_ON_INT
        jne     short breakList3

        ; BI   nn   ON/OFF C=n

        push    dword ptr [ebx].brk_IntNumber ;int number
        push    edi                     ;break number
        call    Printf
        db      ' ',d_deci,d_col,6,'BI    INT=',d_h08,d_ret
        jmp     short breakList4

breakList3:
        test    al, BRKTYPE_IO          ; BRK_ON_IO
        jz      short breakList6

        ; BIO port ON/OFF N=n <exp>

        push    [ebx].brk_Address[0]    ;port number
        push    edi                     ;break number
        call    Printf
        db      ' ',d_deci,d_col,6,'BIO   Port=',d_h16,d_ret
breakList4:
        movzx   esi, [ebx].brk_MaxCount
        push    esi                     ;break count
        push    dword ptr [ebx].brk_Flags ;_bits (BRK_ACTIVE)
        push    0                       ;a_b mask for _bits
        lea     ebx, [ebx].brk_Condition
        call    PrintfAt
        db      d_col,27
        _bits   BRK_ACTIVE+BRK_APPLY,3,'No Yes    + '
        db      d_col,37,'N=',d_deci,d_col,46,d_text,30,d_ret
breakList5:
        ret

breakList6:
        cmp     al, BRK_ON_MOD
        jne     short breakList5

        ; BM module ON/OFF  C=n

        push    dword ptr [ebx].brk_Flags ;_bits (BRK_ACTIVE)
        push    0                       ;a_b mask for _bits
        lea     ebx, [ebx].brk_ModuleName[1]
        push    edi                     ;break number
        call    Printf
        db      ' ',d_deci,d_col,6,'BM    ',d_text,8
        db      d_col,27
        _bits   BRK_ACTIVE+BRK_APPLY,3,'No Yes    + '
        db      d_ret
        ret

PUBPROC Cmd_BreakEnable
        DBGBRK  3
        call    Loop_On_Breaks
        ; will be called with ebx=break#, edx pointing to the break struc
        or      [edx].brk_Flags, BRK_ACTIVE
        ret

PUBPROC Cmd_BreakDisable
        DBGBRK  3
        call    Loop_On_Breaks
        ; will be called with ebx=break#, edx pointing to the break struc
        and     [edx].brk_Flags, not BRK_ACTIVE
        ret

PUBPROC Cmd_BreakClear
        DBGBRK  3
        call    Loop_On_Breaks
        ; will be called with ebx=break#, edx pointing to the break struc

        test    [edx].brk_Flags, BRK_APPLY
        jnz     short cannot_remove     ; Do not clear it if still applied
        mov     [edx].brk_Flags, 0      ; clear break
        ; BC <n>, if int break
        mov     al, [edx].brk_TypeInfo
        cmp     al, BRK_ON_INT
        je      short clr_int_break

        ; BC <n>, if hw breaks, release
        test    al, BRKTYPE_DRX         ; BRK_ON_EXEC+
        jz      short @f
        mov     cl, [edx].brk_DR7Value  ; sstt00nn
        and     ecx, 3
        bts     HwBreak_Flags, ecx
@@:     ret

clr_int_break:
        movzx   eax, byte ptr [edx].brk_IntNumber ;int number
        btr     int_flags, eax
        ret

cannot_remove:
        inc     ebx                     ; break number (1-base)
        push    ebx
        dec     ebx                     ; back to 0-base
        call    Printf
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,' BP<',d_deci,'> Not Accessible. '
        db      'Release anyway (y/n)?',d_clreol,d_el
@@:     call    key_read
        cmp     al, K_ESC
        je      short codewin_then_menu
        or      al, 20h
        cmp     al, 'n'
        je      short @f
        xor     al, 'y'
        jnz     short @b
        mov     [edx].brk_Flags, al     ; clear break
        cmp     [edx].brk_TypeInfo, BRK_ON_INT
        jne     short @f
        movzx   ecx, [edx].brk_IntNumber ;int number
        btr     int_flags, ecx
@@:     ret

; In:   Pushed address of break service
;       Pushed address will be called with ebx=break#, edx=break struc
PUBPROC Loop_On_Breaks
        DBGBRK  3
        cmp     al, '*'
        jne     short loopBreakNum

        xor     ebx, ebx
loopBreakAll1:
        imul    edx, ebx, BreakInfoSize
        add     edx, OFFSET32 breakTable
        test    [edx].brk_Flags, BRK_INUSE
        jz      short loopBreakAll2
        call    dword ptr [esp]         ; break service procedure
loopBreakAll2:
        inc     ebx
        cmp     ebx, TOTAL_BREAKS
        jb      short loopBreakAll1
PUBPROC codewin_then_menu
        mov     al, SF_CODE
        jmp     Update_Screen

loopBreakNext:
        push    esi
        call    dword ptr [esp+4]       ; break service procedure
        pop     esi
loopBreakNum:
        call    Scan_Decimal
        jc      short codewin_then_menu
        dec     ebx
        cmp     ebx, TOTAL_BREAKS
        jae     short bad_break_num
        imul    edx, ebx, BreakInfoSize
        add     edx, OFFSET32 breakTable
        test    [edx].brk_Flags, BRK_INUSE
        jnz     short loopBreakNext
        reportError 'Break Number Not Used.'

bad_break_num:  
        reportError 'Invalid Break.'

PUBPROC Cmd_Zap
        DBGBRK  3
        mov     ebx, currentInst
        dec     ebx
        call    read_byte_al
        cmp     al, 0cch                ;INT 03?
        je      short zap_Int3
        and     al, not 2               ;3 => 1
        mov     ah, al
        dec     ebx
        call    read_byte_al
        cmp     ax, 01cdh               ;INT 01/INT 03?
        jne     short bad_zap
        mov     al, 90h                 ;NOP
        call    write_byte_al
        inc     ebx
zap_Int3:
        mov     al, 90h                 ;NOP
        call    write_byte_al
        jmp     codewin_then_menu
bad_zap:
        reportError 'No INT 1 or INT 3 Here.'

PUBPROC Cmd_CodeBreak
        DBGBRK  3
        mov     edi, OFFSET32 Code_Data_Ptrs[PNTR_CODE]  ;ptr default address
        call    GetBreakPointAddress

        push    edi
        mov     ch, BRKTYPE_I3 ; OR BRKTYPE_DRX
        call    FindCodeBreak
        pop     edi
        jnc     break_is_there

        mov     al, 0cch
        call    xchg_byte_al
        jc      short no_break_here
;       mov     [edi].brk_I3OrgInst, al
        call    xchg_byte_al
        cmp     al, 0cch
        jne     short no_break_here

        mov     [edi].brk_TypeInfo, BRK_INT3
        mov     [edi].brk_Flags, BRK_INUSE + BRK_ACTIVE
        jmp     codewin_then_menu

no_break_here:
        reportError 'Cannot Set Break Here.'

PUBPROC Cmd_HwBreak
        DBGBRK  3
        bsf     ecx, HwBreak_Flags
        jz      short breaks_used       ; any break available?
        or      al, cl                  ; al=sstt00nn, ah=BRK_ON_xxx
        push    eax
        mov     edi, OFFSET32 Code_Data_Ptrs[PNTR_DATA]
        test    al, 0f0h
        jnz     short @f
        add     edi, PNTR_CODE - PNTR_DATA ; edi= OFFSET32 Code_Data_Ptrs[PNTR_CODE]
@@:     call    GetBreakPointAddress
        pop     eax                     ; al=sstt00nn, ah=BRK_ON_xxx
        mov     [edi].brk_TypeInfo, ah
        mov     [edi].brk_DR7Value, al  ; al=sstt00nn
        mov     [edi].brk_Flags, BRK_INUSE + BRK_ACTIVE
        and     eax, 3
        btr     HwBreak_Flags, eax
        jmp     codewin_then_menu

breaks_used:    
        reportError 'All Hardware Breaks Used.'

PUBPROC Cmd_ModBreak
        jz      syntaxError
        ; ESI points to the module name
        DBGBRK  3
        mov     ah, BRK_INUSE + BRK_ACTIVE
        mov     al, BRK_ON_MOD
        call    FindUnusedBreak
        jc      all_breaks_used

        ; EDI points to breakpoint struc
        push    -1
        pop     [edi].brk_LinAddress

        call    GetSymbolLen
        lea     edi, [edi].brk_ModuleName
        and     ecx, 15                 ; make sure not too big
        mov     al, cl
        stosb                           ; length for name
        rep     movsb                   ; copy the module name
        mov     [edi], ch
is_client_code:
        ret

PUBPROC Cmd_GoClient
        test    byte ptr [ebp].R_CS, 3  ; Ring 0?
        jnz     short is_client_code
        call    Break_In_Client_Code
        jmp     short SPWIN_Return

PUBPROC Cmd_GoFault
        or      SP_flags, SP_EXEC_FLT
        jmp     short SPWIN_Return

PUBPROC Cmd_Go
        DBGBRK  3
;       test    al, al
        jz      short SPWIN_Return
        cmp     al,'='
        je      short startAt
        call    Scan_AddressCode
        jc      addressError
        cmp     al, 0
        je      short Stop_At_Address
        jmp     addressError

startAt:
        inc     esi
        call    Scan_AddressCode
        jc      addressError
        cmp     al, 0
        jne     addressError
        push    edx
        push    ebx
        xchg    eax, edx
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      addressError
        pop     [ebp].R_EIP
        pop     [ebp].R_CS

PUBPROC SPWIN_Return
        DBGBRK  3
        test    ScreenFlags, SF_NOSWAP
        jnz     short Return_1
        call    Usr_Screen
Return_1:
        mov     esi, ebp
        mov     edi, OFFSET32 PrevRegs
        mov     ecx, 19
        rep     movsd

        call    applyBreaks
        and     SP_flags, not SP_ACTIVE
        call    Restore_CPU_Registers
        add     esp, 4                  ;remove R_Fault
        iretd

PUBPROC Cmd_Step
        mov     ebx, currentInst
        mov     ecx, [ebp].R_CS         ;to get the oprand size
        call    stepIns
        jnc     short start_trace1
; ebx = linear address for break point.
        sub     ebx, currentInst        ;length of instruction
        add     ebx, [ebp].R_EIP        ;esi=offset of next instruction
        mov     edx, dword ptr [ebp].R_CS
Stop_At_Address:
        mov     ah, BRK_TEMP
        mov     al, BRK_INT3
        call    FindUnusedBreak
        jc      short SetHwBreak2
        xchg    eax, edx
        call    Get_FlatAddress         ;ebx=linear address
        jc      addressError
        call    Apply_Int3Break
        jc      short SetHwBreak1
        or      [edi].brk_Flags, BRK_INUSE + BRK_ACTIVE
        jmp     SPWIN_Return

SetHwBreak1:
        mov     ebx, [edi].brk_Address[0]
        mov     edx, [edi].brk_Address[4]
SetHwBreak2:
        xchg    eax, edx
        call    Get_FlatAddress         ;ebx=linear address
        jc      addressError
        mov     eax, 000000280h ;clear LEN, RW fields (1byte, inst)
        mov     DR3_BreakAddress, ebx
        mov     DR3, ebx
        mov     DR7, eax
        call    Setup_Intr1
        jmp     SPWIN_Return

PUBPROC Cmd_Trace
        jnc     short set_traceCount
start_trace1:   
        mov     bx, 1                   ;default: T1
set_traceCount: 

        ; Since we do not apply breaks during trace, we should clear
        ; the BRK_HIT1 state
        mov     edi, OFFSET32 breakTable
@@:     and     [edi].brk_Flags, not BRK_HIT1
        add     edi, BreakInfoSize
        cmp     edi, OFFSET32 breakTable + TOTAL_BREAKS*BreakInfoSize
        jb      short @b
        or      byte ptr [ebp].R_EFLAGS[2], 1 ;set resume flag (RF)

        mov     esi, ebp
        mov     edi, OFFSET32 PrevRegs
        mov     ecx, 19
        rep     movsd
        movzx   edi, bx                 ;traceCount
@@:     or      ScreenFlags, SF_NOSWAP
        call    Single_Step_Once
        dec     edi
        jnz     short @b

        call    SPWIN_MouseTrap
        db      d_sub

; --------------------------------------------------------------------------
PUBPROC SPWIN_MouseTrap
        pop     [ebp].R_BrkMsg
        or      SP_flags, SP_ACTIVE
        and     SP_flags, not (SP_I1ON + SP_SS1BREAK + SP_EXEC_FLT)
        and     byte ptr [ebp].R_EFLAGS[1], not 1 ; TF=0
        and     byte ptr PrevRegs.R_EFLAGS[1], not 1 ; TF=0

        call    Restore_Int_Controller

        mov     cl, BRK_TEMP            ; free temp breaks
        mov     ch, 0ffh                ; keep BRK_HIT1 state
        call    removeBreaks

        ; save current screen, setup screen

        btr     dword ptr ScreenFlags, SF_NOSWAP_BIT
        jc      short @f
        call    SPW_Screen
@@:     call    CollectKernelInfo
        jmp     Init_AllWindows

; --------------------------------------------------------------------------
; I/O break supports
; --------------------------------------------------------------------------
; In:   EDX = Port address
; Out:  CF=0 :  Found, ebx=ptr TSS:IO_MAP
;       CF=1 :  Not found
PUBPROC FindIoBreak
        DBGBRK  3
        mov     edi, OFFSET32 breakTable
findIoBreak1:
        test    [edi].brk_Flags, BRK_ACTIVE
        jz      short findIoBreak2
        cmp     [edi].brk_TypeInfo, BRK_ON_IO
        jne     short findIoBreak2
        DBGBRK  3
        cmp     dx, word ptr [edi].brk_Address[0] ;port number
        je      short findIoBreak3
findIoBreak2:
        add     edi, BreakInfoSize
        cmp     edi, OFFSET32 breakTable + TOTAL_BREAKS*BreakInfoSize
        jb      short findIoBreak1
        stc
findIoBreak3:
        ret

badSelector:    reportError 'Invalid Selector.'

; In:   bx  = selector
; Out:  bx  = selector
;       eax = base address
;       edx = limit
;       esi = ptr descriptor
;       edi = io map offset
get_TSSInfo:
        movzx   eax, bx
        call    Get_Selector
        jc      badSelector
        ; eax = base address
        ; edx = limit
        ; esi = ptr descriptor
        mov     cl, 1dh                 ;ignore busy bit
        and     cl, [esi].AccessRights
        cmp     cl, 9                   ;386-TSS?
        jne     badSelector
        cmp     edx, 68h                ;minimum limit
        jb      badSelector
        movzx   edi, [eax].TSS_IOPORTS
        ret

Capture_IO:
        DBGBRK  3
        movzx   edx, bx
        xor     edx, ebx
        jnz     valueError
        mov     ah, 0 ;; BRK_INUSE + BRK_ACTIVE
        mov     al, BRK_CAP_IO
        call    FindUnusedBreak
        jc      all_breaks_used
        ; edi = break info
        ; ecx = break number

        DBGBRK  3
        bsf     eax, HwBreak_Flags
        jz      breaks_used             ; any break available?
        btr     HwBreak_Flags, eax
        mov     DR_BreakPtr[eax*4], edi
        or      al, 20h                 ; al=sstt00nn
        mov     [edi].brk_DR7Value, al  ; al=sstt00nn
        mov     [edi].brk_Flags, BRK_INUSE + BRK_ACTIVE
        ret

; --------------------------------------------------------------------------
PUBPROC Cmd_IoBreak
        DBGBRK  1
        jc      syntaxError
        push    ebx
        call    GetBreakPointCondition
        pop     ebx
        movzx   edx, bx
        cmp     edx, ebx
        jne     valueError

        DBGBRK  3
        push    edi
        ; Do we have a similiar break?
        call    FindIoBreak
        jnc     break_is_there
        pop     edi
        mov     [edi].brk_TypeInfo, BRK_ON_IO
        mov     [edi].brk_Flags, BRK_INUSE + BRK_ACTIVE
        ret

PUBPROC Cmd_Capture
        DBGBRK  3
        jz      Cmd_VuCap
        call    Parse_Line
        PartCmd 'START' ENDOF_LINE <OFFSET32 cap_Start>
        PartCmd 'STOP'  ENDOF_LINE <OFFSET32 cap_Stop>
;;      PartCmd 'PRINT' ENDOF_LINE <OFFSET32 cap_Print>
        db      0

        DBGBRK  1
        call    Scan_Dword
        push    esi
        call    cap_Stop                ;remove previous capture
        call    Capture_IO
;       mov     byte ptr [edi].brk_Address[4], 0 ;port index
        mov     cap_BreakNum[0], cl
        pop     esi
        mov     cap_Port[0], bx
        call    Scan_Expression
        jc      short cap_Start
        push    esi
        call    Capture_IO
        mov     byte ptr [edi].brk_Address[4], 1 ;port index
        mov     cap_BreakNum[1], cl
        pop     esi
        mov     cap_Port[2], bx
        call    Scan_Expression
        jc      short cap_Start
        call    Capture_IO
        mov     byte ptr [edi].brk_Address[4], 2 ;port index
        mov     cap_BreakNum[2], cl
        mov     cap_Port[4], bx
cap_Start:
        xor     eax, eax
        mov     cap_Length, eax
        mov     dword ptr cap_PortVal, eax ;reset all flags and values
        ret

cap_Stop:
        xor     esi, esi
        call    cap_Cancel
        call    cap_Cancel
cap_Cancel:
        movzx   edi, cap_BreakNum[esi]
        xor     ecx, ecx
        xchg    cx, cap_Port[esi+esi]
        jecxz   short cap_Can_Ret
        imul    edi, BreakInfoSize              ;1st=1
        add     edi, OFFSET32 breakTable-BreakInfoSize
        mov     cl, [edi].brk_DR7Value  ; sstt00nn
        and     ecx, 3
        bts     HwBreak_Flags, ecx      ; free DR
        mov     [edi].brk_Flags, ch     ; free break point
cap_Can_Ret:
        inc     esi
        ret

cap_States      db 'Ú½' ; 1 -> 0   'ÖÙ'
                db 'À·' ; 0 -> 1   'Ó¿'
                db '³ ' ; 0 -> 0   'º '
                db ' º' ; 1 -> 1   ' ³'

cap_Empty:
        reportError 'Capture Buffer Empty.'

PUBPROC Cmd_VuCap
        DBGBRK  4
        mov     ecx, cap_Length
        jecxz   short cap_Empty
        push    ecx                     ;sl_limit
        push    0                       ;sl_index
        push    dword ptr cap_Port[4]
        push    dword ptr cap_Port[2]
        push    dword ptr cap_Port[0]
        call    scrollLines
        db      d_col, 4,'Time'
        db      d_col,19,'PORT ',d_h16
        db      d_col,42,'PORT ',d_h16
        db      d_col,65,'PORT ',d_h16
        db      d_lf
        db      d_col, 3,'(msec)'
        db      d_col,16,'7 6 5 4 3 2 1 0'
        db      d_col,39,'7 6 5 4 3 2 1 0'
        db      d_col,62,'7 6 5 4 3 2 1 0'
        db      d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  4
        mov     esi, CapBuffer_Beg
        lea     ebx, [esi+edx*8]        ; ptr our data
                                        ; [P2:P1:P0:CC], [time]
                                        ; CC=[III..Onn]
                                        ; I =Initialized flags for 3 ports
                                        ; O =1:OUT, 0:IN
                                        ; nn=port number (0-2)
        mov     eax, [ebx][4]           ; time
        sub     eax, [esi][4]           ; reference is starting time
        push    eax                     ; Time
        call    Printf
        db      d_numb,NM_RJSPC+8,' ´ ',d_ret

;;      mov     edx, [ebx]
        mov     ch, 20h                 ; I-mask
        mov     cl, 8                   ; #shifts
        mov     dl, 0                   ; port number
        call    cap_Show_Port
        mov     ch, 40h                 ; I-mask
        mov     cl, 16                  ; #shifts
        mov     dl, 1                   ; port number
        call    cap_Show_Port
        mov     ch, 80h                 ; I-mask
        mov     cl, 24                  ; #shifts
        mov     dl, 2                   ; port number
;       call    cap_Show_Port
;       ret
cap_Show_Port:
        mov     eax, [ebx]
        xor     dl, al
        and     edx, 3
        je      short show_Newdata
        ; display previous info
        xor     edx, edx                ;delta=0
        test    ch, al                  ;initialized?
        mov     al, ' '                 ;I/O was from another port
        jnz     short show_Curdata

        ; undefined yet.
        call    PrintfAt
        db      '     ° ° ° ° ° ° ° °   ',d_ret
        ret

show_Newdata:
        test    ch, al                  ;initialized?
        jz      short show_CurFunc
        mov     edx, [ebx-8]            ;previous values
        xor     edx, eax                ;delta
        shr     edx, cl                 ;DL=bit pattern of prev
show_CurFunc:
        test    al, 4                   ;
        mov     al, 'i'
        jz      short show_Curdata
        mov     al, 'o'
show_Curdata:
        stosb                           ; 'i'/'o'/' '
        mov     al, ' '
        stosb
        shr     eax, cl                 ;AL=bit pattern of curr
        mov     dh, al                  ;DH=value, DL=delta
        call    hex_08
        mov     al, ' '
        stosb
        mov     ecx, 8
@@:     shl     dl, 1
        sbb     esi, esi
        shl     dh, 1
        adc     esi, esi
        mov     ax, word ptr cap_States[esi+esi+4]
        stosw
        loop    @b
        mov     al, ' '
        stosb
        stosb
        ret

PUBPROC Cmd_Tss
        DBGBRK  3
        jnc     short disp_ts1
        str     bx
disp_ts1:
        call    get_TSSInfo
        ; eax = base address
        ; edx = limit
        ; esi = ptr descriptor
        ; edi = io map offset

        DBGBRK  3
        lea     ecx, [edx-1]
        sub     ecx, edi
;;      jc      badSelector
        jae     short @f
        ; all i/o's are trapped.
        xor     ecx, ecx        ;no-i/o map
@@:     shr     ecx, 3          ;bytes to qwords
        add     edi, eax
        push    edi             ;(sl_context)
        push    ecx             ;(sl_limit)
        push    0               ;(sl_Index)

        push    dword ptr ds:[eax].TSS_BackLink
        push    dword ptr ds:[eax].TSS_EIP
        push    dword ptr ds:[eax].TSS_CS
        push    dword ptr ds:[eax].TSS_EFLAGS
        push    dword ptr ds:[eax].TSS_CR3
        push    dword ptr ds:[eax].TSS_LDT
        push    dword ptr ds:[eax].TSS_ESP
        push    dword ptr ds:[eax].TSS_SS
        push    dword ptr ds:[eax].TSS_GS
        push    dword ptr ds:[eax].TSS_EDX
        push    edx             ;limit
        push    dword ptr ds:[eax].TSS_ESP2
        push    dword ptr ds:[eax].TSS_SS2
        push    dword ptr ds:[eax].TSS_FS
        push    dword ptr ds:[eax].TSS_EBP
        push    dword ptr ds:[eax].TSS_ECX
        push    eax             ;base
        push    dword ptr ds:[eax].TSS_ESP1
        push    dword ptr ds:[eax].TSS_SS1
        push    dword ptr ds:[eax].TSS_ES
        push    dword ptr ds:[eax].TSS_EDI
        push    dword ptr ds:[eax].TSS_EBX
        push    ebx             ;selector
        push    dword ptr ds:[eax].TSS_ESP0
        push    dword ptr ds:[eax].TSS_SS0
        push    dword ptr ds:[eax].TSS_DS
        push    dword ptr ds:[eax].TSS_ESI
        push    dword ptr ds:[eax].TSS_EAX
        call    scrollLines
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        db      'EAX=', d_h32,'  ESI=', d_h32,'  DS=',d_h16
        db      '  SS:ESP0=',d_h16,':',d_h32,'  TSS=',d_h16
        db      d_lf,'EBX=', d_h32,'  EDI=', d_h32,'  ES=',d_h16
        db      '  SS:ESP1=',d_h16,':',d_h32,'  BASE=',d_h32
        db      d_lf,'ECX=', d_h32,'  EBP=', d_h32,'  FS=',d_h16
        db      '  SS:ESP2=',d_h16,':',d_h32,'  LIMIT=',d_h32
        db      d_lf,'EDX=', d_h32,d_spc,16,'GS=',d_h16
        db      '  SS:ESP =',d_h16,':',d_h32,'  LDT=',d_h16
        db      d_lf,'CR3=', d_h32,'  EFLAGS=',d_h32,d_spc,8
        db      'CS:EIP =',d_h16,':',d_h32,'  BACKLINK=',d_h16
        db      d_lf,'  Trapped   0',    d_spc,16,'1',   d_spc,16,'2',   d_spc,16,'3'
        db      d_lf,' I/O Ports  0123456789ABCDEF 0123456789ABCDEF 0123456789ABCDEF 0123456789ABCDEF'
        db      d_sub
        ; edx = ecx = port number
        DBGBRK  3
        lea     esi, [esi+ecx*8]
        or      eax, -1
        mov     edx, eax
        call    qword_read_@esi
        xchg    ebx, eax                ;edx:eax=64-bit i/o map
        shl     ecx, 6
        lea     eax, [ecx+3fh]
        push    eax
        push    ecx
        call    Printf
        db      ' ',d_h16,'-',d_h16,' ',d_ret
        mov     cl, 64
tss_bitMap1:
        test    cl, 0fh
        jnz     short tss_bitMap2
        mov     al, ' '
        stosb
tss_bitMap2:
        shr     edx, 1
        rcr     ebx, 1
        mov     al, '.'
        jnc     short tss_bitMap3
        mov     al, 'x'
tss_bitMap3:
        stosb
        loop    short tss_bitMap1
        ret

; --------------------------------------------------------------------------
; Watch Windows for changing the trapped I/O ports.
SPWIN_Enable_Global_Trapping:
        call    Prev_Enable_Global_Trapping
        pushad

enable_If_Trapped:
        call    FindIoBreak
        jc      short @f
        DBGBRK  3
        mov     [edi].brk_TssIoState, 1
        call    SetIoBitMap
@@:     popad
        ret

SPWIN_Disable_Local_Trapping:
        call    Prev_Disable_Local_Trapping
        pushad

        VMMcall Get_Cur_VM_Handle
        ; ebx = Cur_VM_Handle
        cmp     ebx, [esp].Pushad_EBX
        je      short disable_If_Trapped

        popad
        ret

SPWIN_Disable_Global_Trapping:
        call    Prev_Disable_Global_Trapping

        pushad

disable_If_Trapped:
        call    FindIoBreak
        jc      short @f
        DBGBRK  3
        mov     [edi].brk_TssIoState, 0
        call    SetIoBitMap
@@:     popad
        ret

IFDEF   _W95_
; In:   EAX = Old VM handle
;       EBX = Current VM handle
SPWIN_TaskSwitchCallBack:
        DBGBRK  3
        mov     edi, OFFSET32 breakTable
taskSwCall1:
        test    [edi].brk_Flags, BRK_ACTIVE
        jz      short taskSwCall2
        test    [edi].brk_TypeInfo, BRKTYPE_IO ; BRK_ON_IO
        jz      short taskSwCall2
        DBGBRK  3
        mov     edx, [edi].brk_Address[0] ;port number
        call    SetIoBitMap
taskSwCall2:
        add     edi, BreakInfoSize
        cmp     edi, OFFSET32 breakTable + TOTAL_BREAKS*BreakInfoSize
        jb      short taskSwCall1
        ret
ENDIF

SPWIN_Enable_Local_Trapping:
        call    Prev_Enable_Local_Trapping

        pushad

        VMMcall Get_Cur_VM_Handle
        ; ebx = Cur_VM_Handle
        cmp     ebx, [esp].Pushad_EBX
        je      short enable_If_Trapped

        popad
        ret

SetIoBitMap:
        DBGBRK  3
        str     ax
        call    Get_SelectorBase
        jc      short @f

        xchg    ebx, eax
        lea     esi, [ebx].TSS_IOPORTS
        call    word_read_@esi
        jc      short @f
        bts     [ebx+eax], edx
@@:     ret

; --------------------------------------------------------------------------
PUBPROC Break_In_Client_Code
        DBGBRK  3
        VMMcall Get_Cur_VM_Handle
        mov     ebx, [ebx + CB_Client_Pointer]
        ; Set the trace flag on the client EFLAGS
        or      byte ptr [ebx].Client_EFlags[1], 1 ; TF=1
        ; Let the int01 handler know about this
        or      SP_flags, SP_CLIENT     ; Client break ON
        ret

LCODE_ENDS

; ***************************************************************************
; ICODE section
; ***************************************************************************
ICODE_SEG

; Sys_Critical_Init time initialisation
PUBPROC Breaks_Critical_Init
        ; ES:EDI = IDT to use

        DBGBRK  3
        call    Setup_PM_Int
        db      03h
        dd      OFFSET32 PrevInt03Vector
        dd      OFFSET32 Int03_Handler
        dd      0ee000000h + VXD_CODESELECTOR

        call    Setup_PM_Int
        db      01h
        dd      OFFSET32 PrevInt01Vector
        dd      OFFSET32 Int01_Handler
        dd      0ee000000h + VXD_CODESELECTOR

        call    Setup_PM_Int
        db      02h
        dd      OFFSET32 PrevNMIVector
        dd      OFFSET32 NMI_Handler
        dd      0ee000000h + VXD_CODESELECTOR

        ret

; ***************************************************************************
; Device_Init time

PUBPROC Breaks_Device_Init

        Hook_Service Enable_Local_Trapping
        Hook_Service Disable_Local_Trapping
        Hook_Service Enable_Global_Trapping
        Hook_Service Disable_Global_Trapping

IFDEF   _W95_
        mov     esi, OFFSET32 SPWIN_TaskSwitchCallBack
        VMMCall Call_When_Task_Switched
ENDIF
        DBGBRK  3
        Hook_Service Set_V86_Exec_Mode
        Hook_Service Set_PM_Exec_Mode

        jmp     Kybrd_Device_Init

ICODE_ENDS

; ***************************************************************************
END
