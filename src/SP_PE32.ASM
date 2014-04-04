title.  SoftProbe - PE/Module32 support.
; **HACK**

SP_PE32 EQU 1
INCLUDE SP_DEFS.INC 
INCLUDE SP_KRNL.INC 
INCLUDE SPAPI.INC

IFDEF   _W95_
INCLUDE VWIN32.INC
ENDIF ; _W95_

EXTPROC SP_MAIN Display_PDE
; ---------------------------------------------------------------------------
LDATA_SEG
; ---------------------------------------------------------------------------

IFDEF   _W95_
PUBDWRD Module32_List         0
PUBDWRD Module32_List_Ptr     0
PUBDWRD Kernel32_CodeSelector 0
PUBDWRD Kernel32_DataSelector <0,0> ; selector, kernel32 seg#4.DD_base
PUBDWRD VWIN32_State_Info_Ptr <SIZE VxD_Desc_Block>
ENDIF ; _W95_

LDATA_ENDS

; ---------------------------------------------------------------------------
SCODE_SEG       ; Safe code area (No Pushes inside calls)
; ---------------------------------------------------------------------------

IFDEF   _W95_
PUBPROC GetSysSpaceIndirect
        lodsd
        mov     esi, eax
        rol     eax, 2
        and     al, 1111b
        cmp     al, 0010b               ; dword aligned + 80000000-BFFFFFFC
        je      qword_read_@esi         ;
k32info_failed:
        stc
        ret

; In:   ebx = kernel32 hMod
PUBPROC InstallModule32Hook
        mov     esi, [ebx].td3_PE_Header
        movzx   edx, [esi].pe_SizeOfOptionalHdr
        ; esi+edx+pe_OptHdrMagic points to the first section (_FREQASM)
        mov     ebx, [esi+edx].pe_OptHdrMagic.pes_SectionRVA
        mov     ecx, [esi+edx].pe_OptHdrMagic.pes_VirtualSize
        add     ebx, [esi].pe_ImageBase ; +base of code
        ; Now locate the starter routine
@@:     mov     esi, OFFSET32 Kernel32TaskStarter
        lodsb
        mov     edi, ebx
        repne   scasb
        jne     short k32info_failed
        mov     ebx, edi
        xchg    eax, ecx
        mov     ecx, Kernel32TaskStarterSize-1
        repe    cmpsb
        xchg    eax, ecx
        jne     short @b
        DBGBRK  3
        ; put our hook 'int3, ret' instead of 'jmp eax'
        dec     edi
        dec     edi
        mov     word ptr [edi], 0c3cch
        mov     Kernel32_LoaderHookAddr, edi
        ret

; In:   EDX = points to an array of pointers (4 bytes/mod)
;       ECX = index
; Out:  EDI = ptr WIN32_TDB_STRUC
;       ESI = PE-Header
Walk_Module32s:
        call    FirstModule32
        jnc     short WalkMod32Next
        ret
WalkMod32Loop:
        call    NextModule32
        jc      short WalkMod32Done
WalkMod32Next:
        loop    WalkMod32Loop
        mov     edi, [edx]
WalkMod32Done:
        ret

Walk_AddrCntx:
        mov     eax, CurMemoryContext
        mov     edi, eax
walk_ctx1:
        cmp     eax, ebx
        je      short walk_ctx3
        cmp     [eax].ac_Signature, 44434443h ; 'CDCD'?
        jne     short walk_ctx3
        loop    short walk_ctx2
        ret
walk_ctx2:
        mov     eax, [eax].ac_NextAddrCntx
        cmp     eax, edi                ; loops back to 1st?
        jne     short walk_ctx1
walk_ctx3:
        ret

; In:   eax=Address context handle
PUBPROC GetContextInfo
        mov     esi, [eax].ac_OtherInfo
        mov     ecx, [esi].oac_MinAddr
        mov     ebx, [esi].oac_MaxAddr
        mov     edx, [esi].oac_Mutex
        mov     esi, [eax].ac_NumTables
        mov     edi, [eax].ac_PageTablePtr
        shl     ecx, 12                 ; Min address
        shl     ebx, 12
        or      ebx, 0fffh              ; Max address
        ret

; In:   None
; Out:  CF=1 :  Not found
;       CF=0 :  edx = hMod32
;               ebx = Base Address
;               esi = PE-Header
PUBPROC FirstModule32
        mov     edx, Module32_List
        test    edx, edx
        jnz     short Mod32FindLoop
Mod32NotFound:
        stc
        ret

; In:   edx = hMod32
; Out:  CF=1 :  Not found
;       CF=0 :  edx = hMod32
;               ebx = Base Address
;               esi = PE-Header
PUBPROC NextModule32
        add     edx, 4
Mod32FindLoop:
        cmp     dword ptr [edx], 0
        je      short NextModule32

; In:   EDX = hMod32
; Out:  ESI = PE-Header
;       EBX = Base address
PUBPROC Mod32BasePtrs
        mov     ebx, [edx]              ; ptr WIN32_TDB_STRUC
        mov     esi, [ebx].td3_PE_Header
        cmp     word ptr [esi], 4550h   ; 'PE'?
        jne     short Mod32NotFound
        mov     ebx, [esi].pe_ImageBase ; base of code
        ret

; In:   edx = hMod32
; Out:  CF=1 :  Not visible
;       CF=0 :  Is visible
; Kills:eax, ebx, ecx
PUBPROC CheckPEModuleVisible
        DBGBRK  4
        ; Check the memory context
        mov     ebx, [edx]              ; ptr WIN32_TDB_STRUC
        mov     eax, [ebx].td3_PE_Header
        mov     eax, [eax].pe_ImageBase
        test    eax, 0ffc00000h
        jz      short CPEMV_Unvisible   ; if eax <  00400000h
        js      short CPEMV_Done        ; if eax >= 80000000h
        movzx   ecx, [ebx].td3_Usage    ; number of linked modules
        jecxz   short CPEMV_Unvisible
        mov     ebx, [ebx].td3_ModRef   ; ptr linked modules
CPEMV_LoopContext:
        test    ebx, ebx
        jz      short CPEMV_Unvisible
        mov     eax, [ebx].mr_PtrProcessDB
        mov     eax, [eax].pdb32_MemContext
        cmp     eax, CurMemoryContext
        je      short CPEMV_Done        ; if its the owner of current context
        mov     ebx, [ebx].mr_NextInstModref
        loop    short CPEMV_LoopContext
CPEMV_Unvisible:
        stc
CPEMV_Done:
        ret

; In:   EAX = address
;       ESI = PE-Header
; Out:  CF=1  error
;       CF=0  EAX = address RVA, EBX=base
PUBPROC CheckModuleAddressSpace
        DBGBRK  3
        mov     ebx, [esi].pe_ImageBase
        sub     eax, ebx
        cmp     [esi].pe_SizeOfImage, eax
        ret

; In:   esi = PE-Header
;       edx = hMod32
;       eax = linear address
; Out:  CF=1 :  Not found
;       CF=0 :  ebx = Offset within section
;               esi = Ptr section = section name
;               eax = ptr filename.ext

PUBPROC PESectionNameFromAddress
        movzx   ecx, [esi].pe_NumberOfSections
        jecxz   short PESNFA_NotFound

        sub     eax, [esi].pe_ImageBase ; convert address to relative
        jc      short PESNFA_NotFound
        movzx   ebx, [esi].pe_SizeOfOptionalHdr
        lea     esi, [esi+ebx].pe_OptHdrMagic

PESNFA_LoopSection:
        mov     ebx, eax
        sub     ebx, [esi].pes_SectionRVA ; Offset within section
        cmp     ebx, [esi].pes_PhysSize
        jb      short GetModule32FileName

PESNFA_NextSection:
        add     esi, SIZE PE_SECTION_HEADER_STRUC
        loop    short PESNFA_LoopSection
PESNFA_NotFound:
PEXS_NotFound:
        stc
        ret

PUBPROC GetModule32FileName
        DBGBRK  4
        mov     eax, [edx]              ; Points to a WIN32_TDB_STRUC struc
        mov     eax, [eax].td3_ModuleName ; ptr filename.ext
        clc
        ret

; In:   ESI = ptr PE Header
; Out:  CF = 1: Not found, or not present
;       CF = 0: EAX = ptr export directory (actual address)
PUBPROC Find_PE_ExportSection
        DBGBRK  4
        mov     eax, [esi].pe_Directories[DIR_EXPORT].pedd_RVA
        test    eax, eax
        jz      short PEXS_NotFound
        add     eax, [esi].pe_ImageBase
        ret

; In:   eax = ptr PE_EXPORT_DIR_STRUC
;PUBPROC P32ExportedNameInfo
;        mov     ecx, [eax].pex_NumberOfFunctions
;        mov     edi, [eax].pex_OrdinalBase     ;ord base
; In:   eax = ptr PE_EXPORT_DIR_STRUC
; Out:  eax = Number of names
;       esi = Address of names
PUBPROC AddressOfP32ExportedNames
        mov     esi, [eax].pex_AddrOfNames
        mov     eax, [eax].pex_NumberOfNames
        cmp     eax, 1                  ; cf=1 if eax=0
        ret

PUBPROC repne_scasw
        repne   scasw
        ret

; In:   ebx = base address
;       ecx = ordinal number
;       eax = ptr PE_EXPORT_DIR_STRUC
;       EDX = hMod32
PUBPROC Module32AddressForOrdinal
        sub     ecx, [eax].pex_OrdinalBase ;ord#-base
        cmp     ecx, [eax].pex_NumberOfFunctions
        jae     short PEXS_NotFound

        mov     eax, [eax].pex_AddrOfFunctions
        add     eax, ebx                ;+base
        add     ebx, [eax+ecx*4]
        mov     edx, Kernel32_CodeSelector
        clc
        ret

; In:   ESI = ptr PE Header
;       EAX = address to find (RVA)
;       EBX = base address
;       EBP = address of buffer for name
;       EDX = hMod32
PUBPROC FindPEXportFromAddress
        DBGBRK  3
        mov     ecx, [esi].pe_Directories[DIR_EXPORT].pedd_RVA
        jecxz   short PEXS_NotFound
        mov     ebx, [esi].pe_ImageBase
        lea     esi, [ebx+ecx]          ; esi = ptr PE_EXPORT_DIR_STRUC
        mov     ecx, [esi].pex_NumberOfFunctions
        jecxz   short PEXS_NotFound
        mov     edi, [esi].pex_AddrOfFunctions
        add     edi, ebx                ; += base
        repne   scasd
        jne     short PEXS_NotFound

GetTheXportedName:
        DBGBRK  3
        not     ecx                     ; -1-ecx
        add     ecx, [esi].pex_NumberOfFunctions ; the actual index
        xchg    eax, ecx
        mov     ecx, [esi].pex_NumberOfNames
        mov     edi, [esi].pex_AddrOfNameOrdinals
        add     edi, ebx                ; +base
        call    repne_scasw
        jne     short PEXFA_ByOrdinal

        not     ecx                     ; -1-ecx
        add     ecx, [esi].pex_NumberOfNames ; the actual index
        mov     esi, [esi].pex_AddrOfNames
        add     esi, ebx
        mov     eax, [esi+ecx*4]
        mov     esi, [edx]              ; esi points to a WIN32_TDB_STRUC
        mov     esi, [esi].td3_ModuleName ; ptr filename.ext
        mov     edi, ebp
        xor     ecx, ecx
        mov     cl, 8                   ; max 8 chars
@@:     cmp     [esi], ch
        je      short @f
        movsb
        cmp     byte ptr [esi], '.'
        loopne  short @b
@@:     lea     esi, [eax+ebx]          ; ptr name
        mov     al, '.'
        stosb
        mov     cl, 40                  ; max 40 chars

        ; Fall through strncpy
ENDIF ; _W95_
PUBPROC strncpy
        lodsb
        stosb
        cmp     al, 0
        loopne  strncpy
        mov     [edi], ch
        dec     edi
;       clc
        ret

IFDEF   _W95_
PEXFA_ByOrdinal:
        add     eax, [esi].pex_OrdinalBase
        mov     esi, [edx]              ; esi points to a WIN32_TDB_STRUC
        mov     esi, [esi].td3_ModuleName ; ptr filename.ext
        mov     edi, ebp

        DBGBRK  4
        push    eax                     ; ordinal number
        push    esi
        call    PrintfAt
        db      d_fname,'.',d_h16,d_ret
        ; cf=0
        ret

; In:   ESI = ptr name
;       ECX = length of the name
; Out:  CF = 1 not found
;       CF = 0 : EDX = hMod32
PUBPROC GetP32ModuleFromName
        DBGBRK  4
        mov     edi, esi
        call    FirstModule32
        jc      short P32MFN_Return

P32MFN_ModLoop:
        ; edx = hMod32
        ; ebx = base address
        ; esi = PE-Header
        mov     esi, [edx]
        mov     esi, [esi].td3_ModuleName ; ptr NAME.EXT
        call    strncmp
        jc      short P32MFN_NextMod
        cmp     al, '.'
        jne     short P32MFN_NextMod
        lea     esi, [edi+ecx]          ; return pointer to end of name
        ret

P32MFN_NextMod:
        call    NextModule32
        jnc     short P32MFN_ModLoop
P32MFN_Return:
        mov     esi, edi
        ret

; In:   EDX = hMod32
; Out:  EDX:EBX = td3_Mod16DB:0
PUBPROC P32Mod16DBSelector
        mov     ebx, [edx]
        movzx   edx, [ebx].td3_Mod16DB
        xor     ebx, ebx
        ret

; In:   eax = index
;       ebx = base address (module-base or sym-base)
;       ebp = ptr Address of names
;       esi = ptr name to compare
;       cl  = length of name
; Out:  CF=0 if found
;       ESI updated, all other registers except eax are preserved
PUBPROC CompareP32ExportedName
        DBGBRK  3
        mov     edi, [ebp+eax*4]        ;*name
        add     edi, ebx                ;+base
        call    strncmp
        jc      short failure_return
        test    ah, ah                  ; 0?
        jnz     short failure_return
        add     esi, ecx
;       clc
        ret

failure_return:
        stc
        ret

; In:   ESI = ptr export section
;       EBX = base for export section
;       EAX = index to the name table
;       EDX = hMod32
; Out:  CF=0 if ok
;               edx:ebx = address for the name
PUBPROC GetP32IndexedAddress
        ; From the name index, get the hint which is the index to the
        ; function table.
        shl     eax, 1                  ;*2
        add     eax, [esi].pex_AddrOfNameOrdinals
        movzx   eax, word ptr [eax+ebx]
        cmp     eax, [esi].pex_NumberOfFunctions
        jae     short failure_return

        add     ebx, [esi].pex_AddrOfFunctions
        mov     ebx, [ebx+4*eax]        ;address RVA
        mov     edx, [edx]              ;ptr WIN32_TDB_STRUC
        mov     edx, [edx].td3_PE_Header
        add     ebx, [edx].pe_ImageBase ;+base of code
        mov     edx, Kernel32_CodeSelector
        clc
        ret

; In:   ebx = ptr process DB
; Out:  eax = ptr module name
PUBPROC GetProcessOwnerName
        mov     eax, [ebx].pdb32_TDB16
        call    ModuleNameFromHandle
        jnc     short @f
        movzx   esi, [ebx].pdb32_ModTableIndex
        mov     eax, Module32_List
        mov     esi, [eax+esi*4]
        mov     esi, [esi].td3_ModuleName ; ptr NAME.EXT
@@:     xchg    eax, esi
        ret

; In:   ebx = ptr WIN32_PROCESS_DATABASE
;       edi = ptr buffer for info
PUBPROC GetProcessInfo
        cmp     [ebx].pdb32_Type, K32OBJ_PROCESS
        jne     short @f
        mov     eax, [ebx].pdb32_Flags
        stosd
        call    GetProcessOwnerName
        stosd
        mov     eax, [ebx].pdb32_MemContext
        stosd
        mov     eax, [ebx].pdb32_ProcessHeap
        stosd
        mov     eax, [ebx].pdb32_BasePriority
        stosd
        mov     eax, [ebx].pdb32_PtrParentPdb32
        stosd
        mov     eax, [ebx].pdb32_PtrEnvDB
        stosd
        mov     eax, [ebx].pdb32_TDB16
        stosd
        movzx   eax, [ebx].pdb32_PSPSelector
        stosd
;;      movzx   eax, [ebx].pdb32_EnvSelector
;;      mov     eax, [ebx].pdb32_PSPLinAddr
;       mov     eax, [ebx].pdb32_PtrModRefList
;       mov     esi, [ebx].pdb32_PtrThreadList
;       movzx   ecx, [ebx].pdb32_NumThreads
        ret

@@:     reportError 'Invalid Process.'

; In:   ESI = process handle
;       ECX = number of threads to skip
Walk_ProcessThreads:
        VMMcall Get_Cur_VM_Handle
        ; ebx = Cur_VM_Handle
        VMMcall Get_Initial_Thread_Handle
        mov     edx, edi
walk_ps1:
        VMMcall Validate_Thread_Handle
        jc      short walk_ps3
        mov     eax, VWIN32_State_Info_Ptr
        mov     eax, [eax].vw32_R0TcbTdbxOffset
        mov     ebx, [edi+eax]                  ; our TDBX
        test    ebx, ebx
        jz      short walk_ps2
        mov     eax, [ebx].tdbx_ppdb            ; PPROCESDS_DATABASE
        cmp     [eax].pdb32_Type, K32OBJ_PROCESS ; (5)
        jne     short walk_ps3
        cmp     eax, esi                        ; same ps we are looking for?
        jne     short walk_ps2
        loop    short walk_ps2

        ; edi = Ring0TCB
        ; ebx = TDBX
        mov     edx, dword ptr [edi].R0TCB_ThreadId
        mov     eax, dword ptr [edi].R0TCB_Flags
        mov     esi, [ebx].tdbx_ppdb            ; PPROCESDS_DATABASE
        mov     ecx, [esi].pdb32_BasePriority
        mov     esi, [ebx].tdbx_ptdb            ; PTHREAD_DATABASE (R3TCB)
        mov     ebx, dword ptr [esi].thdb_TIBSelector
        ret

walk_ps2:
        VMMcall Get_Next_Thread_Handle
        cmp     edi, edx
        jne     short walk_ps1
walk_ps3:
        ret

; In:   ebx = Thread handle
;       edi = ptr buffer for info
PUBPROC GetThreadInfo
        mov     eax, dword ptr [ebx].R0TCB_ThreadId
        stosd
        mov     eax, dword ptr [ebx].R0TCB_Flags
        stosd

        ; Now we are going to get a pointer to R3TCB from our R0TCB.
        ; A pointer to a TDBX exists in R0TCBs, whoever its offset is
        ; calculated by the VWIN32 (I do not know if this means it can
        ; change in the future or not). This offset is always 8ch as I
        ; have seen it so far.
        ; VWIN32 gets this value from the 1st call to the
        ; VMM.00ff (_AllocateThreadDataSlot).

        mov     eax, VWIN32_State_Info_Ptr
        mov     eax, [eax].vw32_R0TcbTdbxOffset
        mov     ebx, [ebx+eax]                  ; our TDBX
        mov     eax, [ebx].tdbx_ptdb            ; PTHREAD_DATABASE
        cmp     [eax].thdb_Type, K32OBJ_THREAD  ; (6)
        jne     short gti_ret

        stosd
        mov     eax, dword ptr [eax].thdb_TIBSelector
        stosd
        mov     eax, [ebx].tdbx_ppdb            ; PPROCESDS_DATABASE
        cmp     [eax].pdb32_Type, K32OBJ_PROCESS ; (5)
        jne     short gti_ret

        stosd
        xchg    ebx, eax
        mov     eax, [ebx].pdb32_MemContext
        stosd
        call    GetProcessOwnerName
        stosd
        mov     eax, [ebx].pdb32_BasePriority
        stosd
gti_ret:ret

; In:   PARAM1 = linear address
; Out:  CF=0  ebx poits to the module name, esi=PE-Header, edx=hMod32
;       CF=1  Not found
PUBPROC CheckP32ModuleFromEntryPoint
        DBGBRK  3
        call    FirstModule32
        jc      short P32MFA_NotFound

P32MFA_LoopMod:
        ; edx = hMod32
        ; ebx = base address
        ; esi = PE-Header

        call    CheckPEModuleVisible
        jc      short P32MFA_NextMod
        DBGBRK  3
        mov     ebx, [edx]              ; ptr WIN32_TDB_STRUC
        mov     ebx, [ebx].td3_ModuleName  ; i.e. KERNEL32.DLL
        mov     eax, [esi].pe_AddrOfEntryPoint
        add     eax, [esi].pe_ImageBase ; base of code
        cmp     eax, [esp+PARAM1]
        je      short P32MFA_Done
P32MFA_NextMod:
        call    NextModule32
        jnc     short P32MFA_LoopMod
P32MFA_NotFound:
LM32S_NotFound:
        stc
P32MFA_Done:
        ret

; In:   EDX = hMod32
; Out:  CF=0 if found, then EBX=ptr symbolic info
; Kills ESI, EDI, ECX, EAX
PUBPROC LocateModule32Symbols
        mov     esi, [edx]
        mov     esi, [esi].td3_ModuleName ; ptr NAME.EXT
        call    str_len
        inc     ecx                     ; include '\0'
        mov     ebx, SymBuffer_Beg
        jmp     short LM32S_Find2
LM32S_Find1:
        add     ebx, [ebx].sh32_Size
LM32S_Find2:
        cmp     ebx, SymBuffer_End
        jae     short LM32S_NotFound
        cmp     [ebx].sh32_Size, 0
        je      short LM32S_NotFound
        cmp     [ebx].sh32_Type, SYM_P32
        jne     short LM32S_Find1
        mov     edi, [ebx].pex_Name
        add     edi, ebx                ;points to module name
        call    strncmp
        jc      short LM32S_Find1
        ret

PUBPROC FindExpRVA
        mov     edi, [ebx].pex_AddrOfFunctions
        mov     ecx, [edx]              ;ptr WIN32_TDB_STRUC
        mov     ecx, [ecx].td3_PE_Header
        add     edi, [ecx].pe_ImageBase ;points to table of functions
        mov     ecx, [ebx].pex_NumberOfFunctions
        repne   scasd
        ret

ENDIF ; _W95_

SCODE_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------

IFDEF   _W95_
; In:   EBX = linear address
;       ES:EDI = buffer for name
; Out:  CF=0  Prints section name + offset
;       CF=1  Not found
PUBPROC GetPESectionFromAddress
        DBGBRK  4

        push    ebx
        call    FirstModule32
        jc      short P32SFA_NotFound

P32SFA_LoopMod:
        ; edx = hMod32
        ; ebx = base address
        ; esi = PE-Header

        call    CheckPEModuleVisible
        jc      short P32SFA_NextMod
        DBGBRK  4
        mov     eax, [esp]              ;linear address
        call    PESectionNameFromAddress
        jc      short P32SFA_NextMod
        ; eax = ptr filename.ext
        ; esi = ptr section (same as section name)
        ; ebx = offset within section

        DBGBRK  4
        push    ebx                     ; offset within section
        mov     ebx, esi
        push    eax
        call    PrintfAt
        db      d_fname,'(',d_text,8,')+',d_h32,d_ret
        ; cf=0
        pop     ebx
        ret

P32SFA_NextMod:
        call    NextModule32
        jnc     short P32SFA_LoopMod

P32SFA_NotFound:
        pop     ebx
        stc
        ret


PUBPROC GetP32NameFromOrd
        ; EDX = hMod32
        add     esi, ecx                ; skip module name
        inc     esi                     ; skip '.'
        call    Parse_LineNoSkip
        FullCmd 'MDB'  JUMP_ADDRS <OFFSET32 P32Mod16DBSelector>
        db      0

        DBGBRK  4

        mov     edi, esi                ; edi=poiter to input string
        ; Is it Module32.ord#
        call    Scan_Hex
        jnc     short FindP32ExportByOrd ; ebx = ordinal number

        ; Is it one of exported names of this module?
        ; edx = hMod32
        ; edi = ptr name
        call    FindP32ExportByName
        mov     esi, edi
P32AFN_Done:
        ret

; In:   EDX = hMod32
;       EBX = ordinal number
; Out:  CF=0    EDX:EBX = address
PUBPROC FindP32ExportByOrd
        DBGBRK  3
        push    esi                     ;save it
        push    ebx

        call    CheckPEModuleVisible
        jc      short P32XBO_Return
        call    Mod32BasePtrs
        jc      short P32XBO_Return
        ; ESI = PE-Header
        ; EBX = Base address
        call    Find_PE_ExportSection
        jc      short P32XBO_SymOrds
        mov     ecx, [esp+0]            ; ordinal number
        mov     esi, [esp+4]
        call    Module32AddressForOrdinal
        jnc     short P32XBO_Return

P32XBO_SymOrds:
        ; EDX = hMod32
        call    LocateModule32Symbols
        jc      short P32XBO_Return
        ; EBX=ptr symbolic info
        mov     eax, ebx
        ; eax = ptr PE_EXPORT_DIR_STRUC
        pop     ecx                     ; ordinal number
        pop     esi
        ; ebx = base address for export section
        ; ecx = ordinal number
        ; eax = ptr PE_EXPORT_DIR_STRUC
        ; edx = hMod32
        jmp     Module32AddressForOrdinal

P32XBO_Return:
        pop     eax
        pop     esi
        ret

; In:   EAX = linear address
;       EDI = ptr buffer for name
; Out:  CF=0  found the name
;       CF=1  not found
PUBPROC GetPENameFromAddress
        DBGBRK  3
        push    ebp
        push    ebx
        push    eax
        mov     ebp, edi

        call    FirstModule32
        jc      short PENFA_NotFound

PENFA_ModLoop:
        ; edx = hMod32
        ; ebx = base address
        ; esi = PE-Header

        cmp     [esp], ebx
        jb      short PENFA_NextMod

        call    CheckPEModuleVisible
        jc      short PENFA_NextMod

        mov     eax, [esp]
        ; EAX = address to find
        ; ESI = PE-Header
        ; EBP = address of buffer for name
        ; EDX = hMod32
        call    CheckModuleAddressSpace
        jc      short PENFA_NextMod

        ; EAX = address RVA
        ; EBX = base address
        ; EBP = address of buffer for name
        ; ESI = PE-Header
        ; EDX = hMod32
        call    FindPEXportFromAddress
        jnc     short PENFA_Return

        DBGBRK  3
        sub     [esp], ebx              ; convert to RVA
        ; Now search in our symbolic list
        ; First locate the module
        ; EDX = hMod32
        call    LocateModule32Symbols
        jnc     short PENFA_Found

PENFA_NextMod:
        call    NextModule32
        jnc     short PENFA_ModLoop

PENFA_NotFound:
        mov     edi, ebp
        stc
PENFA_Return:
        pop     eax
        pop     ebx
        pop     ebp
        ret

PENFA_Found:
        DBGBRK  3
        mov     eax, [esp]
        call    FindExpRVA
        jne     short PENFA_NotFound

        DBGBRK  3
        mov     esi, ebx

        call    GetTheXportedName

        pop     eax
        pop     ebx
        pop     ebp
        ret

; In:   ESI = ptr name
PUBPROC P32AddressFromName
        DBGBRK  3
        mov     edi, esi                ;pointer to input string
        call    FirstModule32
        jc      short P32AFN_Return
P32AFN_ModLoop:
        ; edx = hMod32
        ; edi = ptr name
        call    FindP32ExportByName
        jnc     short P32AFN_Return
P32AFN_NextMod:
        call    NextModule32
        jnc     short P32AFN_ModLoop
P32AFN_Return:
        xchg    esi, edi
        ret

; In:   EDX = hMod32
;       EDI points to the name
PUBPROC FindP32ExportByName
        DBGBRK  4
        push    ebp
        push    edi                     ;points to input name
        push    ecx                     ;esp+4=ptr to export section
        push    ecx                     ;esp+0=no of names in export list
        call    CheckPEModuleVisible
        jc      short P32XFN_NotFound

        call    Mod32BasePtrs
        jc      short P32XFN_NotFound
        ; ESI = PE-Header
        ; EBX = Base address
        call    Find_PE_ExportSection
        jc      short P32XFN_FindSym
        ; eax = ptr PE_EXPORT_DIR_STRUC
        mov     [esp+4], eax
        call    AddressOfP32ExportedNames
        jnc     short P32XFN_ChkExports
        ; Cannot locate it in memory, try getting it from symbolic info
P32XFN_FindSym:
        ; EDX = hMod32
        call    LocateModule32Symbols
        jnc     short P32XFN_SearchSym

P32XFN_NotFound:
        add     esp, 8
        pop     edi
        pop     ebp
        stc
        ret

P32XFN_SearchSym:
        ; EBX = ptr symbolic info
        mov     esi, [ebx].pex_AddrOfNames
        mov     eax, [ebx].pex_NumberOfNames
        mov     [esp+4], ebx
P32XFN_ChkExports:
        ; eax = Number of names
        ; esi = Address of names (relative to ebx)
        mov     [esp+0], eax            ;number of names
        lea     ebp, [ebx+esi]

        mov     esi, [esp+8]            ;input string
        call    GetSymbolLen
        ; ECX = length of the name

P32XFN_NextName:
        dec     dword ptr [esp+0]       ;number of names
        js      P32XFN_NotFound
        ; [esp+0]: PARAM1 = index to the name table
        mov     eax, [esp+0]
        call    CompareP32ExportedName
        jc      P32XFN_NextName

        ; Found a name,
        xchg    esi, [esp+4]            ;esi = ptr export section/sym-info
        mov     eax, [esp+0]            ;index to name table
        ; ESI = ptr export section
        ; EBX = base for export section
        ; EAX = index to the name table
        ; EDX = hMod32
        call    GetP32IndexedAddress
        jc      P32XFN_NotFound
        pop     esi                     ;index to the name table
        pop     edi                     ;points to the end of symbol
        pop     esi
        pop     ebp
        ret

PUBPROC SPWIN_Kernel32_Initialized
        DBGBRK  3
        pushad

; **HACK**

        mov     esi, Kernel32_DataSelector[4] ; kernel32 seg#4.DD_base
        mov     ecx, 2000h/4            ; on the 1st 2000h bytes
FindMod32PtrLoop:
        push    esi
        call    GetSysSpaceIndirect
        jc      short FindMod32PtrNext
        test    eax, eax
        jns     short FindMod32PtrNext
        xchg    ebx, eax
        lea     esi, [ebx].td3_PE_Header
        call    GetSysSpaceIndirect
        jc      short FindMod32PtrNext
        cmp     eax, 00004550h          ; 'PE'?
        jne     short FindMod32PtrNext
        DBGBRK  3
        lea     esi, [ebx].td3_ModuleName ; ptr 'KERNEL32.DLL'
        call    GetSysSpaceIndirect
        jc      short FindMod32PtrNext
        cmp     eax, 'NREK'
        jne     short FindMod32PtrNext
        cmp     edx, '23LE'
        jne     short FindMod32PtrNext
        DBGBRK  3
        pop     Module32_List_Ptr       ; 0BFFBC1E0h
        call    InstallModule32Hook
        jmp     short FindMod32PtrDone
FindMod32PtrNext:
        pop     esi
        add     esi, 4
        loop    FindMod32PtrLoop
FindMod32PtrDone:
        popad
        jmp     Log_Event_Vxd

Kernel32TaskStarter:                 ; **HACK**
 db 3Dh,00h,00h,00h,80h              ;     cmp     eax, 80000000h
 db 73h,15h                          ;     jnc     short @f
 db 66h,64h,0Fh,0BAh,35h,1Ch,0,0,0,1 ;     btr     word ptr fs:[1ch],1
 db 73h,09h                          ;     jnc     short @f
 db 9Ch                              ;     pushfd
 db 81h,0Ch,24h,0,1,0,0              ;     or      [esp],100h
 db 9Dh                              ;     popfd
 db 0FFh,0E0h                        ; @@: jmp     eax
Kernel32TaskStarterSize equ ($-Kernel32TaskStarter)

Krnl32_Not_Initialized:
        reportError 'Cannot Locate KERNEL32'

PUBPROC Cmd_Process
        DBGBRK  3
        mov     ecx, Module32_List      ; 0 if kernel32 not initialized
        jecxz   Krnl32_Not_Initialized
        jnc     short @f

        VxDCall VWIN32_GetCurrentProcessHandle
        ; eax = ptr WIN32_PROCESS_DATABASE
        xchg    eax, ebx
@@:     push    ebx                     ;sl_context
        xor     ecx, ecx
        mov     esi, ebx                ;process handle
        push    ebx
        call    Walk_ProcessThreads
        pop     ebx
        neg     ecx
        push    ecx                     ;sl_limit
        push    0                       ;sl_index

        sub     esp, 4*9
        mov     edi, esp
        call    GetProcessInfo
        push    ebx                     ; Process Handle
        call    scrollLines
        db      ' Process Handle: ',d_h32,'  Flags: ',d_h32
        db      '  Module Name: ',d_fname
        db      d_lf,' Memory Context: ',d_h32,'   Heap: ',d_h32
        db      '  Priority: ',d_deci
        db      d_lf,' Parent Process: ',d_h32,'  EnvDB: ',d_h32
        db      '  TaskDB16: ',d_h16,'  PSP: ',d_h16
        db      d_lf,' Ring0TCB',d_spc,3,'ID',d_spc,4,'Flags',d_spc,4
        db      'Ring3TCB  TIB',d_spc,3,'Pri',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        inc     ecx
        ; esi = process handle
        call    Walk_ProcessThreads
        ; edi=Thread handle
        push    ecx                     ; Priority
        push    ebx                     ; TIB
        push    esi                     ; Ring3TCB
        push    eax                     ; Flags
        push    edx                     ; ID
        push    edi                     ; Ring0TCB
        call    Printf
        db      ' ',d_h32,'  ',d_h16,'  ',d_h32,'  ',d_h32,'  ',d_h16
        db      '  ',d_deci,d_ret
        ret

PUBPROC Cmd_Thread
        DBGBRK  3
        xor     ecx, ecx
        call    Walk_Threads
        neg     ecx
        push    ecx                     ;sl_limit
        push    0                       ;sl_index
        VMMcall Get_Cur_Thread_Handle
        push    edi
        call    scrollLines
        db      ' Current Thread=',d_h32
        db      d_lf,' Ring0TCB',d_spc,3,'ID',d_spc,4,'Flags',d_spc,4
        db      'Ring3TCB  TIB',d_spc,3,'Process',d_spc,3
        db      'Context',d_spc,3,'Owner',d_spc,5,'Pri',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        inc     ecx
        call    Walk_Threads
        ; edi=Thread handle
        mov     ebx, edi
        push    ecx
        push    OFFSET32 Zeros          ; as name
        push    ecx
        push    ecx
        push    ecx
        push    ecx
        push    ecx
        push    ecx
        mov     edi, esp
        push    ebx
        call    GetThreadInfo
        call    Printf
        db      ' ',d_h32,'  ',d_h16,'  ',d_h32,'  ',d_h32,'  ',d_h16
        db      '  ',d_h32,'  ',d_h32,'  ',d_fname,d_col,73,d_deci,d_ret
        ret

Walk_Threads:
        VMMcall Get_Cur_VM_Handle
        ; ebx = Cur_VM_Handle
        VMMcall Get_Initial_Thread_Handle
        mov     edx, edi
walk_th1:
        VMMcall Validate_Thread_Handle
        jc      short walk_th3
        loop    short walk_th2
        ret
walk_th2:
        VMMcall Get_Next_Thread_Handle
        cmp     edi, edx
        jne     short walk_th1
walk_th3:
        ret

display_context:
        DBGBRK  3
        call    GetContextInfo
        jc      short walk_th3
        push    edi                     ;sl_context=[eax].ac_PageTablePtr
        push    esi                     ;sl_limit=[eax].ac_NumTables
        push    0                       ;sl_index

        push    ebx                     ; Max address
        push    ecx                     ; Min address
        push    edx                     ; Mutex
        push    edi                     ; [eax].ac_PageTablePtr
        push    eax
        call    scrollLines
        db      ' Handle=',d_h32,'  PageTable=',d_h32,'  Mutex=',d_h32,d_lf
        db      ' Address Range=',d_h32,'-',d_h32,d_lf
        db      '  Linear Address  PageTable  Attributes'
        db      d_sub
        ; will be called by scrollLines
        ; esi = context = ac_PageTablePtr
        ; edx = ecx = index
        jmp     Display_PDE

PUBPROC Cmd_AddrCntx
        DBGBRK  3
        xor     ecx, ecx
        call    Walk_AddrCntx
        cmp     eax, ebx
        je      display_context
        neg     ecx
        push    ecx                     ;sl_limit
        push    0                       ;sl_index
        call    scrollLines
        db      '  Handle   PageTable  #Pages     Address Range    Mutex',d_sub
                ; --------  --------  --------  --------=--------  --------
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        inc     ecx
        call    Walk_AddrCntx
        ; eax=Address context handle
        call    GetContextInfo
        jc      short gc_failed
        push    edx                     ; Mutex
        push    ebx                     ; Max address
        push    ecx                     ; Min address
        push    esi                     ; [eax].ac_NumTables
        push    edi                     ; [eax].ac_PageTablePtr
        push    eax
        call    Printf
        db      ' ',d_h32,'  ',d_h32,'  ',d_h32
        db      '  ',d_h32,'-',d_h32,'  ',d_h32,d_ret
        DBGBRK  3
        VMMcall _GetMutexOwner, <edx>
        test    eax, eax
        jz      short gc_failed
        push    eax
        call    PrintfAt
        db      '  ',d_fname,d_ret
gc_failed:
        ret

Mod32_NotAvail:
        reportError 'No 32-bit Module Found.'

PUBPROC Cmd_Mod32
        DBGBRK  3
        call    GetSymbolLen
        jecxz   short Display_AllMod32s
        call    GetP32ModuleFromName
        jnc     Display_Mod32Info

        reportError 'Module Not Found.'

Display_AllMod32s:
;       xor     ecx, ecx
        call    Walk_Module32s
        jecxz   Mod32_NotAvail
        neg     ecx                     ;total number of modules
        push    ecx                     ;sl_total
        push    0                       ;sl_index
        call    scrollLines
        ;         --------  00000000  00000000  0000  0000  xxxxxxxx
        db      ' Module    Base      PE-Header Mod16 Usage FileName',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        inc     ecx
        call    Walk_Module32s
        ; edi = ptr WIN32_TDB_STRUC
        ; esi = PE-Header

        mov     ebx, [edi].td3_FilePath         ;
        push    dword ptr [edi].td3_Usage       ; word
        push    dword ptr [edi].td3_Mod16DB     ; word
        push    esi                             ; td3_PE_Header
        push    dword ptr [esi].pe_ImageBase    ; base of code
        push    dword ptr [edi].td3_ModuleName  ; KERNEL32.DLL
        call    Printf
        db      ' ',d_fname,d_col,11,d_h32,'  ',d_h32,'  ',d_h16,'  '
        db      d_h16,'  ',d_text,37,d_ret
        ret

Display_Mod32Info:
        call    Mod32BasePtrs
        ; esi = PE-Header
        ; ebx = Base address
        ; edx = hMod32
        mov     edi, [edx]              ;td3
        movzx   eax, [esi].pe_NumberOfSections

        push    esi                     ;sl_context
        push    eax                     ;sl_total (pe_NumberOfSections)
        push    0                       ;sl_index

        mov     ecx, [esi].pe_AddrOfEntryPoint
        add     ecx, ebx
        push    ecx
        push    dword ptr [esi].pe_BaseOfData
        push    dword ptr [esi].pe_BaseOfCode

        push    eax                     ;pe_NumberOfSections
        push    esi                     ;td3_PE_Header
        push    ebx                     ;pe_ImageBase
        movzx   eax, [edi].td3_Usage
        push    eax
        push    dword ptr [edi].td3_Mod16DB     ; word
        push    dword ptr [edi].td3_ModuleName  ; KERNEL32.DLL
        mov     ebx, [edi].td3_FilePath         ;
        call    scrollLines
        db              '    File Name: ',d_text,67
        db      d_lf,'  Module Name: ',d_fname
        db      d_col,27,'Mod16DB: ',d_h16,d_col,46,'Usage: ',d_deci
        db      d_lf,' Base Address: ',d_h32,'  PE-Header: ',d_h32
        db      '  Sections: ',d_deci
        db      d_lf,'    Code Base: ',d_h32,'  Data Base: ',d_h32
        db      '  Entry Point: ',d_h32
        db      d_lf,' Section   Address    Size    FilePos    Size    Flags',d_sub
        ;              --------  -------- --------  -------- --------  --------
        ; will be called by scrollLines
        ; esi = context (ptr PE-Header)
        ; edx = ecx = index
        DBGBRK  3
        movzx   eax, [esi].pe_SizeOfOptionalHdr
        lea     edi, [esi+eax].pe_OptHdrMagic
        imul    edx, SIZE PE_SECTION_HEADER_STRUC
        add     edi, edx

        push    dword ptr [edi].pes_Characteristics ; _bits
        push    0                       ;a_b mask for _bits

        push    dword ptr [edi].pes_Characteristics
        push    dword ptr [edi].pes_PhysSize
        push    dword ptr [edi].pes_PhysAddress
        push    dword ptr [edi].pes_VirtualSize
        mov     eax, [edi].pes_SectionRVA
        add     eax, [esi].pe_ImageBase
        push    eax
        lea     ebx, [edi].pes_Name
        call    Printf
        db      ' ',d_text,8,d_col,11,d_h32,' ',d_h32,'  ',d_h32,' ',d_h32
        db      '  ',d_h32,'  '
        _bits   0e00000e0h,1,' W R X U D C'
        db      d_ret
        ret
ENDIF ; _W95_

LCODE_ENDS
END

