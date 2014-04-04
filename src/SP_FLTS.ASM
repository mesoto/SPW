title.  SoftProbe - Fault handler

SP_FLTS EQU 1
include SP_DEFS.inc
include SPAPI.inc

; --------------------------------------------------------------------------
; IMPORTANT: **** This should be the first module linked ****
; --------------------------------------------------------------------------

LDATA_SEG
; --------------------------------------------------------------------------
        ; Win95 puts _LDATA first
PUBPROC SPWIN_Beg_Of_LData      ; keep this label on 1st byte of LDATA
        jmp     SPWIN_PMINIT_Callback
        align   4

IntStk_Beg      db 4*MIN_STK_SIZE dup(0) ; Stack area
IntStk_Top      userStateStruc<>
IntStk_Usage    db -1
                db 0,0,0

IF DBG
SavedContext    dd ?
prev_w32_service DD 0
ENDIF

IFDEF   _W95_
SPW32_Services  dd 1, 0
                dd OFFSET32 SPW32_Service_0, 3
ENDIF

Faulty_Address  dd 4 dup(0,0)   ; trapped faulty addresses

; Bit definition of Fault_Flags & BF_Flags:
FF_Fault06      equ 01h
FF_Fault0C      equ 02h
FF_Fault0D      equ 04h
FF_Fault0E      equ 08h

FF_Fault06_B    equ 0
FF_Fault0C_B    equ 1
FF_Fault0D_B    equ 2
FF_Fault0E_B    equ 3

Fault_Flags     db 0
BF_Flags        db FF_Fault0D+FF_Fault0E+FF_Fault06+FF_Fault0C

PUBBYTE SP_flags 0
PUBBYTE handle_fault 0
PUBBYTE Address_Valid 0
PUBBYTE DebugOutFlags 1

LDATA_ENDS

; ---------------------------------------------------------------------------
SCODE_SEG
; ---------------------------------------------------------------------------
; Faults in this segment are trapped by SPW and returns w
PUBPROC SPWIN_Beg_Of_SCode      ; ===== Begining of trappable area. =========

; ---------------------------------------------------------------------------
; the instruction at read_a_byte is monitored by the PF_trap
; The faulting address will be increased by 4 bytes.

; Check the limit before reading it.
; Keep the limit overflow in mind (base=FFFF0000, Limit=FFFFFFFF is no limit)

PUBPROC read_byte_ltd
        cmp     cs:Address_Valid, 1
        jb      short off_limit_byte
        push    ebx
        dw      0eb81h          ;sub ebx,xxxx
PUBDWRD Address_Base 0          ;Base of memory (flat address)
        dw      0fb81h          ;cmp ebx,xxxx
PUBDWRD Address_Limit 0         ;Upper limit of memory (flat address)
        pop     ebx
        ja      short off_limit_byte

PUBPROC read_byte_al_p1
        inc     ebx
PUBPROC read_byte_al_m1
        or      al, 0ffh                ; cf=0, value in case of fault
        mov     al, ds:[ebx-1]
        ret

off_limit_word:
        inc     ebx
off_limit_byte:
        inc     ebx
PUBPROC Ret_CF_Set
        stc
        ret

PUBPROC read_word_ltd
        call    read_byte_ltd
        jc      short off_limit_byte
        mov     ah, al
        call    read_byte_ltd
        xchg    al, ah
        ret

PUBPROC read_dword_ltd
        call    read_word_ltd
        jc      short off_limit_word
        shl     eax, 16
        call    read_word_ltd
        jc      short read_dwrd1
        ror     eax, 16
        clc
read_dwrd1:
        ret

PUBPROC read_byte_cl
        inc     ebx
        mov     cl, ds:[ebx-1]          ;error handler at $-4
        clc
        ret

PUBPROC read_byte_al
        mov     al, ds:[ebx]
        clc
        ret

PUBPROC read_word_ax
        mov     ax, ds:[ebx]            ;error handler at $-4
        clc
        ret

PUBPROC read_dword_eax
        mov     eax, ds:[ebx]           ;error handler at $-4
        clc
        ret

PUBPROC xchg_byte_al
        xchg    al, ds:[ebx]            ;error handler at $-4
        clc
        ret

PUBPROC write_byte_al
        mov     ds:[ebx], al            ;error handler at $-4
        clc
        ret

PUBPROC word_read_@esi
        movzx   eax, word ptr [esi]
        clc
        ret

PUBPROC dword_read_@esi
        mov     eax, [esi]
        clc
        ret

PUBPROC qword_read_@esi
        mov     eax, [esi]
        mov     edx, [esi+4]
        clc
        ret

PUBPROC Read_dwIndex_EDX
        xor     eax, eax                ; in case it fails
        mov     eax, [esi+edx*4]
        ret
; --------------------------------------------------------------------------
; find_string:
; In:      ebx = ptr memory to search
;          edx = memory size
;          esi = ptr string to find (always present)
;           ah = length of string
; Out:      cf = 0: found it, edi=passed found pattern
;           cf = 1: not found
; esi unchanged.
PUBPROC find_string
        lodsb
        mov     edi, ebx
        mov     ecx, edx                ;ecx=len of block
        repne   scasb
        mov     ebx, edi
        mov     edx, ecx
        jne     short find_byte1
        movzx   ecx, ah
        repe    cmpsb
find_byte1:
        clc
        ret

; --------------------------------------------------------------------------
PUBPROC rep_movsb
        rep     movsb                   ;error handler at $-4
        clc
        ret

; --------------------------------------------------------------------------
PUBPROC repe_cmpsb
        repe    cmpsb                   ;error handler at $-4
        clc
        ret

PUBPROC Process_APICommand
        DBGBRK  3
        movzx   eax, [ebx].spapi_Command
        cmp     eax, 8                  ;function code
        jae     short invalid_api_pkt

        movzx   edx, [ebx].spapi_PortAddr
        cmp     edx, [ebp].R_EDX
        jne     short invalid_api_pkt

        lea     edi, [ebx].spapi_Data
        ; jump with CF=0
        jmp     dword ptr SPAPI_FunctionTable[4*eax]

invalid_api_pkt:
        stc
        ret

; ***************************************************************************
; API functions for the GUI support.
; ***************************************************************************
SPAPI_VERSION:
        mov     word ptr [edi], (VER_MAJ shl 8) + VER_MIN
        ret

SPAPI_LOADLOG:
        mov     esi, LogBuffer_Beg
        add     esi, [ebx].spapi_Offset
        mov     eax, LogBuffer_Ptr
        movzx   ecx, byte ptr [eax]
        lea     eax, [eax+ecx+1]
        xor     ecx, ecx
        sub     eax, esi
        jc      short @f
        mov     ecx, [ebx].spapi_Length
        cmp     eax, ecx
        jae     short @f
        xchg    ecx, eax
@@:     mov     [ebx].spapi_Length, ecx
        rep     movsb
        clc
        ret

SPAPI_INTGET:
        mov     eax, int_flags
        and     eax, 0000000000001010b  ; int 1 and 3 only
        stosd
        ret

SPAPI_INTSET:
        and     int_flags, not 001110b  ; BI1 = BI3 = NMI = 0
        mov     eax, [edi]              ; INT MASK   [edi+0]
        and     eax, 0000000000001110b  ; int 1, 2 and 3 only
        or      int_flags, eax
        ret

SCODE_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------
        jmp     SPWIN_PMINIT_Callback   ; keep it on 1st byte of LCODE

; --------------------------------------------------------------------------
; CAUTION: From this area upto SPWIN_Beg_Of_LCode faults can occur without
;       generating internal faults (should be handleded by OS)
; --------------------------------------------------------------------------
ExternalFaultCheck:
        DBGBRK  4
        mov     ebx, [ebp].R_EIP
        mov     eax, [ebp].R_CS
        and     ecx, 7

        bt      dword ptr Fault_Flags, ecx
        jnc     short not_our_fault

        DBGBRK  3

        cmp     ebx, Faulty_Address[8*ecx][0]
        jne     short not_our_fault
        cmp     eax, Faulty_Address[8*ecx][4]
        jne     short not_our_fault
        DBGBRK  3
        mov     Fault_Flags, 0                  ; invalidate for next
        pop     esi                             ; remove ret address
        push    dword ptr Fault_Message[ecx*4]  ; as R_BrkMsg
        jmp     SPWIN_MouseTrap

not_our_fault:
        ret

; --------------------------------------------------------------------------
InternalFaultCheck:
        DBGBRK  4
        push    eax
        push    ds
        push    VXD_DATASELECTOR
        pop     ds
        ; esp ->ds      +00
        ;       eax     +04
        ;       ret     +08
        ;       fault   +0c
        ;       eip     +10
        ;       cs      +14
        ;       eflags  +18
        call    Restore_Int_Controller
        and     byte ptr [esp+10h][10], not 1   ; RF=0 (EFLAGS)
        cmp     word ptr [esp+10h][4], VXD_CODESELECTOR
        jne     short not_in_probe
        mov     eax, [esp+10h][0]       ; eip
        cmp     eax, OFFSET32 SPWIN_End_Of_SCode
        jae     short not_in_probe
        cmp     eax, OFFSET32 SPWIN_Beg_Of_SCode
        jb      short check_internal_fault

Safecode_Fault:
        DBGBRK  3
        pop     ds
        pop     eax
        add     esp, 4*3                ;remove ret, faultCode and eip
        push    OFFSET32 Ret_CF_Set
        iretd

check_internal_fault:
IF      DBG
        cmp     eax, OFFSET32 SPWIN_Beg_Of_LCode
        jb      short not_in_probe

        ; Its INTERNAL for sure!!

        pop     ds
        pop     eax
        add     esp, 4                  ;remove ret address

        call    Save_CPU_Registers

SPWIN_Internal_Fault:
        DBGBRK  1
        DBGBRK  1
        call    SPWIN_MouseTrap
        db      'Internal Error: Fault=',d_h32
        db      ' EIP=',d_r32,R_EIP,d_sub
ENDIF

not_in_probe:
        pop     ds
        pop     eax

; --------------------------------------------------------------------------
; CAUTION: Make sure this routine does not generate a double fault due to
;       a page fault when Stack page not present.
;       Any fault (ie page fault) due to stack can call this routine and
;       generate a double fault if stack growth
; --------------------------------------------------------------------------
PUBPROC Save_CPU_Registers
        DBGBRK  3
        cli
        push    ebp
        mov     ebp, OFFSET32 IntStk_Top
        inc     byte ptr [ebp][IntStk_Usage-IntStk_Top]
        jz      short SaveState_0
        lea     ebp, [esp+24-SIZE userStateStruc] ; overwrites 6 dwords
IF DBG
        cmp     ebp, OFFSET32 IntStk_Beg
        jb      short SaveState_0
        cmp     ebp, OFFSET32 IntStk_Beg+MIN_STK_SIZE
        jb      short SPWIN_Internal_Fault
ENDIF
SaveState_0:
        pop     [ebp].R_EBP
        pop     [ebp].R_BrkMsg          ;return address
        pop     [ebp].R_Fault
        pop     [ebp].R_EIP
        pop     [ebp].R_CS
        pop     [ebp].R_EFLAGS
        mov     [ebp].R_EDI, edi
        mov     [ebp].R_ESI, esi
        mov     [ebp].R_EDX, edx
        mov     [ebp].R_ECX, ecx
        mov     [ebp].R_EBX, ebx
        mov     [ebp].R_EAX, eax
        mov     ecx, CR2
        bt      [ebp].R_EFLAGS, 17      ;V86?
        mov     [ebp].R_CR2, ecx
        sbb     ecx, ecx
        jc      short SaveState_1

        mov     word ptr [ebp].R_ES, es
        mov     word ptr [ebp].R_DS, ds
        mov     word ptr [ebp].R_FS, fs
        mov     word ptr [ebp].R_GS, gs
        test    byte ptr [ebp].R_CS, 3  ;from PL0?
        jnz     short SaveState_2
        mov     [ebp].R_ESP, esp
        mov     word ptr [ebp].R_SS, ss
        jmp     short SaveState_4

SaveState_1:
        pop     [ebp].R_ESP
        pop     [ebp].R_SS
        pop     [ebp].R_ES              ; V86 segment registers
        pop     [ebp].R_DS
        pop     [ebp].R_FS
        pop     [ebp].R_GS
        jmp     short SaveState_3       ; clear hi-word of ESP

SaveState_2:
        pop     [ebp].R_ESP
        pop     [ebp].R_SS
        lar     ebx, [ebp].R_CS
        lar     eax, [ebp].R_SS
        or      eax, ebx
        bt      eax, 22                 ; default size
        jc      short SaveState_4
        ; both CS and SS are 16-bit
SaveState_3:
        mov     word ptr [ebp].RingESP[2], 0
SaveState_4:
        mov     [ebp].RingESP, esp
        mov     word ptr [ebp].RingSS, ss
        mov     word ptr [ebp].R_CS[2], cx
        mov     word ptr [ebp].R_DS[2], cx
        mov     word ptr [ebp].R_ES[2], cx
        mov     word ptr [ebp].R_FS[2], cx
        mov     word ptr [ebp].R_GS[2], cx
        mov     word ptr [ebp].R_SS[2], cx

        push    VXD_DATASELECTOR
        pop     ss
        mov     esp, ebp                ; switch stack
        push    ss
        pop     ds
        push    ds
        pop     es
        cld
        mov     ecx, CR3
        mov     CR3, ecx                ;invalidate the cache
IFDEF   _W95_
@@CurrentContext:                       ;will be replaced with
        VMMcall _GetCurrentContext      ; mov eax, [CurrentContext]
        mov     CurMemoryContext, eax
ENDIF
IF DBG
        mov     bl, 0eh
        call    getIntVector
        mov     SavedContext, edx
        mov     edx, OFFSET32 SPWIN_PageFault
        call    setIntVectorCS
ENDIF
        jmp     [ebp].R_BrkMsg          ;caller return

; --------------------------------------------------------------------------
        align   4
SPAPI_FunctionTable label dword
        dd OFFSET32 SPAPI_VERSION ; 0 SPWCMD_VERSION
        dd OFFSET32 SPAPI_LOADLOG ; 1 SPWCMD_LOADLOG
        dd OFFSET32 Cmd_LogClear  ; 2 SPWCMD_EMPTYLOG
        dd OFFSET32 SPAPI_INTGET  ; 3 SPWCMD_INTGET
        dd OFFSET32 SPAPI_INTSET  ; 4 SPWCMD_INTSET
        dd OFFSET32 SPAPI_SYMINFO ; 5 SPWCMD_SYMINFO
        dd OFFSET32 SPAPI_SYMLOAD ; 6 SPWCMD_SYMLOAD
        dd OFFSET32 SPAPI_SYMREMV ; 7 SPWCMD_SYMREMV

Fault_Message   label dword
        dd OFFSET32 Fault06_Msg
        dd OFFSET32 Fault0C_Msg
        dd OFFSET32 Fault0D_Msg
        dd OFFSET32 Fault0E_Msg

SoftProbe_API:
        DBGBRK  4
        mov     eax, [ebp].R_DS
        mov     ebx, [ebp].R_EBX        ;DS:EBX=ptr command pkt
        call    Get_FlatAddress         ;ebx=linear address
        jc      short Prev_GP_Handler
        call    Process_APICommand
        jc      short Prev_GP_Handler
        add     [ebp].R_EIP, 2          ;return to inst at IP+2
IFDEF   _W95_
        mov     [ebp].R_EAX, 'SP95'     ;signature
ELSE
        mov     [ebp].R_EAX, 'SP31'     ;signature
ENDIF
        jmp     Return_After_Restore

; --------------------------------------------------------------------------
SPWIN_GPFault:
        DBGBRK  3
        call    InternalFaultCheck
        mov     cl, FF_Fault0D_B
        call    ExternalFaultCheck
        ; eax:ebx=instruction address
        call    Get_FlatAddress         ;ebx=linear address
        DBGBRK  2
        jc      short Prev_GP_Handler
        mov     esi, ebx                ;needed for inst len calculations
        call    read_byte_ltd
        DBGBRK  2
        jc      short Prev_GP_Handler
        cmp     al, 0cdh                ; int xx?
        je      short GP_On_Int_xx
        mov     ah, al                  ; save opcode
        or      al, 3                   ;
        cmp     al, 0e7h                ; e4/e5/e6/e7 (in/out b/w xx)
        je      short GP_io_xx
        movzx   edx, word ptr [ebp].R_EDX
        or      al, 80h                 ; 6c/6d/6e/6f (ins/outs b/w)
        cmp     al, 0efh                ; ec/ed/ee/ef (in/out b/w dx)
        je      short GP_io_dx
        ;
        ;
Prev_GP_Handler:
        call    Restore_CPU_Registers
        test    cs:SP_flags, SP_I1ON + SP_SS1BREAK ; did we trace?
        jz      short @f
        btr     dword ptr [esp+12][1], 0 ; TF=1?
        jnc     short @f
        pushfd
        bts     dword ptr [esp], 8      ; TF=1
        popfd
@@:     db      0eah                    ; jmp ssss:oooooooo
PrevInt0dVector dd 0, 0

GP_On_Int_xx:
        xor     eax, eax
        call    read_byte_ltd
        jc      short Prev_GP_Handler
        bt      int_flags, eax          ; watch this one?
        jnc     short Prev_GP_Handler

        ; Find the break structure for this INT

        DBGBRK  3
        mov     edi, OFFSET32 breakTable
findIntBreak1:
        test    [edi].brk_Flags, BRK_ACTIVE
        jz      short findIntBreak2
        cmp     [edi].brk_TypeInfo, BRK_ON_INT
        jne     short findIntBreak2
        cmp     al, [edi].brk_IntNumber ;int number
        je      short GP_IntBreak
findIntBreak2:
        add     edi, BreakInfoSize
        cmp     edi, OFFSET32 breakTable + TOTAL_BREAKS*BreakInfoSize
        jb      short findIntBreak1
        ; not in our active list
        jmp     Prev_GP_Handler

GP_io_xx:
        call    read_byte_cl
        jc      Prev_GP_Handler
        movzx   edx, cl
GP_io_dx:
        cmp     [ebp].R_ESI, 'Soft'
        jne     short @f
        cmp     [ebp].R_EDI, 'Prob'
        jne     short @f
        call    dword_read_@esi
        jc      short @f
        cmp     eax, SPAPI_CallRet      ;in al,dx; test al,0f9;sbb cx,cx
        je      SoftProbe_API
@@:     call    FindIoBreak
        jc      Prev_GP_Handler
        ; only edi and al are modified
        DBGBRK  3

        call    Evaluate_BreakCondition
        jc      Prev_GP_Handler
        DBGBRK  3
        call    SPWIN_MouseTrap
        db      'I/O Break',d_sub

GP_IntBreak:
        DBGBRK  3
        call    Evaluate_BreakCondition
        jc      Prev_GP_Handler
        DBGBRK  3
        call    SPWIN_MouseTrap
        db      'INT Break',d_sub

Fault06_Msg     db 'Invalid Opcode',d_sub
Fault0C_Msg     db 'Stack Fault (',d_h32,')',d_sub
Fault0D_Msg     db 'GP-Fault (',d_h32,')',d_sub
Fault0E_Msg     db 'Page Fault (',d_h32,')',d_sub

; --------------------------------------------------------------------------
SPWIN_PageFault:
        call    InternalFaultCheck
        ; registers are saved
        mov     cl, FF_Fault0E_B
        call    ExternalFaultCheck
        call    Restore_CPU_Registers
        db      0eah            ; jmp ssss:oooooooo
PrevInt0eVector dd 0, 0

; --------------------------------------------------------------------------
SPWIN_OpcodeFault:
        DBGBRK  2
        push    0                       ; as error code
        call    InternalFaultCheck
        mov     cl, FF_Fault06_B
        call    ExternalFaultCheck
        ; eax:ebx=instruction address
        xor     ax, word ptr PrevRegs.R_CS
        jnz     short @f
        xor     ebx, PrevRegs.R_EIP
@@:     sete    byte ptr [ebp].R_Fault

        call    Restore_CPU_Registers

        DBGBRK  3
        test    byte ptr [esp], 1       ;R_Fault
        lea     esp, 4[esp]             ;remove fake error code
        jz      short @f

        test    cs:SP_flags, SP_I1ON + SP_SS1BREAK ; did we trace?
        jz      short @f
        btr     dword ptr [esp+9], 0    ;tracing?
        jnc     short @f
        pushfd
        bts     dword ptr [esp], 8      ; TF=1
        popfd
@@:     db      0eah                    ;jmp ssss:oooooooo
PrevInt06Vector dd 0,0

; --------------------------------------------------------------------------
SPWIN_StackFault:
        DBGBRK  2
        call    InternalFaultCheck
        ; registers and DS are saved
        mov     cl, FF_Fault0C_B
        call    ExternalFaultCheck
        call    Restore_CPU_Registers
        db      0eah            ;jmp old handler
PrevInt0cVector dd 0,0

; --------------------------------------------------------------------------
PUBPROC SPWIN_Beg_Of_LCode              ; Beg of internal fault check
; --------------------------------------------------------------------------

PUBPROC Restore_CPU_Registers
IF DBG
        mov     bl, 0eh
        call    getIntVector
        mov     edx, SavedContext
        call    setIntVector
ENDIF
        pop     edi                     ;caller return
        mov     esp, ebp
        pop     ebx                     ;R_ESP
        pop     eax                     ;R_SS

        dec     IntStk_Usage
        test    byte ptr [ebp].R_EFLAGS[2], 2 ;V86?
        jnz     short RestoreState_1
        pop     es
        pop     ds
        pop     fs
        pop     gs
        lss     esp, fword ptr [ebp].RingESP
        DBGBRK  3
        test    byte ptr [ebp].R_CS, 3 ;from PL0?
        jnz     short RestoreState_2
        jmp     short RestoreState_3
RestoreState_1:
        lss     esp, fword ptr [ebp].RingESP
        push    [ebp].R_GS
        push    [ebp].R_FS
        push    [ebp].R_DS
        push    [ebp].R_ES
RestoreState_2:
        push    eax                     ;R_SS
        push    ebx                     ;R_ESP
RestoreState_3:
        push    [ebp].R_EFLAGS
        push    [ebp].R_CS
        push    [ebp].R_EIP
        push    [ebp].R_Fault
        push    edi                     ;caller return address
        mov     eax, [ebp].R_CR2
        mov     CR2, eax
        mov     eax, [ebp].R_EAX
        mov     ebx, [ebp].R_EBX
        mov     ecx, [ebp].R_ECX
        mov     edx, [ebp].R_EDX
        mov     esi, [ebp].R_ESI
        mov     edi, [ebp].R_EDI
        mov     ebp, [ebp].R_EBP
        ret

; --------------------------------------------------------------------------
PUBPROC Cmd_BF
        call    Parse_Line
        FullCmd 'GP'   GOTO_REL16  BF_OnOff <FF_Fault0D>
        FullCmd 'PF'   GOTO_REL16  BF_OnOff <FF_Fault0E>
        FullCmd 'OP'   GOTO_REL16  BF_OnOff <FF_Fault06>
        FullCmd 'SF'   GOTO_REL16  BF_OnOff <FF_Fault0C>
        db 0
        mov     al, FF_Fault0D+FF_Fault0E+FF_Fault06+FF_Fault0C
BF_OnOff:
        xchg    edx, eax
        call    Parse_Line
        FullCmd 'ON'   JUMP_ADDRS  <OFFSET32 Enable_Fault_Breaks>
        FullCmd 'OFF'  JUMP_ADDRS  <OFFSET32 Disable_Fault_Breaks>
        db 0

displayFaults:
        call    PrintfMainScr
        db      d_lf,'Break On Faults:',d_el

        mov     ebx, OFFSET32 Fault_Types
dispFaultsLoop:
        DBGBRK  3
        mov     al, [ebx]
        inc     ebx
        and     al, BF_Flags
        setnz   al
        push    eax
        call    Printf
        db      ' ',d_text,t_fill+2,'='
        _table  ON_OFF_Table
        db      d_el
        cmp     byte ptr [ebx], 0
        jne     short dispFaultsLoop
        ret

Enable_Fault_Breaks:
        or      BF_Flags, dl
        jmp     displayFaults

Disable_Fault_Breaks:
        not     dl
        and     BF_Flags, dl
        jmp     displayFaults

Fault_Types     db FF_Fault0D,'GP',FF_Fault0E,'PF',FF_Fault06,'OP'
                db FF_Fault0C,'SF',0

; ***************************************************************************
;
;   SPWIN_Hook_Faults
;
;   DESCRIPTION:
;       Fault 06 - Invalid Opcodes
;       Fault 0C - Stack Fault
;       Fault 0D - General Protection Fault
;       Fault 0E - Page Fault
;
;   ENTRY:
;       EBX = Current VM handle
;       EBP = Client Registers
;
;   EXIT:
;
; ===========================================================================
IFNDEF  _W95_
PM_Fault0C_Handler:
        push    OFFSET32 fault_done     ; will be replaced by the prev hndlr
        jmp     short chk_flt0c
ENDIF

V86_Fault0C_Handler:
        push    OFFSET32 fault_done     ; will be replaced by the prev hndlr
chk_flt0c:
        push    FF_Fault0C_B
        jmp     short Record_Fault

; ===========================================================================
IFNDEF  _W95_
PM_Fault06_Handler:
        push    OFFSET32 fault_done     ; will be replaced by the prev hndlr
        DBGBRK  4
        ; Take care of KERNEL(1) segment which uses 0FFF (invalid opcode)
        ; as part of DPMI initialisation.
        call    CheckKernelFaults
        jc      short chk_flt06
        ret                             ; go kernel handler
ENDIF

VMM_Fault06_Handler:
        push    OFFSET32 fault_done     ; will be replaced by the prev hndlr
        jmp     short chk_flt06

V86_Fault06_Handler:
        push    OFFSET32 fault_done     ; will be replaced by the prev hndlr
chk_flt06:
        push    FF_Fault06_B
        jmp     short Record_Fault

; ===========================================================================
IFNDEF  _W95_
PM_Fault0E_Handler:
        push    OFFSET32 fault_done     ; will be replaced by the prev hndlr
        jmp     short chk_flt0e
ENDIF

V86_Fault0E_Handler:
        push    OFFSET32 fault_done     ; will be replaced by the prev hndlr
chk_flt0e:
        push    FF_Fault0E_B
Record_Fault:
        xchg    eax, [esp]
        DBGBRK  3
        bt      dword ptr BF_Flags, eax ; are we supposed to trap that?
        jnc     short Next_Fault_Handler

        btc     dword ptr Fault_Flags, eax
        jc      short Next_Fault_Handler

        push    edx
        bt      [ebp].Client_EFlags[2], 1       ; V86?
        sbb     edx, edx
        mov     dx, word ptr [ebp].Client_CS

        ; Check for the the fault exec after the break on fault
        cmp     edx, Faulty_Address[8*eax][4]
        jne     short Restart_Fault1
        mov     edx, [ebp].Client_EIP
        xor     edx, Faulty_Address[8*eax][0]
        jnz     short Restart_Fault2
        pop     edx
        test    SP_flags, SP_EXEC_FLT
        jz      short Restart_Fault3
Next_Fault_Handler:
        and     SP_flags, not SP_EXEC_FLT
        btr     dword ptr Fault_Flags, eax
        pop     eax
fault_done:
        ret

Restart_Fault1:
        mov     Faulty_Address[8*eax][4], edx
Restart_Fault2:
        mov     edx, [ebp].Client_EIP
        mov     Faulty_Address[8*eax][0], edx
        pop     edx
Restart_Fault3:
        pop     eax
        add     esp, 4                  ; remove addres of next handler
        ret                             ; return to VMM to restart it

; ===========================================================================
VMM_Fault0D_Handler:
        push    OFFSET32 fault_done     ; will be replaced by the prev hndlr
chk_flt0d:
        push    FF_Fault0D_B
        jmp     short Record_Fault

V86_Fault0D_Handler:
        push    OFFSET32 fault_done     ; will be replaced by the prev hndlr
        jmp     short chk_flt0d

IFNDEF  _W95_
PM_Fault0D_Handler:
        push    OFFSET32 fault_done     ; will be replaced by the prev hndlr
        DBGBRK  4
        ; Take care of USER case which loads the non-present selectors into
        ; ES register.
        call    CheckKernelFaults
        jc      short chk_flt0d
        ret                             ; go kernel handler

lstr_user:      LString 'USER'
lstr_kernel:    LString 'KERNEL'

; In:   EBP    = client register struc
; Out:  CF = 0  if Client_CS is KERNEL(1) or USER(4)
;       CF = 1  not found or not accessible
CheckKernelFaults:
        DBGBRK  4
        pushad
        call    CollectKernelInfo
        jc      short chkcli_Done
        mov     eax, dword ptr [ebp].Client_CS
        call    ModuleNameFromSelector
        jc      short chkcli_Done
        cmp     al, 'N'
        jne     short chkcli_Done

        xchg    eax, ecx                ; eax points to MDB
        push    dword ptr [ebp].Client_CS ; PARAM1 = Segment to find
        call    FindP16Segment
        pop     ecx
        jc      short chkcli_Done
        ; edx = segment#
        ; edi = lstring name
        mov     esi, OFFSET32 lstr_user ; module name
        cmp     edx, 4                  ; can it be USER(4)?
        je      short @f
        dec     edx                     ; can it be KERNEL(1)?
        stc
        jnz     short chkcli_Done
        mov     esi, OFFSET32 lstr_kernel
@@:     call    lstrncmp
chkcli_Done:
        popad
        ret
ENDIF

IFDEF   _W95_
; This service is called by KERNEL32.0001( 00020000,... ) =DEBUG,WIN32 SVC 0
SPW32_Service_0:
        ; esp+00-return address
        ; esp+04-???
        ; esp+08-Current VM (EBX)
        ; esp+0c-Fault number           1st of 3 params copied
        ; esp+10-flags???               2nd of 3 params copied
        ; esp+14-ptr CONTEXT            3rd of 3 params copied
        pushad
        DBGBRK  3
        mov     esi, 0b8h               ; eip offset in CONTEXT (winnt.h)
        add     esi, [esp+20h][14h]     ; CONTEXT record
        mov     edx, [esi+0]            ; EIP
        movzx   ecx, word ptr [esi+4]   ; CS
        mov     eax, [esp+20h][0ch]     ; fault number
        call    Map_Faults
        mov     handle_fault, 0
        popad
IF      DBG
        jmp     prev_w32_service
ELSE
        ret     5*4
ENDIF
ENDIF

; IN:   EAX    = fault number
;       CX:EDX = faulting CS:EIP
; OUT:  CF = 1 to trap on it
PUBPROC Map_Faults
        sub     eax, 6
        jz      short map_fault1
        sub     al, 0ch-6
        cmp     eax, 3
        jnc     short map_fault2
        ; possible faults: 0c, 0d or 0e
        add     al, FF_Fault0C_B
if      FF_Fault06_B
        .err
endif
map_fault1:
        bt      dword ptr BF_Flags, eax ; are we supposed to trap that?
        jnc     short map_fault2
        jecxz   short map_fault2
        bts     dword ptr Fault_Flags, eax
        lea     ebx, Faulty_Address[8*eax]
        mov     [ebx+0], edx
        mov     [ebx+4], ecx
        stc
map_fault2:
        ; CF=1 to trap
        ret

LCODE_ENDS

; ***************************************************************************
ICODE_SEG

IFDEF   _W95_
Dummy_DDB VxD_Desc_Block <,,DEBUG_Device_ID,4,0,,,,,,,,,,,>
ELSE
Prev_DYNALINK_HANDLER dd 0

SPWIN_Dynalink_Handler  proc
        call    Prev_DYNALINK_HANDLER
        mov     VMM_DDB_BASE, ecx
        ret
SPWIN_Dynalink_Handler  endp
ENDIF

Fault_Hook_Install MACRO fltnum, fltmode
        mov     eax, fltnum&h
        mov     esi, OFFSET32 fltmode&_Fault&fltnum&_Handler
        VMMcall Hook_&fltmode&_Fault
        test    esi, esi
        jz      short @f
        mov     dword ptr [fltmode&_Fault&fltnum&_Handler+1], esi
@@:
        ENDM

PUBPROC Faults_Init
        ; VMM installs its own fault handlers after Sys_Critical_Init.
        ; If we install hooks here it will handle the faults that VMM cannot
        ; handle.

        DBGBRK  3
IFNDEF  _W95_
        Fault_Hook_Install 06, PM
        Fault_Hook_Install 0C, PM
        Fault_Hook_Install 0D, PM
        Fault_Hook_Install 0E, PM
ENDIF
        Fault_Hook_Install 06, V86
        Fault_Hook_Install 0C, V86
        Fault_Hook_Install 0D, V86
        Fault_Hook_Install 0E, V86

        Fault_Hook_Install 06, VMM
        Fault_Hook_Install 0D, VMM

IFDEF   _W95_
        DBGBRK  3
IF      DBG
        mov     eax, 0c000d600h + 4*2
        mov     eax, [eax]
        mov     eax, [eax+8]
        mov     prev_w32_service, eax
ENDIF
        push    OFFSET32 SPW32_Services
        push    OFFSET32 Dummy_DDB
        VMMCall _Register_Win32_Services
        add     esp, 8
ENDIF
        ret

PUBPROC Setup_PM_Int
        pop     esi
        lodsb
        xchg    ebx, eax
        call    getIntVector
        xchg    ecx, eax
        lodsd
        mov     [eax+0], edx
        mov     [eax+4], ecx
        lodsd
        xchg    edx, eax
        lodsd
        push    esi
        ; eax:edx = access:selector:offset32
        jmp     setIntVector

PUBPROC Faults_Critical_Init
        DBGBRK  4
        call    Setup_PM_Int
        db      06h
        dd      OFFSET32 PrevInt06Vector
        dd      OFFSET32 SPWIN_OpcodeFault
        dd      08e000000h + VXD_CODESELECTOR

        call    Setup_PM_Int
        db      0ch                     ;Stack fault
        dd      OFFSET32 PrevInt0cVector
        dd      OFFSET32 SPWIN_StackFault
        dd      08e000000h + VXD_CODESELECTOR

        call    Setup_PM_Int
        db      0dh                     ;GP Fault
        dd      OFFSET32 PrevInt0dVector
        dd      OFFSET32 SPWIN_GPFault
        dd      08e000000h + VXD_CODESELECTOR

        call    Setup_PM_Int
        db      0eh                     ;Page Fault
        dd      OFFSET32 PrevInt0eVector
        dd      OFFSET32 SPWIN_PageFault
        dd      08e000000h + VXD_CODESELECTOR
        DBGBRK  4
IFDEF   _W95_
        VMMcall _GetCurrentContext      ; eax = CurrentContext
        xchg    ecx, eax
        VMMcall VMM_GetDDBList          ; Get the VMM_DDB_BASE
        mov     VMM_DDB_BASE, eax
        mov     eax, [eax].DDB_Service_Table_Ptr
        mov     esi, [eax+4*157h]       ;_GetCurrentContext
        ; **HACK**
        ; _GetCurrentContext code is only mov eax, [xxxxxxxx]
        lodsb
        cmp     al, 0a1h                ; mov eax, [xxxxxxxx]?
        jne     short @f
        lodsd
        xchg    esi, eax
        call    dword_read_@esi
        jc      short @f
        cmp     eax, ecx                ; is it realy the context?
        jne     short @f
        mov     eax, OFFSET32 @@CurrentContext
        mov     word ptr [eax], 058bh   ; MOV EAX, [xxxxxxxx]
        mov     [eax+2], esi            ; xxxxxxxx
@@:
ELSE
        mov     esi, OFFSET32 SPWIN_Dynalink_Handler
        mov     eax, 20h
        VMMCall Hook_VMM_Fault          ; install our handler
        mov     Prev_DYNALINK_HANDLER, esi
        mov     eax, 20h
        VMMCall Hook_VMM_Fault          ; call our handler then restore
ENDIF
        ret

ICODE_ENDS

; ***************************************************************************
END
