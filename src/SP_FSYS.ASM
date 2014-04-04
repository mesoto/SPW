title.  SoftProbe - File system support.

SP_FSYS EQU 1
INCLUDE SP_DEFS.INC 
INCLUDE SP_KRNL.INC 
IFDEF   _W95_
INCLUDE IFSMGR.INC
;;INCLUDE IFS.INC
ENDIF

; ---------------------------------------------------------------------------
LDATA_SEG
; ---------------------------------------------------------------------------

IFDEF   _W95_
Prev_FileSystemHook     dd ?
ENDIF

LDATA_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------

; ***************************************************************************
;
;
; ===========================================================================
IFDEF   _W95_
; Parameters passed thru stack
fsh_StkStruc    struc
  fsh_RetAddr   dd ?    ; Return address
  fsh_pIFSFunc  dd ?    ;
  fsh_Function  dd ?    ; Function code
  fsh_Drive     dd ?    ; 0=A, 1=B,...
  fsh_ResType   dd ?    ;
  fsh_CodePage  dd ?    ;
  fsh_pIOReq    dd ?    ;
fsh_StkStruc    ends

; int _cdecl FSHookProc(pIFSFunc, Function, Drive, ResType, CodePage, pIOReq)

FileSystemApiHook:
        DBGBRK  0
        mov     eax, esp
        ; Save some fields of incomming IO Request, they can be modified.
        xchg    esi, [esp].fsh_pIOReq
;       push    [esi].ir_options
;       push    [esi].ir_pos
;       push    [esi].ir_length
;       push    [esi].ir_locklen
;       push    [esi].ir_flags
;       push    [esi].ir_attr
;       push    [esi].ir_data

        push    esi
        push    [eax].fsh_CodePage
        push    [eax].fsh_ResType
        push    [eax].fsh_Drive
        push    [eax].fsh_Function
        push    [eax].fsh_pIFSFunc
        mov     eax, Prev_FileSystemHook
        call    dword ptr [eax]
        add     esp, 6*4
        ; Save the return value
        xchg    esi, [esp].fsh_pIOReq
        ret
ENDIF

PUBPROC FileSys_Device_Init
        DBGBRK  0
IFDEF   _W95_
        ; Win95 only debug services
        VxDCall IFSMgr_InstallFileSystemApiHook, FileSystemApiHook
        mov     Prev_FileSystemHook, eax
ENDIF
        ret

LCODE_ENDS

; ---------------------------------------------------------------------------
ICODE_SEG
; ---------------------------------------------------------------------------

ICODE_ENDS
END

