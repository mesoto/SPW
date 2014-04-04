title.  SoftProbe - Kernel support.

SP_KRNL EQU 1
INCLUDE SP_DEFS.INC 
INCLUDE SP_KRNL.INC 
IFDEF   _W95_
INCLUDE VWIN32.INC
ENDIF ; _W95_

; ---------------------------------------------------------------------------
LDATA_SEG
; ---------------------------------------------------------------------------

PUBDWRD VMM_DDB_BASE          0
PUBDWRD THHOOK_PTR            <0,0>

PUBDWRD THHOOK_LinAddr        0
PUBDWRD BURGERMASTER_LinAddr  0
PUBDWRD SELECTORTABLE_LinAddr 0

IFDEF   _W95_
PUBDWRD CurMemoryContext 0
Total_Win32Services dd 0
ENDIF

special_owners  db 12
        db 'TEMP        ' ; -7 FFF9  "bogus" (temporarily allocated)
        db '            ' ; -6 FFFA  "wraith" (?)
        db 'PHANTOM     ' ; -5 FFFB  "phantom" (defunct EMS type?)
        db 'NOT THERE   ' ; -4 FFFC  "NOT THERE" (mapped to hardware)
        db 'BURGERMASTER' ; -3 FFFD  Burgermaster itself (KRNL286 only)
        db '            ' ; -2 FFFE  ?
        db 'SENTINEL    ' ; -1 FFFF  sentinel block
        db 'FREE        ' ; 0  0000  free

LDATA_ENDS

; ---------------------------------------------------------------------------
SCODE_SEG       ; Safe code area (No Pushes inside calls)
; ---------------------------------------------------------------------------

PUBPROC qword_write_@esi
        mov     [esi+0], eax
        mov     [esi+4], edx
        clc
        ret

PUBPROC CollectKernelInfo
        DBGBRK  3
        xor     eax, eax
        mov     THHOOK_LinAddr, eax
        mov     BURGERMASTER_LinAddr, eax
        mov     SELECTORTABLE_LinAddr, eax

IFDEF   _W95_
        mov     eax, Module32_List_Ptr
        test    eax, eax
        jz      short @f
        mov     eax, [eax]              ;ptr MOD32LIST
@@:     mov     Module32_List, eax
ENDIF
        mov     eax, THHOOK_PTR[4]
        call    Get_Selector
        jc      short kernel_done
        ; eax=base, edx=limit, esi=ptr descriptor
        add     eax, THHOOK_PTR         ; eax = linear address of THHOOK
        mov     THHOOK_LinAddr, eax

        mov     ecx, [eax].th_SelTableStart
        movzx   eax, [eax].th_pGlobalHeap ; selector(BURGERMASTER)
        call    Get_Selector
        jc      short kernel_done
        ; eax=base, edx=limit, esi=ptr descriptor
        mov     BURGERMASTER_LinAddr, eax
        add     eax, ecx
        mov     SELECTORTABLE_LinAddr, eax
kernel_done:
        ret

; IN:   ax = selector
; OUT:  CF=0    esi = ptr module name
;               ecx = ptr module header(ax=NE)/TaskDB(ax=TB), edx = limit
;       CF=1    esi = ptr 0
PUBPROC ModuleNameFromSelector
        DBGBRK  3
        call    ModuleHandleFromSelector
        jc      short unknown_module

; ---------------------------------------------------------------------------
; IN:   ax = module handle (ax:0=NE header)
; OUT:  CF=0    esi = ptr module name
;               ecx = ptr module header(ax=NE)/TaskDB(ax=TB), edx = limit
;       CF=1    esi = ptr 0
PUBPROC ModuleNameFromHandle
;;      HandleToSelector eax
        call    Get_Selector
        jc      short unknown_module
        ; eax=base, edx=limit
        mov     esi, OFFSET32 Zeros     ; in case of InternalFault traps
        xchg    ecx, eax
        ; ds:ecx=NE header address
        movzx   eax, [ecx].ne_signature
        cmp     ax, 454Eh               ; 'NE'
        jne     short MNFH_tryPSP
        ; Obtain the resident names table offset from the NE header.
        ; The first entry is always the module name (lstring).
        movzx   eax, [ecx].ne_restab    ; resident names offset (lstring)
        lea     esi, [ecx+eax+1]        ; string
        mov     ax, 454Eh               ; 'NE'
        ret

MNFH_tryPSP:
        cmp     ax, 20CDh               ; PSP mark?
        jne     short MNFH_tryTDB
        sub     ecx, 100h               ;linear address -100h is the TDB
MNFH_tryTDB:
        movzx   eax, [ecx].td_signature
        cmp     ax, 4454h               ; 'TD'?
        jnz     short unknown_module

        lea     esi, [ecx].td_moduleName
        ret

; IN:   ax = selector
; OUT:  CF=0    ax = module handle
;       CF=1
PUBPROC ModuleHandleFromSelector
        DBGBRK  3
        test    al, 4                   ; GDT?
        jz      short retCF1
        mov     ecx, SELECTORTABLE_LinAddr
        jecxz   short retCF1
        and     eax, 0000fff8h          ; index*8 to LDT
        shr     eax, 1                  ; index to selector table
        mov     ecx, [eax+ecx]          ; offset inside BURGERMASTER
        jecxz   short retCF1
        add     ecx, BURGERMASTER_LinAddr
        movzx   eax, [ecx].gh_owner     ; owner of the arena
        ret

unknown_module:                         ; esi= OFFSET32 bad_modName
        mov     esi, OFFSET32 Zeros
retCF1: stc
        ret

; ---------------------------------------------------------------------------
; IN:   none (ds)
; OUT:  ax = module handle (ax:0=NE header)
PUBPROC GetCurrentTask
        DBGBRK  3
        call    CollectKernelInfo
        mov     ecx, THHOOK_LinAddr
        jecxz   short retCF1
        movzx   eax, [ecx].th_CurTDB
;       HandleToSelector eax
        call    Get_Selector
        jc      short retCF1
        cmp     [eax].td_signature, 4454h ; 'TD'?
        jne     short retCF1
        movzx   eax, [eax].td_hTask
        ret

PUBPROC GetHeadExe
        mov     eax, THHOOK_LinAddr
        cmp     eax, 1
        jb      short @f
        movzx   eax, [eax].th_hExeHead
@@:     ret

PUBPROC GetHeadTDB
        mov     eax, THHOOK_LinAddr
        cmp     eax, 1
        jb      short @f
        movzx   eax, [eax].th_HeadTDB
@@:     ret

; In at Walk_Tasks:
;       eax = HeadTDB
;       ecx = number of tasks to skip
; Out:  eax = ptr taskDB if ecx=0
;       edi = taskDB
Next_Task:
        movzx   eax, [eax].td_next
Walk_Tasks:
        mov     edi, eax
        call    Get_Selector
        jc      short @f
        cmp     [eax].td_signature, 4454h ; 'TD'
        jne     short @f
        loop    short Next_Task
@@:     ret

PUBPROC CollectTDBInfo
        lea     eax, [ebx].td_moduleName
        stosd
        mov     al, byte ptr [ebx].td_flags
        and     eax, 10h                        ;0=16, 10=32
        add     al, 10h                         ;16/32
        stosd
        xchg    eax, edx
        stosd                                   ;TDB
        mov     eax, dword ptr [ebx].td_hModule
        stosd
        mov     eax, dword ptr [ebx].td_hInstance
        stosd
        mov     eax, dword ptr [ebx].td_hQueue
        stosd
        mov     eax, dword ptr [ebx].td_pdb
        stosd
        mov     eax, dword ptr [ebx].td_hParent
        stosd
IFDEF   _W95_
        mov     eax, [ebx].td_pRing3TCB
        stosd
        xor     ecx, ecx
        movzx   eax, [ebx].td_TIB_Selctor
        call    Get_Selector
        jc      short @f
        ; eax=base, edx=limit, esi=ptr descriptor
        ; eax-10h should point to a threadDB
        cmp     [eax-10h].thdb_Type, K32OBJ_THREAD
        jne     short @f
        mov     ecx, [eax-10h].thdb_pProcess
@@:     mov     [edi], ecx
ENDIF
        clc
        ret

; In:   eax = HeadExe
;       ecx = number of tasks to skip
; Out:  eax = ptr taskDB if ecx=0
;       edi = taskDB     if ecx=0
;       edx = limit      if ecx=0
Next_Module:
        movzx   eax, [eax].ne_pnextexe
Walk_Modules:
        mov     edi, eax
        call    Get_Selector
        jc      short @f
        cmp     [eax].ne_signature, 454Eh ; 'NE'
        jne     short @f
        loop    short Next_Module
@@:     ret

; In:   ESI = ptr name
; Out:  CF=0: EBX = selector
;             EDX = linear address of module database
;             ESI = ptr module name
;             EDI = ptr input name
;       CF=1: Module not found
; EBX is preserved.
PUBPROC GetP16ModuleFromName
        DBGBRK  3
        call    GetSymbolLen
        jecxz   short P16MFN_Failed
        mov     edi, esi
        call    GetHeadExe
P16MFN_Loop:
        mov     ebx, eax                ; selector to return
        call    Get_Selector
        jc      short P16MFN_Failed
        DBGBRK  3
        cmp     [eax].ne_signature, 454Eh ; 'NE'
        jne     short P16MFN_Failed
        xchg    edx, eax
        ; Obtain the resident names table offset from the NE header.
        movzx   esi, [edx].ne_restab    ; resident names offset
        ; first entry is always the module name (lstring)
        add     esi, edx
        cmp     cl, [esi]
        jne     short P16MFN_Next
        inc     esi
        call    strncmp
        jnc     short P16MFN_Done
P16MFN_Next:
        movzx   eax, [edx].ne_pnextexe
        jmp     short P16MFN_Loop

P16MFN_Failed:
FP16EP_Failed:
        stc
P16MFN_Done:
        ret

; In:   EDX = ptr module database
; Out:  CF=0: EDX:EAX = entry point
;       CF=1: Module not found or no entry point
; EBX is preserved.
PUBPROC Mod16_EntryPoint
        DBGBRK  3
        movzx   ecx, word ptr [edx].ne_csip[2]
        jecxz   short FP16EP_Failed
        ; translate seg# to selector
        imul    ecx, SIZE SEGMENT_TABLE_STRUC
        movzx   eax, [edx].ne_segtab
        add     ecx, eax
        movzx   eax, word ptr [edx].ne_csip[0]
        movzx   edx, [edx+ecx-SIZE SEGMENT_TABLE_STRUC].sg_handle
        ret

SCODE_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------
MkSymbol macro a, b, c
        a&b = c
        endm

@VM     equ     8000h
@FL     equ     4000h
@DV     equ     2000h
@CB     equ     1000h
@TH     equ     0800h

VxdEventNum = 0
VxdEventLog macro txt, X
        vvxd = ($-SPWIN_Vxd_Control_Msgs)
        ifnb <X>
        vvxd = vvxd + X
        endif
        MkSymbol vxdEvent_, %VxdEventNum, vvxd

        ifnb <txt>
        db txt
        endif
        VxdEventNum = VxdEventNum + 1
        endm

; ---------------------------------------------------------------------------
SPWIN_Vxd_Control_Msgs:
  VxdEventLog 'Sys_Critical_Init'    ,@VM        ; 00   Sys_Critical_Init
  VxdEventLog 'Device_Init'          ,@VM        ; 01   Device_Init
  VxdEventLog 'Init_Complete'        ,@VM        ; 02   Init_Complete
  VxdEventLog 'Sys_VM_Init'          ,@VM        ; 03   Sys_VM_Init
  VxdEventLog 'Sys_VM_Terminate'     ,@VM        ; 04   Sys_VM_Terminate
  VxdEventLog 'System_Exit'          ,@VM        ; 05   System_Exit
  VxdEventLog 'Sys_Critical_Exit'    ,@VM        ; 06   Sys_Critical_Exit
  VxdEventLog 'Create_VM'            ,@VM        ; 07   Create_VM
  VxdEventLog 'VM_Critical_Init'     ,@VM        ; 08   VM_Critical_Init
  VxdEventLog 'VM_Init'              ,@VM        ; 09   VM_Init
  VxdEventLog 'VM_Terminate'         ,@VM        ; 0A   VM_Terminate
  VxdEventLog 'VM_Not_Executeable'   ,@VM+@FL    ; 0B   VM_Not_Executeable
  VxdEventLog 'Destroy_VM'           ,@VM        ; 0C   Destroy_VM
  VxdEventLog 'VM_Suspend'           ,@VM        ; 0D   VM_Suspend
  VxdEventLog 'VM_Resume'            ,@VM        ; 0E   VM_Resume
  VxdEventLog 'Set_Device_Focus'     ,@VM+@DV    ; 0F   Set_Device_Focus
  VxdEventLog 'Begin_Message_Mode'   ,@VM        ; 10   Begin_Message_Mode
  VxdEventLog 'End_Message_Mode'     ,@VM        ; 11   End_Message_Mode
  VxdEventLog 'Reboot_Processor'     ,@VM        ; 12   Reboot_Processor
  VxdEventLog 'Query_Destroy'        ,@VM        ; 13   Query_Destroy
  VxdEventLog 'Debug_Query'          ,@VM        ; 14   Debug_Query
  VxdEventLog 'Begin_PM_App'         ,@VM+@FL+@CB; 15   Begin_PM_App
  VxdEventLog 'End_PM_App'           ,@VM+@CB    ; 16   End_PM_App
  VxdEventLog 'Device_Reboot_Notify' ,@VM        ; 17   Device_Reboot_Notify
  VxdEventLog 'Crit_Reboot_Notify'   ,@VM        ; 18   Crit_Reboot_Notify
  VxdEventLog 'Close_VM_Notify'      ,@VM+@FL    ; 19   Close_VM_Notify
  VxdEventLog 'Power_Event'                      ; 1A   Power_Event
IFDEF   _W95_
  VxdEventLog 'Sys_Dynamic_Device_Init'          ; 1B   SYS_DYNAMIC_DEVICE_INIT
  VxdEventLog 'Sys_Dynamic_Device_Exit'          ; 1C   SYS_DYNAMIC_DEVICE_EXIT
  VxdEventLog 'Create_Thread'         ,@VM+@TH   ; 1D   CREATE_THREAD
  VxdEventLog 'Thread_Init'           ,@TH       ; 1E   THREAD_INIT
  VxdEventLog 'Terminate_Thread'      ,@TH       ; 1F   TERMINATE_THREAD
  VxdEventLog 'Thread_Not_Executeable',@TH       ; 20   THREAD_Not_Executeable
  VxdEventLog 'Destroy_Thread'        ,@TH       ; 21   DESTROY_THREAD
  VxdEventLog 'PnP_New_Devnode'                  ; 22   PNP_NEW_DEVNODE
  VxdEventLog 'WIN32_Device_IO_Control'          ; 23   W32_DEVICEIOCONTROL
  VxdEventLog 'Sys_VM_Terminate2'                ; 24   SYS_VM_TERMINATE2
  VxdEventLog 'System_Exit2'                     ; 25   SYSTEM_EXIT2
  VxdEventLog 'Sys_Critical_Exit2'               ; 26   SYS_CRITICAL_EXIT2
  VxdEventLog 'VM_Terminate2'                    ; 27   VM_TERMINATE2
  VxdEventLog 'VM_Not_Executeable2'              ; 28   VM_NOT_EXECUTEABLE2
  VxdEventLog 'Destroy_VM2'                      ; 29   DESTROY_VM2
  VxdEventLog 'VM_Suspend2'                      ; 2A   VM_SUSPEND2
  VxdEventLog 'End_Message_Mode2'                ; 2B   END_MESSAGE_MODE2
  VxdEventLog 'End_PM_App2'                      ; 2C   END_PM_APP2
  VxdEventLog 'Device_Reboot_Notify2'            ; 2D   DEVICE_REBOOT_NOTIFY2
  VxdEventLog 'Critical_Reboot_Notify2'          ; 2E   CRIT_REBOOT_NOTIFY2
  VxdEventLog 'Close_VM_Notify2'                 ; 2F   CLOSE_VM_NOTIFY2
  VxdEventLog 'Get_Contention_Handler'           ; 30   GET_CONTENTION_HANDLER
  VxdEventLog 'Kernel32_Initialized'             ; 31   KERNEL32_INITIALIZED
  VxdEventLog 'Kernel32_Shutdown'                ; 32   KERNEL32_SHUTDOWN
ENDIF
NUM_VXD_EVENT = VxdEventNum
  VxdEventLog <>                               ; End of list

mkRef   macro   n
        dw vxdEvent_&n
        endm

SPWIN_Control_Table label word
        x = 0
        REPT VxdEventNum
        mkRef %x
        x = x + 1
        ENDM

unknown_vxd_event:
        pop     ebx
        call    Log_Event
        db      d_text,40,'UNKNOWN',d_lf,d_sub

PUBPROC LogEventVxd
        mov     edi, OFFSET32 Display_Buffer + 80
        push    edi                     ; save for d_text at the end

        call    PrintfAt
        db      'VxDMsg  ',d_r32,R_EAX,' ',d_ret

        DBGBRK  3
        mov     ebx, [ebp].R_EAX
        cmp     ebx, NUM_VXD_EVENT
        jae     short unknown_vxd_event

        movzx   eax, word ptr SPWIN_Control_Table[2*ebx]
        mov     cl,  byte ptr SPWIN_Control_Table[2*ebx+2]
        mov     ebx, eax
        sub     ecx, eax
        and     ecx, 3fh
        and     ah, 7
        lea     esi, SPWIN_Vxd_Control_Msgs[eax]
        rep     movsb
        mov     [edi], cl

        shl     bh, 1
        jnc     short @f
        call    PrintfAt
        db      ', VM=',d_r32,R_EBX,d_ret
@@:     shl     bh, 1
        jnc     short @f
        call    PrintfAt
        db      ', Flags=',d_r32,R_EDX,d_ret
@@:     shl     bh, 1
        jnc     short @f
        call    PrintfAt
        db      ', Device=',d_r16,R_EDX,d_ret
@@:     shl     bh, 1
        jnc     short @f
        call    PrintfAt
        db      ', CB=',d_r32,R_EDI,d_ret
IFDEF   _W95_
@@:     shl     bh, 1
        jnc     short @f
        call    PrintfAt
        db      ', TH=',d_r32,R_EDI,d_ret
ENDIF
@@:     pop     ebx
        call    Log_Event
        db      d_text,80,d_lf,d_sub

PUBPROC SegNotAvailable
        test    al, 4
        jnz     short has_ldt
no_seg: reportError 'Seg Not Available.'

has_ldt:sldt    bx
        and     bx, not 7
        jz      short no_seg

PUBPROC no_ldt
        reportError 'LDT Not Available.'

PUBPROC Cmd_Heap
        DBGBRK  3
        mov     ecx, BURGERMASTER_LinAddr
        jecxz   short SegNotAvailable
        movzx   eax, [ecx].bm_entries
        push    ecx                     ;sl_context
        push    eax                     ;sl_limit
        push    0                       ;sl_index
        call    scrollLines
        db      ' Hndl  Base      Length   #sel Owner',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        mov     eax, [esi].bm_1starena
        jecxz   short gHeapDisp
gHeapNext:
        mov     eax, [esi+eax].gh_next
        loop    short gHeapNext
gHeapDisp:
        add     esi, eax
        movsx   edx, [esi].gh_owner
        push    edx
        push    dword ptr [esi].gh_selcount
        push    [esi].gh_bytes
        push    [esi].gh_base
        push    dword ptr [esi].gh_handle
        call    Printf
        db      ' ',d_h16,'  ',d_h32,'  ',d_h32,'  ',d_h08
        db      '  ',d_h16,'  ',d_ret
        DBGBRK  3
        lea     ecx, [edx+7]            ; -7..0 => 0..7
        cmp     ecx, 8
        jb      short special_owner
        xchg    eax, edx
        push    edi
        call    ModuleNameFromHandle
        pop     edi
        push    esi
        call    PrintfAt
        db      d_fname,d_ret
ghDispDone:
        ret

special_owner:
        push    ecx
        call    PrintfAt
        _table  special_owners
        db      d_ret
        ret

PUBPROC Cmd_Task
        DBGBRK  3
        call    GetHeadTDB
        jc      SegNotAvailable
        push    eax                     ;sl_context
        xor     ecx, ecx
        call    Walk_Tasks
        neg     ecx
        push    ecx                     ;sl_limit
        push    0                       ;sl_index
        call    scrollLines
        db      ' TaskName  Sz TaskDB hModule hInst hQueue  PSP  Parent'
        ;         xxxxxxxx  16  0000   0000   0000   0000   0000  0000
IFDEF   _W95_
        db      ' Ring3TCB  Process'
        ;         00000000  00000000
ENDIF
        db      d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        xchg    eax, esi
        inc     ecx
        call    Walk_Tasks

        xchg    ebx, eax
        mov     edx, edi
IFDEF   _W95_
        sub     esp, 4*10
ELSE
        sub     esp, 4*8
ENDIF
        mov     edi, esp
        DBGBRK  3
        call    CollectTDBInfo

        ; ebx=thdb_pProcess
        ; edx=td_pRing3TCB
        call    Printf
        db      ' ',d_fname,d_col,11,d_deci,'  ',d_h16,'   ',d_h16
        db      '   ',d_h16,'   ',d_h16,'   ',d_h16,'  ',d_h16
IFDEF   _W95_
        db      '  ',d_h32,'  ',d_h32
ENDIF
        db      d_ret
        ret

PUBPROC Cmd_Mod
        DBGBRK  3
        jnz     short disp_ModuleInfo

        call    GetHeadExe
        jc      SegNotAvailable
        push    eax                     ;sl_context
        xor     ecx, ecx
        call    Walk_Modules
        neg     ecx                     ;total number of modules
        push    ecx                     ;sl_total
        push    0                       ;sl_index
        call    scrollLines
        ;         0000  xxxxxxxx
        db      ' hMod  Module    Filename',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        xchg    eax, esi
        inc     ecx
        call    Walk_Modules
        xchg    edx, eax

        lea     esi, [edx].ne_pfileinfo
        call    word_read_@esi
IFDEF   _W95_
        lea     ebx, 9[eax+edx]         ; pathname start at offset 9
ELSE
        lea     ebx, 8[eax+edx]         ; pathname start at offset 8
ENDIF
        ; Obtain the resident names table offset from the NE header.
        lea     esi, [edx].ne_restab    ; resident names offset
        call    word_read_@esi
        ; first entry is always the module name (lstring)
        lea     eax, [eax+edx+1]
        jnc     short @f
        mov     eax, OFFSET32 Zeros
@@:     push    eax
        push    edi                     ; hModule
        call    Printf
        db      ' ',d_h16,'  ',d_fname,d_col,17,d_text,63,d_ret
        ret

disp_ModuleInfo:
        DBGBRK  3
        call    Scan_Expression
        jnc     short disp_ModInfo1
        call    GetP16ModuleFromName
        ; CF=0: ebx = hMod, edx = linear address of hMod, ESI = ptr name
        jnc     short disp_ModInfo2

mod_notFound:
        reportError 'Module Not Found.'

disp_ModInfo1:
;       HandleToSelector ebx
        xchg    eax, ebx
        call    ModuleHandleFromSelector
        jc      short mod_notFound
        mov     ebx, eax
        call    ModuleNameFromHandle
        jc      short mod_notFound
        cmp     al, 'N'
        jne     short mod_notFound
        ; ecx = linear address of MDB
        ; esi = ptr module name
        mov     edx, ecx

disp_ModInfo2:
        ; ebx = hMod, edx = linear address of hMod, ESI = ptr name
        push    edx                     ;sl_context
        movzx   eax, [edx].ne_cseg      ;count of segments in segment table
        push    eax                     ;sl_total
        push    0                       ;sl_index

        push    dword ptr [edx].ne_usage
        push    dword ptr [edx].ne_heap
        push    dword ptr [edx].ne_stack
        movzx   eax, [edx].ne_pautodata
        movzx   ecx, [eax+edx].sg_handle
        jecxz   short @f
        HandleToSelector ecx
@@:     push    ecx
        push    dword ptr [edx].ne_flags
        movzx   eax, [edx].ne_expver    ; expected windows version num
        xor     ecx, ecx
        xchg    cl, ah
        push    eax
        push    ecx
        push    esi
        push    ebx                     ;ModuleDB
        movzx   esi, [edx].ne_pfileinfo
IFDEF   _W95_
        lea     ebx, 9[edx+esi]         ; pathname start at offset 9
ELSE
        lea     ebx, 8[edx+esi]         ; pathname start at offset 8
ENDIF
        call    scrollLines
        db      'ModuleDB=',d_h16
        db      d_lf,'Module Name: ',d_fname
        db      d_lf,'Expected windows version: ',d_deci,'.',d_deci
        db      d_lf,'Flags=',d_h16
        db      d_lf,'Filename: ',d_text,70
        db      d_lf,'DGROUP=',d_h16
        db      '  Stack=',d_h16
        db      '  Heap=',d_h16
        db      '  Usage=',d_h16
        db      d_lf,' Seg#  Sel/Hnd  Type',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  4
        imul    ecx, SIZE SEGMENT_TABLE_STRUC
        movzx   edi, [esi].ne_segtab
        add     edi, esi
        add     edi, ecx                ; edi points to the segment info
        push    dword ptr [edi].sg_flags
        push    0                       ; attrib for flags
        push    dword ptr [edi].sg_handle
        inc     edx                     ; segment #
        push    edx
        call    Printf
        db      ' ',d_numb,NM_RJZRO+3,d_spc,5,d_h16,'   '
        ;       11h
        _bits   11h,8,'FIXED   MOVABLE CODE    DATA    '
        db      d_ret
        ret

disp_VxD_Services:
        DBGBRK  3
IFDEF   _W95_
        xor     ebx, ebx
        test    [edx].DDB_Flags, DDB_HAS_WIN32_SVCS
        jz      short @f
        mov     eax, [edx].DDB_Win32_Service_Table
        test    eax, eax
        jns     short @f
        mov     ebx, [eax]
@@:     mov     Total_Win32Services, ebx
ENDIF
        push    edx                          ;sl_context
IFDEF   _W95_
        mov     eax, [edx].DDB_Service_Table_Size
        cmp     eax, ebx
        jae     short @f
        mov     eax, ebx
@@:     push    eax                          ;sl_total =max(stdsvc, w32svc)
ELSE
        push    [edx].DDB_Service_Table_Size ;sl_total
ENDIF
        push    0                            ;sl_index

IFDEF   _W95_
        xor     ebx, ebx
        test    [edx].DDB_Flags, DDB_HAS_WIN32_SVCS
        jz      short @f
        mov     eax, [edx].DDB_Win32_Service_Table
        test    eax, eax
        jns     short @f
        mov     ebx, [eax]
@@:     push    ebx
ENDIF
        push    dword ptr [edx].DDB_V86_API_Proc
        push    dword ptr [edx].DDB_Init_Order
        movzx   eax, [edx].DDB_SDK_Version
        xor     ecx, ecx
        xchg    cl, ah
        push    eax
        push    ecx

IFDEF   _W95_
        test    [edx].DDB_Flags, DDB_DYNAMIC_VXD
        setne   bl
        push    ebx
ENDIF
        push    dword ptr [edx].DDB_PM_API_Proc
        push    dword ptr [edx].DDB_Reference_Data
        push    dword ptr [edx].DDB_Req_Device_Number

        push    dword ptr [edx].DDB_Control_Proc
        push    edx
        lea     ebx, [edx].DDB_Name
        push    ebx
        call    scrollLines
        db      '   Name: ',d_fname,d_col,23,      'DDB: ',d_h32
        db d_col,38,'Ctrl Proc: ',d_h32
        db d_lf,'     ID: ',d_h16,   d_col,17,'Ref. Data: ',d_h32
        db d_col,41,   'PM API: ',d_h32
IFDEF   _W95_
        db '  DynLoad: '
        _table  YN_Table
ENDIF
        db d_lf,'Version: ',d_deci,'.',d_deci
        db d_col,17,'InitOrder: ',d_h32
        db d_col,40,  'V86 API: ',d_h32
IFDEF   _W95_
        db '  W32svcs: ',d_deci
        db d_lf,' svc#  Address   Name'
        db d_col,52,'WIN32: svc#  Address  Param'
ENDIF
        db d_sub
        ; will be called by scrollLines
        ; edi = OFFSET32 Display_Buffer
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
IFDEF   _W95_
        push    [esi].DDB_Win32_Service_Table
        cmp     edx, [esi].DDB_Service_Table_Size
        jae     short @f
ENDIF
        movzx   ebx, [esi].DDB_Req_Device_Number
        mov     eax, [esi].DDB_Service_Table_Ptr
        mov     eax, [eax+edx*4]
        push    eax
        push    edx
        call    PrintfAt
        db      ' ',d_h16,'  ',d_h32,'  ',d_ret
        DBGBRK  3
        ; ebx = ID, EDX = service no.
        xchg    eax, ebx
        ; EAX = VxdID
        ; EDX = Service No.
IFDEF   _W95_
        push    edx
        call    GetVxdServiceName
        pop     edx
@@:     pop     esi                     ;DDB_Win32_Service_Table
        cmp     edx, Total_Win32Services
        jae     short @f
        push    dword ptr [esi+edx*8][4] ;number of parameters
        push    dword ptr [esi+edx*8][8] ;service address
        push    edx                     ;win32 service number
        call    PrintfAt
        db      d_col,59,d_h16,'  ',d_h32,'  ',d_deci,d_ret
@@:     ret
ELSE
        jmp     GetVxdServiceName
ENDIF

PUBPROC Cmd_VxD
        DBGBRK  3
        call    GetSymbolLen
        jecxz   short display_VxDs
        call    FindVxdByName
        jnc     disp_VxD_Services
display_VxDs:
        mov     esi, VMM_DDB_BASE
        push    esi                     ;sl_context
        xor     ecx, ecx
@@:     inc     ecx
        mov     esi, [esi].DDB_Next
        test    esi, esi
        jnz     short @b
        push    ecx                     ;sl_total
        push    esi                     ;sl_index
        call    scrollLines
        db      'Name',d_col,10,'Vers  DevId CtrlProc  PM API    V86 API   '
IFDEF   _W95_
        db      'DDB',d_spc,6,'Dyn #VxDsvc #W32svc',d_sub
ELSE
        db      'Ref.Data  DDB',d_spc,7,'#Services',d_sub
ENDIF
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        jecxz   short vxd_Disp
@@:     mov     esi, [esi].DDB_Next
        loop    short @b
vxd_Disp:
IFDEF   _W95_
        xor     ebx, ebx
        bt      [esi].DDB_Flags, DDB_HAS_WIN32_SVCS_BIT
        jnc     short @f
        ; VMM.INCs dated before 07/95 do not have DDB_Size defined
;;      cmp     [esi].DDB_Size, SIZE(VxD_Desc_Block)
;;      jne     short @f
        mov     eax, [esi].DDB_Win32_Service_Table
        test    eax, eax
        jns     short @f
        mov     ebx, [eax]
@@:     push    ebx
        push    dword ptr [esi].DDB_Service_Table_Size
        bt      [esi].DDB_Flags, DDB_DYNAMIC_VXD_BIT
        setc    bl
        push    ebx
        push    esi
ELSE
        push    dword ptr [esi].DDB_Service_Table_Size
        push    esi
        push    dword ptr [esi].DDB_Reference_Data
ENDIF
        push    dword ptr [esi].DDB_V86_API_Proc
        push    dword ptr [esi].DDB_PM_API_Proc
        push    dword ptr [esi].DDB_Control_Proc
        push    dword ptr [esi].DDB_Req_Device_Number
        movzx   eax, [esi].DDB_SDK_Version
        xchg    cl, ah
        push    eax
        push    ecx
        lea     ebx, [esi].DDB_Name
        call    Printf
        db      d_text,t_fill+8,'  '
        db      d_deci,'.',d_deci,d_col,16
        db      d_h16,'  ',d_h32,'  ',d_h32,'  '
IFDEF   _W95_
        db      d_h32,'  ',d_h32,'  '
        _table  YN_Table
        db      '  ',d_deci,d_col,73,d_deci,d_ret
ELSE
        db      d_h32,'  ',d_h32,'  ',d_h32,'  ',d_deci,d_ret
ENDIF
        ret

YN_Table        db 1,'NY'

; ***************************************************************************
;
; ***************************************************************************

PUBPROC Terminate_Current_Task
        ; ebx = return code     if CF=0
        DBGBRK  3
        sbb     eax, eax
        or      ebx, eax

        ; Figure out what type of app the current task is.
        ; If P16/V86 task use INT 21, ah=4c
        ; If P32 task, call ExitProcess( PID ): kernel32.214

        mov     eax, [ebp].R_CS
        test    eax, eax
        js      short Terminate_V86Task

        test    al, 3
        jz      short Cannot_Terminate

        lar     esi, eax
        bt      esi, 22
        jc      short Terminate_Win32Task
        mov     eax, SPWIN_P16Int21Ptr
        mov     edx, SPWIN_P16Selector
go2_cs_eip:
        mov     [ebp].R_EIP, eax
        mov     word ptr [ebp].R_CS, dx
        jmp     SPWIN_Return

Terminate_Win32Task:
IFDEF   _W95_
        push    ebx
        mov     esi, OFFSET32 @@ExitProcess
        call    P32AddressFromName
        jc      short Cannot_Terminate
        ; edx:ebx = address for the name
        cmp     edx, [ebp].R_CS
        jne     short Cannot_Terminate
        mov     eax, Kernel32_DataSelector
        cmp     eax, [ebp].R_SS
        jne     short Cannot_Terminate
        ; now simalate a call to ExitProcess
        mov     esi, [ebp].R_ESP
        sub     esi, 8                          ;room for addr,exitcode
        pop     edx                             ;exitcode
        mov     eax, [ebp].R_EIP
        call    qword_write_@esi
        jc      short Cannot_Terminate
        mov     [ebp].R_ESP, esi
        mov     [ebp].R_EIP, ebx
        jmp     SPWIN_Return

;       VxDcall _VWIN32_IsClientWin32
;       test    eax, eax
;       jz      short Cannot_Terminate
;       VMMcall Get_Cur_Thread_Handle
;       mov     ebx, [edi].R0TCB_VMHandle
;       DBGBRK  3
;       ; ebx=VM, edi=Thread
;       VxDcall VWIN32_TerminateApp
;       DBGBRK  3
;       ret

ENDIF
Cannot_Terminate: reportError 'Cannot Terminate.'

Terminate_V86Task:
        mov     bh, 4ch
        mov     word ptr [ebp].R_EAX, bx ; ah=4c, al=ret code
        movzx   eax, SPWIN_V86_Int21Off
        mov     dx, SPWIN_V86_Segment
        jmp     go2_cs_eip

IFDEF   _W95_
@@ExitProcess   db 'ExitProcess',0
ENDIF

PUBPROC Terminate_Current_VM
        DBGBRK  3
        call    Restore_CPU_Registers
        add     esp, 4
        pushfd
        push    cs
        push    OFFSET32 Jump_Crash_Cur_VM
        push    eax                     ; as R_Fault
        call    Save_CPU_Registers
        jmp     SPWIN_Return

Jump_Crash_Cur_VM:
        DBGBRK  3
        VMMcall Crash_Cur_VM
        DBGBRK  3
        jmp     Jump_Crash_Cur_VM

LCODE_ENDS
END

