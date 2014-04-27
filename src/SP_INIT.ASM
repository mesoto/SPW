title.  SoftProbe - SP_Init

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

SP_INIT EQU 1
INCLUDE SP_DEFS.INC
INCLUDE DEBUGSYS.INC            ; From Win95 DDK

Create_SPWIN_Service_Table EQU 1
INCLUDE SPAPI.INC

; ---------------------------------------------------------------------------
; IMPORTANT: **** This should be the last module linked ****
; ---------------------------------------------------------------------------
SCODE_SEG
; ---------------------------------------------------------------------------
PUBPROC SPWIN_End_Of_SCode      ; End of Locked code = End of SCODE
        ; leave something in this segment, otherwise problem under w95
;;      db 0eah                 ;
PUBWORD SPWIN_V86_Int21Off 0    ; offset of INT 21 within SPWIN
PUBWORD SPWIN_V86_Segment  0    ; CS segment of SPWIN.ASM

SCODE_ENDS

; ---------------------------------------------------------------------------
LDATA_SEG
; ---------------------------------------------------------------------------
PUBDWRD Physical_Bias   0 ; Physical linear address bias
; XMS memory usage:
PUBDWRD xms_memory_blk1 0 ; LogBuffer_Beg
PUBDWRD xms_memory_blk2 0 ; CapBuffer_Beg/LogBuffer_End
PUBDWRD xms_memory_blk3 0 ; SymBuffer_Beg/CapBuffer_End
PUBDWRD xms_memory_end  0 ; SymBuffer_End

LDATA_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------

; Replacement for DEBUG_Get_Version
BeginProc SPWService_GetVersion, SERVICE
        DBGBRK  1, 3
        mov     eax, 100h               ; version 1.00
        clc
        ret
EndProc SPWService_GetVersion

; Replacement for DEBUG_Fault
BeginProc SPWService_Fault, SERVICE
        DBGBRK  3, 3
        clc
        ret
EndProc SPWService_Fault

; Replacement for DEBUG_CheckFault
BeginProc SPWService_CheckFault, SERVICE
        DBGBRK  3, 3
        clc
        ret
EndProc SPWService_CheckFault

; Replacement for _DEBUG_LoadSyms
BeginProc SPWService_LoadSyms, SERVICE
        DBGBRK  3, 3
        clc
        ret
EndProc SPWService_LoadSyms

IF DBG
; ***************************************************************************
;
;   SPW_DebugQuery
;
;   DESCRIPTION:
;
;
;   ENTRY:
;
;   EXIT:
;
; ===========================================================================

SPWDBG_QryTable label dword
        dd  OFFSET32 SPWQ_Dump_1             ;[1]
        dd  OFFSET32 SPWQ_Dump_2             ;[2]
        dd  OFFSET32 SPWQ_Dump_3             ;[3]
query_max equ ($ - SPWDBG_QryTable) / 4

BeginProc SPW_DebugQuery, PUBLIC
        DBGBRK  4
        pushad

        Trace_Out "SPWin query menu:"
        Trace_Out " "
        Trace_Out "Select Option"
        Trace_Out "  1 - display VM register states"
        Trace_Out "  2 - display VM memory usage"
        Trace_Out "  3 - dump video page info"

SPWQ_take_input:
        VMMcall In_Debug_Chr
        jz      short SPWQ_Ex
        sub     al, '1'
        cmp     al, query_max
        jae     short SPWQ_Ex
        movzx   eax, al
        jmp     SPWDBG_QryTable[eax*4]

SPWQ_Ex:
        popad
        ret

SPWQ_Dump_1:
SPWQ_Dump_2:
SPWQ_Dump_3:
        jmp     SPWQ_Ex

EndProc SPW_DebugQuery

ENDIF

LCODE_ENDS

; ***************************************************************************
;                V I R T U A L   D E V I C E   D E C L A R A T I O N
; ***************************************************************************

IF      DBG     ; -----------------------------------------------------------
SPWIN_Init_Order  EQU Debug_Init_Order+10H
Declare_Virtual_Device SPWDBG, 3, 0, SPWIN_Control, SPWDBG_Device_ID, SPWIN_Init_Order,,
ELSE            ; -----------------------------------------------------------
SPWIN_Init_Order  EQU Debug_Init_Order
Declare_Virtual_Device SPWIN, 3, 0, SPWIN_Control, SPWIN_Device_ID, SPWIN_Init_Order,,
ENDIF           ; -----------------------------------------------------------

; ===========================================================================

; ***************************************************************************
;              D E V I C E   C O N T R O L   P R O C E D U R E
; ***************************************************************************

VxD_CODE_SEG

; ***************************************************************************
;
;   SPWIN_Sys_Critical_Exit
;
;   DESCRIPTION:
;       Clean up before system terminates
;       - Remove all break points.
;
;   ENTRY:
;
;   EXIT:
;
; ===========================================================================
PUBPROC SPWIN_Sys_Critical_Exit

        DBGBRK  2
        pushad                          ; save registers for the logger

        mov     ch, 0                   ; clear all bits (free)
        call    removeBreaks

        popad
        jmp     short Log_Event_Vxd

; ***************************************************************************
;
;   SPWIN_Control
;
;   DESCRIPTION:
;
;   ENTRY:
;       EAX = Control call ID
;
;   EXIT:
;       If carry clear then
;           Successful
;       else
;           Control call failed
;
;   USES:
;       EAX, EBX, ECX, EDX, ESI, EDI, Flags
;
; ===========================================================================

PUBPROC SPWIN_Control

        DBGBRK  5
IFDEF   _W95_
        cmp     eax, Sys_Critical_Init
        je      SPWIN_Sys_Critical_Init
        cmp     eax, Device_Init
        je      SPWIN_Device_Init
        cmp     eax, Sys_Critical_Exit
        je      SPWIN_Sys_Critical_Exit
        cmp     eax, Kernel32_Initialized
        je      SPWIN_Kernel32_Initialized
  IF DBG
        cmp     eax, Debug_Query
        je      SPW_DebugQuery
  ENDIF
ELSE
        cmp     eax, Sys_Critical_Init
        jne     short @f                ; MASM5 problem
        jmp     SPWIN_Sys_Critical_Init
@@:     cmp     eax, Device_Init
        jne     short @f                ; MASM5 problem
        jmp     SPWIN_Device_Init
@@:     cmp     eax, Sys_Critical_Exit
        je      SPWIN_Sys_Critical_Exit
  IF DBG
        Control_Dispatch Debug_Query, SPW_DebugQuery
  ENDIF
ENDIF

PUBPROC Log_Event_Vxd
        DBGBRK  3
        ; Make an int frame
        clc                             ; as success
        pushfd
        push    cs
        push    edx                     ; as EIP

        push    eax                     ; as R_Fault
        call    Save_CPU_Registers
        call    LogEventVxd
        call    Restore_CPU_Registers
        add     esp, 4*3                ; R_Fault, EIP, CS
        popfd                           ; Restore Int Flag
        ret

VxD_CODE_ENDS

ICODE_SEG
; ***************************************************************************
;                   I N I T I A L I Z A T I O N   C O D E
; ***************************************************************************

IF      DBG
prevPM_Callback  df 0
ENDIF

NameBuffer      db 9 dup (0)

;;      DumpRegsCalls

; ***************************************************************************
;
;   SPWIN_PMINIT_Callback
;
;   DESCRIPTION:
;       This entry is called by SPWIN.ASM during WIN386 initialisation.
;
;   ENTRY:
;       AL  = function code
;             0: PMINIT_INIT_IDT
;                DS:EDI is the IDT to use.
;             1: PMINIT_INIT_PAGING
;                BX  = phys-linear selector
;                ECX = phys-linear bias
;
;   EXIT:
;       Should return with a FAR RET
;
; ===========================================================================

PUBPROC SPWIN_PMINIT_Callback

;;      DumpRegs 'P'
IF      DBG
        pushad
        lds     esi, fword ptr [esp+20h] ; seg:offset of the call in SPWIN
        push    ss
        pop     es
        mov     edi, OFFSET32 prevPM_Callback
        movsd
        movsw
        popad
        push    ss
        pop     ds
        pushad
        call    fword ptr cs:prevPM_Callback
        popad
ENDIF
        cmp     al, PMINIT_INIT_PAGING  ; 1, PMINIT_INIT_IDT=0
        je      short DPMC_PageInit
        ja      short DPMC_Done

        ; al=PMINIT_INIT_IDT (0), DS:EDI is the IDT to use.
        ; Setup int handlers that we need.

;;      DumpRegs '0'
        pushad
        push    ds
        push    es

        push    VXD_DATASELECTOR
        pop     ds
        push    ds
        pop     es
        cld

IFE     DBG
        call    Faults_Critical_Init ;hook faults 6,b,c,d,e
        call    Debug_Critical_Init  ;set up int 41h
        call    Breaks_Critical_Init ;set up int 3,1
ENDIF
        pop     es
        pop     ds
        popad
DPMC_Done:
        add     esp, 8          ;get rid of the SPWIN call
        retf                    ;fword return

DPMC_PageInit:
        ; bx = phys-linear selector
        ; ecx = phys-linear bias

;;      DumpRegs '1'
        DBGBRK  3

        pushad
        mov     ds, bx                  ; same as VXD_DATASELECTOR
        mov     es, bx
        mov     Physical_Bias, ecx

        ; Int Flag during this call should be kept OFF!

        VMMcall Get_VMM_Version
IFDEF   _W95_
        cmp     ah, 4
        jae     short @f
        call    Exit_Windows
        db      13,10,'SoftProbe/W: VMM Version 4.0 or Higher Required.',0
ELSE
        cmp     ah, 3
        jae     short @f
        call    Exit_Windows
        db      13,10,'SoftProbe/W: VMM Version 3.x or Higher Required.',0
ENDIF

@@:     xor     eax, eax
        mov     DR0, eax
        mov     DR1, eax
        mov     DR2, eax
        mov     DR3, eax
        mov     DR6, eax
        mov     DR7, eax

        mov     esi, [esp+20h]          ; offset32 of the call in SPWIN
IF      DBG
        add     esi, 6                  ; size of 'prevPM_Callback  df 0'
ENDIF
        mov     ebx, Physical_Bias
        cld
        lodsd                           ; lo-word=segment
                                        ; hi-word=VxD_Info_Ptr
        mov     SPWIN_V86_Segment, ax
        xchg    edx, eax
        lodsw                           ; v86_terminate: offset int21_call
        mov     SPWIN_V86_Int21Off, ax
        lodsd                           ; xms_address
        movzx   ecx, word ptr ds:[esi]  ; xms_size in KB
        add     eax, ebx                ; translate to linear
        mov     xms_memory_blk1, eax    ; start of xms memory
        shl     ecx, 10                 ; KB to bytes
        add     ecx, eax
        mov     xms_memory_end, ecx     ; end of xms memory

        movzx   esi, dx                 ; segment of VxD_Info_Beg
        shl     esi, 4                  ; physical address
        add     esi, ebx                ; translate to linear
        shr     edx, 16                 ; offset of last VxD_Info_Ptr
        add     edx, esi                ; linear address of VxD_Info_End
        ; esi =>VxD_Info_Beg    db 256*(SIZE VXD_INFO_STRU) dup( ? )

        mov     [esi-4], edx            ; end of vxd info
        mov     VxD_Info_Ptr, esi       ; beg of vxd info

        mov     esi, eax                ; start of xms memory
        mov     edi, OFFSET32 DosInfo
        mov     ecx, SIZE DosInfoStru
        rep     movsb
        mov     [eax], ecx
        mov     edi, xms_memory_end
        mov     eax, DosInfo.symBufSize ; KB's for symbols
        shl     eax, 10                 ; KB to Bytes
        mov     DosInfo.symBufSize, eax ;
        sub     edi, eax
        mov     xms_memory_blk3, edi    ; SymBuffer_Beg
        mov     eax, DosInfo.capBufSize ; KB's for capture
        shl     eax, 10                 ; KB to Bytes
        sub     edi, eax
        mov     xms_memory_blk2, edi    ; CapBuffer_Beg
        DBGBRK  2
        mov     ecx, eax                ; cap size in bytes
        shr     eax, 3                  ; bytes to qwords
        mov     DosInfo.capBufSize, eax ; number of captures (qwords)
        shl     DosInfo.PhyMemSize, 20  ; MB to bytes

        ; Move the INIT sequence to the CapBuffer_Beg
        mov     key_macro_ptr, edi      ; sequence to play [INIT]
mov_Init_Commands:
        lodsb
        stosb
        cmp     al, 0
        loopne  mov_Init_Commands
        mov     byte ptr [edi-1], 0

        mov     word ptr Code_Data_Ptrs[PNTR_DATA][4], ds
        mov     eax, DosInfo.wrkBufSize ; KB's for working memory
        shl     eax, 10                 ; KB to bytes
        jz      short @f
        mov     DosInfo.wrkBufSize, eax ; size of working memory
        VMMCall _HeapAllocate, <eax, HEAPZEROINIT>
        mov     Code_Data_Ptrs[PNTR_WORK][0], eax
@@:
        DBGBRK  3
IF      DBG
        call    Faults_Critical_Init ;hook faults 6,b,c,d,e
        call    Debug_Critical_Init  ;set up int 41h
        call    Breaks_Critical_Init ;set up int 3,1
ENDIF
        call    saveIntrs
        call    InitScreen

;;IFE     DBG
        call    Setup_Intr1_Here
;;ENDIF
        mov     eax, LogBuffer_Beg
        mov     LogBuffer_Ptr, eax
        mov     byte ptr [eax], 0       ; length for the 1st line

        DBGBRK  3
        call    ReadTimeStamp
        jc      short @f
        or      DosInfo.SetupFlags, SET_TIMER
@@:
        popad
        add     esp, 8          ;get rid of the SPWIN call
        test    DosInfo.SetupFlags, SET_BRKEARLY
        jz      short @f
        pushfd
        bts     dword ptr [esp], 8      ; TF=1
        popfd
@@:     retf

; ***************************************************************************
;
; ***************************************************************************

Exit_Windows:
        DBGBRK  2
        pop     esi                     ; ptr message
        xor     eax, eax                ; exit flags
        VMMcall Fatal_Error_Handler

; ***************************************************************************
;
;   SPWIN_Sys_Critical_Init
;
;   DESCRIPTION:
;
;   ENTRY:
;       EBX = System VM handle
;       ESI = points to WIN386 command tail
;       EDX = Reference data from int 2f (DX=CS of SPWIN.ASM)
;
;   EXIT:
;       If carry flag set then SPWIN should never be called again
;
; ===========================================================================
PUBPROC SPWIN_Sys_Critical_Init
        DBGBRK  4
        pushad

        call    Log_Event_Vxd

        ; Macth the int 68h VxD names with the DDB names.
        mov     edx, VMM_DDB_BASE
MatchNames_Loop1:
        mov     ebx, [edx].DDB_Control_Proc

IFDEF   _W95_
        cmp     [edx].DDB_Req_Device_Number, VWIN32_DEVICE_ID
        jne     short @f

        DBGBRK  3
        ; The VWIN32_STATE_INFO_STRUC is located immediately after VWIN32_DDB
        add     VWIN32_State_Info_Ptr, edx ; edx+SIZE VxD_Desc_Block
@@:
ENDIF
        mov     esi, VxD_Info_Ptr       ; ptr loaded VxD's (int 68h)
        mov     ecx, [esi-4]            ; end of info
MatchNames_Loop2:
        cmp     ebx, [esi].vi_Start
        jb      short MatchNames_Next
        cmp     ebx, [esi].vi_End
        jb      short MatchNames_Found
MatchNames_Next:
        add     esi, SIZE VXD_INFO_STRU
        cmp     esi, ecx
        jb      short MatchNames_Loop2
        jmp     short MatchNames_NextDDB

MatchNames_Found:
        ; Owner found
        ; Change all the segments of this name to the DDB name

        DBGBRK  3
        lea     esi, [esi].vi_Name
        mov     edi, OFFSET32 NameBuffer
        movsd
        movsd

        mov     ebx, VxD_Info_Ptr       ; ptr loaded VxD's (int 68h)
        lea     edi, [ebx].vi_Name
        mov     ebx, [ebx-4]            ; end of info
MatchNames_Change:

        mov     esi, OFFSET32 NameBuffer
        call    str_len
        cmp     ecx, 8
        adc     cl, ch                  ; include '\0'
        call    strncmp
        jc      short MatchNames_NextVxd

        push    edi
        lea     esi, [edx].DDB_Name
        mov     cl, 8
@@:     lodsb
        cmp     al, ' '
        je      short @f
        stosb
        loop    @b
@@:     mov     al, 0
        rep     stosb
        pop     edi

MatchNames_NextVxd:
        add     edi, SIZE VXD_INFO_STRU
        cmp     edi, ebx
        jb      short MatchNames_Change

MatchNames_NextDDB:
        mov     edx, [edx].DDB_Next
        test    edx, edx
        jnz     short MatchNames_Loop1

        DBGBRK  4
        call    Faults_Init
        call    Debug_Service_Init
IF      DBG
        call    Setup_Intr1_Here
ENDIF
        popad

        mov     word ptr PrevRegs.R_SS, ss
        mov     word ptr PrevRegs.R_ES, es
        mov     word ptr PrevRegs.R_DS, ds
        mov     word ptr PrevRegs.R_FS, fs
        mov     word ptr PrevRegs.R_GS, gs
        mov     PrevRegs.R_EAX, eax
        mov     PrevRegs.R_EBX, ebx
        mov     PrevRegs.R_ECX, ecx
        mov     PrevRegs.R_EDX, edx
        mov     PrevRegs.R_EBP, ebp
        mov     PrevRegs.R_ESI, esi
        mov     PrevRegs.R_EDI, edi
        clc
        pushfd
        pop     PrevRegs.R_EFLAGS
        pop     PrevRegs.R_EIP
        mov     PrevRegs.R_CS, cs
        mov     PrevRegs.R_ESP, esp

        test    DosInfo.SetupFlags, SET_BRKEARLY
        jnz     short @f
        pushfd
        bts     dword ptr [esp], 8      ; TF=1
        popfd
@@:     jmp     PrevRegs.R_EIP

; ***************************************************************************
;
;   SPWIN_Device_Init
;
;   DESCRIPTION:
;
;   ENTRY:
;       EBX = System VM handle
;       EDX = Reference data from int 2f (DX=CS of SPWIN.ASM)
;
;   EXIT:
;       If carry flag set then SPWIN should never be called again
;
; ===========================================================================

PUBPROC SPWIN_Device_Init

        pushad

        DBGBRK  3

        call    Debug_Device_Init
        call    Breaks_Device_Init

IF DBG GE 5
        DBGBRK  3
        call    Local_Beep
        Trace_Out "INCHAR()..."
        mov     eax, 1                  ;in char
        int     41h
        DBGBRK  3
ENDIF
IF DBG GE 4
        DBGBRK  3
        Debug_Out "DEVICE INIT..."
        mov     dl, '~'
        mov     eax, 0                  ; out char
        int     41h
        DBGBRK  3
        Trace_Out 'Trace-Out: EAX=#EAX, GS=#GS, EDX=#EDX, BH=#BH.'
        mov     edx, OFFSET32 SPWIN_Device_Init
        Trace_Out 'Trace-Out: cs:edx=?cs:edx.'
  IFDEF _W95_
        Debug_Printf 'DebugPrintf: edi=%x, ecx=%d', <edi, ecx>
        Queue_Out "QUEUE OUT"
  ENDIF
ENDIF
        popad
        jmp     Log_Event_Vxd

ICODE_ENDS

; ***************************************************************************
;             R E A L   M O D E   I N I T I A L I Z A T I O N
; ***************************************************************************

; ===========================================================================
VxD_REAL_INIT_SEG
;
;   Data for real mode code is in the same segment.
;
;   SPWIN_Real_Mode_Init
;

PUBPROC SPWIN_Real_Mode_Init

;       si  = env
;       ax  = VMM version
;       bx  = flags
;       edx = reference data from int 2fh
;       ds  = es = cs

;
;   Force TEXT MODE here to make sure text mode VGA state are recorded.
;
        pusha
        mov     ax, 3                   ; VGA init requires TEXT MODE
        int     10h
        mov     dx, offset copyright
        mov     ah, 9
        int     21h
        popa

        DBGBRK  5, 60H
        test    bx, Loading_From_INT2F
        jz      SHORT SPWIN_Abort_Load
        test    bx, Duplicate_From_INT2F OR Duplicate_Device_ID
        jz      SHORT SPWIN_Ok_to_Load
;
;   Another SPWIN device has already been loaded so we won't.
;
SPWIN_Abort_Load:
        xor     bx, bx
        xor     si, si
        mov     ax, Abort_Device_Load ;+ No_Fail_Message
        ret

SPWIN_Ok_to_Load:

        xor     bx, bx
        xor     si, si
        mov     ax, Device_Load_Ok
        ret

copyright       db 'SoftProbe/W Release ',VER_STR,' (C) 1995 Mehdi Sotoodeh.  '
                db 'All rights reserved.',13,10,'$'

VxD_REAL_INIT_ENDS

END     SPWIN_Real_Mode_Init

