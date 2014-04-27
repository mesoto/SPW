title.  SoftProbe - SP_Symb

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

SP_SYMB EQU 1
include SP_DEFS.inc
INCLUDE SP_KRNL.INC 
INCLUDE SPAPI.INC

; ---------------------------------------------------------------------------
LDATA_SEG
; ---------------------------------------------------------------------------

PUBDWRD VxD_Info_Ptr 0
PUBDWRD VxD_SymbolInfo here
IFDEF   _W95_
        include VXDSYMB.W95
ELSE
        include VXDSYMB.W31
ENDIF
PUBDWRD SymbolInfoNext 0 ;ends the module list

tmp_buffer      db 42 dup(0)

LDATA_ENDS

; ---------------------------------------------------------------------------
SCODE_SEG       ; Safe code area (No Pushes inside calls)
; ---------------------------------------------------------------------------
; In:   PARAM1 = Segment to find
;       EAX = Module DB
; Out:  CF=0    Success
;               edx=segment number
;               edi=lstring module name
;               esi=ptr segment table
PUBPROC FindP16Segment
        movzx   ecx, [eax].ne_cseg      ;number of segments
        jecxz   short P16SegFail        ;if no segment
        movzx   edi, [eax].ne_restab    ;module name offset
        add     edi, eax                ;lstring
        movzx   esi, [eax].ne_segtab
        add     esi, eax
        xor     edx, edx
@@:     inc     edx                     ;segment number
        movzx   eax, [esi].sg_handle
        xor     eax, [esp+PARAM1]
        and     ax, not 3
        je      short P16SegDone
        add     esi, size SEGMENT_TABLE_STRUC
        loop    @b
P16SegFail:
M16RN_Fail:
        stc
P16SegDone:
        ret

; ---------------------------------------------------------------------------
Mod16ResidentName:
        cmp     [eax].ne_signature, 454Eh ; 'NE'
        jne     short M16RN_Fail
        ; Obtain the resident names table offset from the NE header.
        movzx   edi, [eax].ne_restab    ; resident names offset
        add     edi, eax
        ; first entry is always the module name (lstring)
        cmp     cl, [edi]               ; same length?
        clc                             ; success
        ret

; ---------------------------------------------------------------------------
; In:   EBX = linear address
;       ECX = selector base
;       ES:EDI  = buffer for name
; Out:  CF=0  Prints section name + offset
;       CF=1  Not found
IFDEF   _W95_
P32SectionFromAddress:
        cmp     ebx, 00400000h
        jb      short VNFA_NotFound
        cmp     ebx, 0c0000000h
        jb      GetPESectionFromAddress
ENDIF

; In:   EBX = linear address
;       ES:EDI  = buffer for name
; Out:
PUBPROC GetVxdSectionFromAddress
        DBGBRK  2
        mov     esi, VxD_Info_Ptr       ; ptr loaded VxD's (int 68h)
        mov     ecx, [esi-4]            ; end of info
VNFA_Loop:
        cmp     ebx, [esi].vi_Start
        jb      short VNFA_Next
        cmp     ebx, [esi].vi_End
        jb      short VNFA_Found
VNFA_Next:
        add     esi, SIZE VXD_INFO_STRU
        cmp     ecx, esi
        ja      short VNFA_Loop
VNFA_NotFound:
        ; cf=1
        ret

VNFA_Found:
        mov     eax, ebx
        sub     eax, [esi].vi_Start
        movzx   ecx, [esi].vi_SegNumber
        lea     esi, [esi].vi_Name
        push    eax
        push    ecx
        push    esi
        call    PrintfAt
        db      d_fname,'(',d_deci,')+',d_h32,d_ret
        ; cf=0
        ret

; ---------------------------------------------------------------------------
; In:   EDX:EBX = address
;       ES:EDI  = buffer for name
PUBPROC SectionNameFromAddress
        DBGBRK  3
        xchg    eax, edx
        mov     ecx, eax                ; save selector
        call    Get_Selector
        jc      short SNFA_Done
        xchg    ecx, eax
        ; ecx=base address
IFDEF   _W95_
        jecxz   P32SectionFromAddress   ; if base address = 0
ELSE
        jecxz   GetVxdSectionFromAddress ; if base address = 0
;;      ; Base selectors of WIN32S
;;      cmp     ecx, 0ffff0000h
;;      je      P32SectionFromAddress   ; if base address = 0
ENDIF

; In:   AX:EBX = address
;       ECX    = base address
;       ES:EDI = buffer for name
P16SectionFromAddress:
        push    ecx                     ; save base address
        push    eax
        call    ModuleNameFromSelector
        pop     edx
        pop     ebx
        jc      short SNFA_Done

        push    esi
        cmp     al, 'T'                 ; 'TD'?
        je      short P16SFA_TDB_Types
        ; ds:ecx = module header
        cmp     ebx, ecx                ; same base?
        jz      short P16SFA_ModuleDB

        xchg    eax, ecx
        movzx   ecx, [eax].ne_cseg      ;number of segments
        jecxz   short SNFA_Simple       ;if no segment
        movzx   esi, [eax].ne_segtab
        add     esi, eax
        xor     ebx, ebx
@@:     inc     ebx                     ;segment number
        movzx   eax, [esi].sg_handle
        xor     eax, edx
        and     eax, not 3
        jz      short SNFA_FoundSeg
        add     esi, size SEGMENT_TABLE_STRUC
        loop    @b
SNFA_Simple:
        call    PrintfAt
        db      d_fname,d_ret
SNFA_Done:
        ret

SNFA_FoundSeg:
        call    PrintfAt
        db      d_fname,d_ret
        push    ebx
        call    PrintfAt
        db      '(',d_deci,')',d_ret
        ret

P16SFA_ModuleDB:
        call    PrintfAt
        db      d_fname,'.MDB',d_ret
        ret

P16SFA_TDB_Types:
        sub     ecx, ebx                ; same base?
        jz      short P16SFA_TDB
        add     ecx, 100h
        jnz     SNFA_Simple
        call    PrintfAt
        db      d_fname,'.PDB',d_ret
        ret

P16SFA_TDB:
        call    PrintfAt
        db      d_fname,'.TDB',d_ret
        ret

; ---------------------------------------------------------------------------
; In:   EDI   =linear address of SS:ESP
;       PARAM1=target CS
; Out:  CF=1 Failed
;       CF=0 Success
;            eax:ecx CALL edx:esi
;            ebx=linear address of eax:ecx, edi=updated SS:ESP
SC32_WCall:
        mov     ecx, [edi]              ; offset
        sub     ecx, 6
        jc      short SC32_failed
        mov     eax, [esp+PARAM1]       ; hi-word = CS type
        mov     ebx, ecx                ; offset
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      short SC32_failed
        cmp     word ptr [ebx], 15ffh   ; call dword [xxxxxxxx]?
        jne     short SC32_failed

        mov     eax, [esp+PARAM1]       ; hi-word = CS type
        ; eax:ecx = CS:EIP
        mov     edx, eax                ; same selectors
        mov     esi, [ebx+2]            ; xxxxxxxx
        mov     esi, [esi]              ; [xxxxxxxx]
        ; eax:ecx CALL edx:esi
        jmp     short StkChk_Pop8

SC32_NCall:
        ; Check for E8xxxxxxxx CALL XXXXXXXX
        mov     ecx, [edi]              ; offset
        sub     ecx, 5
        jc      short SC32_failed
        mov     eax, [esp+PARAM1]       ; hi-word = CS type
        mov     ebx, ecx                ; offset
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      short SC32_failed
        cmp     byte ptr [ebx], 0e8h    ; call xxxx?
        jne     short SC32_failed
        mov     eax, [esp+PARAM1]       ; hi-word = CS type
        ; eax:ecx = CS:EIP
        mov     edx, eax                ; same selectors
        mov     esi, [ebx+1]            ; relative offset
        lea     esi, [esi+ecx+5]        ; the actual offset
        ; eax:ecx CALL edx:esi
        jmp     short StkChk_Pop4

SC32_PushCsCall:
        ; We already know the near call
        ; Check the 'PUSH CS' and the pushed segment
        cmp     byte ptr [ebx-1], 0eh   ; PUSH CS?
        jne     short SC32_failed
        cmp     ax, word ptr [edi]      ; same segments?
        jne     short SC32_failed
        jecxz   short SC32_failed
        dec     ecx                     ; offset-1
        jmp     short StkChk_Pop4

SC32_failed:
        stc
        ret

; ---------------------------------------------------------------------------
; In:   EDI   =linear address of SS:ESP
;       PARAM1=target CS
; Out:
SC32_FCall:
        mov     ecx, [edi]              ; offset
        sub     ecx, 7
        jc      short SC32_failed
        movzx   eax, word ptr [edi+4]   ; CS selector
        mov     ebx, ecx                ; offset
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      short SC32_failed
        cmp     byte ptr [ebx], 9ah     ; call xxxx:xxxxxxxx?
        jne     short SC32_failed

        movzx   eax, word ptr [edi+4]   ; CS selector
        ; eax:ecx = CS:EIP
        movzx   edx, word ptr [ebx+5]   ; target CS
        mov     esi, [ebx+1]            ; target EIP
        ; eax:ecx CALL edx:esi
StkChk_Pop8:
        add     edi, 4
StkChk_Pop4:
        inc     edi
        inc     edi
StkChk_Pop2:
        cmp     edi, 0c004d000h         ; will be set by
StkWlk_EspLimit equ $-4
        jae     short SC32_failed
        inc     edi
        inc     edi
        test    al, [edi]               ; CF if not present
        ret

; ---------------------------------------------------------------------------
; In:   EDI   =linear address of SS:ESP
;       PARAM1=target CS
; Out:  CF=1 Failed
;       CF=0 Success
;            eax:ecx CALL edx:esi
;            ebx=linear address of eax:ecx, edi=updated SS:ESP
SC16_NCall:
        ; Check for E8xxxx CALL XXXX
        movzx   ecx, word ptr [edi]     ; offset
        sub     ecx, 3
        jc      short SC16_failed
        mov     eax, [esp+PARAM1]       ; hi-word = CS type
        mov     ebx, ecx                ; offset
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      short SC16_failed
        cmp     byte ptr [ebx], 0e8h    ; call xxxx?
        jne     short SC16_failed
        mov     eax, [esp+PARAM1]       ; hi-word = CS type
        ; eax:ecx = CS:EIP
        mov     edx, eax                ; same selectors
        movsx   esi, word ptr [ebx+1]   ; relative offset
        lea     esi, [esi+ecx+3]        ; the actual offset
        movzx   esi, si
        ; eax:ecx CALL edx:esi
        jmp     short StkChk_Pop2

SC16_PushCsCall:
        ; We already know the near call
        ; Check the 'PUSH CS' and the pushed segment
        cmp     byte ptr [ebx-1], 0eh   ; PUSH CS?
        jne     short SC16_failed
        cmp     ax, word ptr [edi]      ; same segments?
        jne     short SC16_failed
        jecxz   short SC16_failed
        dec     ecx                     ; offset-1
        jmp     short StkChk_Pop2

SC16_failed:
        stc
        ret

; ---------------------------------------------------------------------------
; In:   EDI   =linear address of SS:ESP
;       PARAM1=target CS
; Out:
SC16_FCall:
        movzx   ecx, word ptr [edi]     ; offset
        sub     ecx, 5
        jc      short SC16_failed
        mov     eax, [esp+PARAM1]       ; hi-word = CS type
        mov     ax, [edi+2]             ; keep hi-word unchanged
        mov     ebx, ecx                ; offset
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      short SC16_failed
        cmp     byte ptr [ebx], 9ah     ; call xxxx:xxxx?
        jne     short SC16_failed

        mov     eax, [esp+PARAM1]       ; hi-word = CS type
        mov     ax, [edi+2]             ; keep hi-word unchanged
        mov     edx, eax                ; hi-word = CS type
        mov     dx, word ptr [ebx+3]    ; target segment
        movzx   esi, word ptr [ebx+1]   ; offset
        ; eax:ecx CALL edx:esi
        jmp     StkChk_Pop4             ; remove 4 bytes not 2

; ---------------------------------------------------------------------------
PUBPROC SpecialGetP32Names
        ; Microsoft imports are like this
        cmp     byte ptr [ebx], 2eh     ; CS: prefix?
        jne     short @f
        inc     ebx
@@:     cmp     word ptr [ebx], 25ffh   ; FF25xxxxxxxx JMP [xxxxxxxx]
        jne     short SC16_failed
        mov     eax, [ebx+2]            ; xxxxxxxx
        mov     eax, [eax]              ; [xxxxxxxx]
        ; eax=offset
        jmp     GetP32NameFromAddress

SCODE_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------

PUBPROC VxdNameFromId
; In:   AX = VxdID
;       ES:EDI = buffer for name
; Out:  ESI = ptr name
;       CF  = 1 if no name found
        DBGBRK  5
        mov     esi, OFFSET32 VxD_SymbolInfo
findModule:
        cmp     ax, [esi].mod_Id
        je      short foundName
        mov     esi, [esi].mod_Next
        test    esi, esi
        jnz     short findModule
notFound:
        call    hex_16
        stc
        ret

foundName:
        lea     esi, [esi].mod_Name[1]  ; LString
        movzx   ecx, byte ptr [esi-1]   ; length
        rep     movsb                   ; report name
;       clc
        ret

; ---------------------------------------------------------------------------
VxdCallStr      db 'VxDcall ',0
VxdJumpStr      db 'VxDjump ',0
VMMCallStr      db 'VMMcall ',0
VMMJumpStr      db 'VMMjump ',0

PUBPROC GetVxdService
; In:   EAX = VxdID
;       EDX = Service No.
;       ES:EDI = buffer for name
; Out:  ESI = ptr name
;       ZF  = 1 if no name found

        DBGBRK  5
        mov     esi, OFFSET32 VxdCallStr
        btr     edx, 15
        jnc     short @f
        add     esi, (VxdJumpStr - VxdCallStr)
@@:     cmp     ax, 1                   ; VMM?
        je      short disp_VMM_Services
        movsd
        movsd
        push    edi
        call    VxdNameFromId
        pop     ecx
        mov     al, '.'
        stosb
        jnc     short disp_Service
BadService:
        xchg    eax, edx
        jmp     hex_16

disp_VMM_Services:
        add     esi, (VMMCallStr - VxdCallStr)
        movsd
        movsd
        mov     esi, OFFSET32 VMM_Srv_Beg-2
        mov     ecx, edi
disp_Service:
        lodsw                           ; Max service
        cmp     dx, ax
        jae     short BadService
        mov     edi, ecx                ; remove VxD!
disp_SrvcName:
        movzx   eax, word ptr [esi+2*edx][0]
        movzx   ecx, word ptr [esi+2*edx][2]
        sub     ecx, eax
        add     esi, eax
        rep     movsb                   ; report name
        ret

; ---------------------------------------------------------------------------
PUBPROC GetVxdServiceName
; In:   EAX = VxdID
;       EDX = Service No.
;       EDI = buffer for name
        push    edi
        call    VxdNameFromId           ;find it in our symbolic list
        pop     edi
        jc      short @f
        lodsw                           ; Max service
        and     edx, 7fffh              ;VxDcall/VxDjump
        cmp     dx, ax
        jb      short disp_SrvcName
        stc
@@:     ret

; ---------------------------------------------------------------------------
; In:   EDX:EAX = address
;       EDI = ptr buffer for name
; Out:  CF=0  found the name
;       CF=1  not found
; EBX should be preserved
PUBPROC GetP16NameFromAddress
        DBGBRK  2
        push    edi
        push    eax
        push    edx                     ; PARAM1( FindP16Segment )
        test    def_segsize, DEFSEG_V86
        jnz     short P16Name_NotFound  ;if V86
        mov     eax, edx
        call    ModuleNameFromSelector
        jc      short P16Name_NotFound  ;if not available
        cmp     al, 'N'
        jne     short P16Name_NotFound  ;if TDB
        xchg    eax, ecx
        ; PARAM1 = Segment to find
        call    FindP16Segment
        jnc     short P16Name_Found
P16Name_NotFound:
        pop     edx
        pop     eax
        pop     edi
        stc
        ret

P16Name_Found:
        DBGBRK  3
        ; edx = selector#
        mov     [esp+6], dx             ;[esp+4]= seg#:offset (saved eax)
        ; edi = ptr lstring module name
        mov     edx, SymBuffer_Beg
        jmp     short P16NFA_Find2

P16NFA_Find1:
        add     edx, [edx].sh16_Size
P16NFA_Find2:
        cmp     edx, SymBuffer_End
        jae     short P16Name_NotFound
        cmp     [edx].sh16_Size, 0
        je      short P16Name_NotFound
        cmp     [edx].sh16_Type, SYM_P16
        jne     short P16NFA_Find1
        lea     esi, [edx].sh16_ModName ;points to lstring module name
        call    lstrncmp
        jc      short P16NFA_Find1

        DBGBRK  3
        mov     edi, [esp+8]            ;saved edi
        inc     esi
        dec     ecx
        rep     movsb                   ;module name

        mov     eax, [esp+4]
        DBGBRK  3
        add     edx, [edx].sh16_Size
P16NFA_Find3:
        lea     esi, [esi+ecx].p16si_Name[1]
        cmp     esi, edx
        jae     short P16Name_NotFound
        mov     cl, byte ptr [esi-1]
        cmp     dword ptr [esi-p16si_Name-1].p16si_Offset, eax
        jb      short P16NFA_Find3
        jne     short P16Name_NotFound
        DBGBRK  3
        mov     al, '.'
        stosb
        rep     movsb
        pop     edx
        pop     eax
        movzx   eax, ax
        pop     esi                     ;saved edi
        clc
        ret

; ---------------------------------------------------------------------------
; In:   EAX = offset
;       EDX = selector
;       EDI = ptr buffer for name
; Out:  CF=0  found the name
;       CF=1  not found
PUBPROC GetSymNameForAddress
        test    def_segsize, DEFSEG_ZBASE ; base=0?
        jnz     short GetP32NameFromAddress
PUBPROC V86P16NameFromAddress
        bt      edx, 31
        jnc     GetP16NameFromAddress
        ret

; ---------------------------------------------------------------------------
; In:   EAX = offset
;       EDI = ptr buffer for name
; Out:  CF=0  found the name
;       CF=1  not found
PUBPROC GetP32NameFromAddress
        DBGBRK  3

IFDEF   _W95_
        cmp     eax, 000400000h
        jb      short VSFA_NotFound
        cmp     eax, 0c0000000h
        jb      GetPENameFromAddress
ELSE
        test    eax, eax
        jns     short VSFA_NotFound
ENDIF

; ---------------------------------------------------------------------------
PUBPROC VxdServiceFromAddress

        mov     edx, VMM_DDB_BASE
VSFA_Loop1:
        cmp     eax, [edx].DDB_Control_Proc
        je      short VSFA_CtrlProc
        cmp     eax, [edx].DDB_V86_API_Proc
        je      short VSFA_V86API
        cmp     eax, [edx].DDB_PM_API_Proc
        je      short VSFA_PMAPI
        mov     ecx, [edx].DDB_Service_Table_Size
IFDEF   _W95_
        jecxz   short VSFA_TryW32svcs
ELSE
        jecxz   short VSFA_Next
ENDIF
        mov     esi, edi
        mov     edi, [edx].DDB_Service_Table_Ptr
        repne   scasd
        xchg    esi, edi
        je      short VSFA_Found
IFDEF   _W95_
VSFA_TryW32svcs:
        test    [edx].DDB_Flags, DDB_HAS_WIN32_SVCS
        jz      short VSFA_Next
        mov     ecx, [edx].DDB_Win32_Service_Table
        jecxz   short VSFA_Next
        mov     esi, ecx
        movzx   ecx, word ptr [esi]     ; assume less than 64K
        jecxz   short VSFA_Next
VSFA_W32svcs:
        add     esi, 8
        cmp     eax, [esi]
        loopne  VSFA_W32svcs
        je      short VSFA_W32svcFound
ENDIF
VSFA_Next:
        mov     edx, [edx].DDB_Next
        test    edx, edx
        jnz     short VSFA_Loop1
VSFA_NotFound:
        stc
        ret

IFDEF   _W95_
VSFA_W32svcFound:
        DBGBRK  4
        mov     eax, [edx].DDB_Win32_Service_Table
        mov     eax, [eax]
        dec     eax
        sub     eax, ecx                ; service number
        push    eax
        call    Copy_VxdNameAndLString
        LString '.W32.'
        pop     eax
        jmp     hex_16
ENDIF

VSFA_CtrlProc:
        call    Copy_VxdNameAndLString
        LString '.CP'
        ret

VSFA_V86API:
        call    Copy_VxdNameAndLString
        LString '.V86'
        ret

VSFA_PMAPI:
        call    Copy_VxdNameAndLString
        LString '.PM'
        ret

VSFA_Found:
        DBGBRK  3
        mov     eax, [edx].DDB_Service_Table_Size
        sub     eax, ecx
        movzx   ecx, [edx].DDB_Req_Device_Number
        ; eax = service number+1
        ; ecx = vxd id

        mov     esi, OFFSET32 VxD_SymbolInfo
VSFA_FindVxd:
        cmp     cx, [esi].mod_Id
        je      short VSFA_FoundVxd
        mov     esi, [esi].mod_Next
        test    esi, esi
        jnz     short VSFA_FindVxd

VSFA_SrvNotFound:
        dec     eax
        push    eax
        lea     esi, [edx].DDB_Name
        call    Display_ModName
        mov     al, '.'
        stosb
        pop     eax
        jmp     hex_16                  ;VxD.nnnn

VSFA_FoundVxd:
        DBGBRK  2
        movzx   ecx, byte ptr [esi].mod_Name[0] ; LString
        lea     esi, [esi].mod_Name[ecx+1] ; LString
        cmp     [esi], ax               ; Max service
        jb      short VSFA_SrvNotFound
        movzx   ecx, word ptr [esi+2*eax][2]
        movzx   eax, word ptr [esi+2*eax][0]
        sub     ecx, eax
        lea     esi, [esi+eax+2]
        rep     movsb                   ; report name
;       clc
        ret

PUBPROC Copy_VxdNameAndLString
        lea     esi, [edx].DDB_Name
        mov     ecx, 8
@@:     lodsb
        cmp     al, ' '
        jbe     short @f
        stosb
        loop    short @b
@@:
PUBPROC Copy_LString
        pop     esi
        movzx   ecx, byte ptr [esi]
        inc     esi
        rep     movsb
        clc
        jmp     esi

; ---------------------------------------------------------------------------
PUBDWRD Symbol_Character here
        ;       fedcba9876543210   fedcba9876543210
        dw      0000000000000000b, 0000000000000000b  ; 00-1f
        dw      0000000000011000b, 1000001111111111b  ; 20-3f #$,0-9,?
        dw      1111111111111111b, 1000011111111111b  ; 40-5f @,A-Z,_
        dw      1111111111111110b, 0000011111111111b  ; 60-7f a-z
        dw      0000000000000000b, 0000000000000000b  ; 80-9f
        dw      0000000000000000b, 0000000000000000b  ; a0-bf
        dw      0000000000000000b, 0000000000000000b  ; c0-df
        dw      0000000000000000b, 0000000000000000b  ; e0-ff

PUBPROC GetSymbolLen
        xor     ecx, ecx
        xor     eax, eax
@@:     lodsb
        inc     ecx
        bt      Symbol_Character, eax
        jc      @b
        sub     esi, ecx
        dec     ecx
jret:   ret

; ---------------------------------------------------------------------------
PUBPROC VxdAddressFromName
        call    GetSymbolLen
        ; esi = ptr symbol
        ; ecx = length
VxdAddressFromNameLen:
        mov     edx, OFFSET32 VxD_SymbolInfo
VAFN_FindVxd1:
        DBGBRK  2
        push    edx
        movzx   eax, byte ptr [edx].mod_Name ; length of LString
        lea     edx, [edx+eax].mod_Name[1]   ; end of LString
        movzx   ebx, word ptr [edx]     ; maximum number of services
        inc     ebx
VAFN_FindVxd2:
        dec     ebx
        jz      short VAFN_FindNext
        movzx   eax, word ptr [edx+ebx*2]
        lea     edi, [edx+eax+2]        ; points to name
        sub     ax,  [edx+ebx*2+2]      ; ax= -length
        add     ax, cx
        jne     short VAFN_FindVxd2
        call    strncmp
        jc      short VAFN_FindVxd2

        ; VxD service found!
        add     esi, ecx
        pop     edx
        ; bx=service# + 1
        ; now translate service number to address

        push    esi
        lea     esi, [edx].mod_Name[1]  ; LString VxD name
        movzx   ecx, byte ptr [esi-1]   ; length
        call    FindVxdByName
        pop     esi
        jc      short VAFN_NotFound     ; maybe unloaded!

        mov     edi, [edx].DDB_Service_Table_Ptr
        mov     ebx, [edi+ebx*4-4]
        xor     edx, edx
        mov     dx, cs
        ret

VAFN_FindNext:
        pop     edx
        mov     edx, [edx].mod_Next
        test    edx, edx
        jnz     VAFN_FindVxd1
        ; VxD service not found
        call    FindVxdByName
        jc      short VAFN_NotFound
VAFN_CtrlProc:
        mov     ebx, [edx].DDB_Control_Proc
        xor     edx, edx
        mov     dx, cs
;       clc
        ret

; ---------------------------------------------------------------------------
; In:   ESI = Ptr symbolic name
;       ECX = length of name
; Out:  CF  = 0 Found, EBX=ptr module symbolic info, EDX=ptr NE-Header
;       CF  = 1 Not found
PUBPROC P16ModuleFromName
        DBGBRK  4
        mov     ebx, SymBuffer_Beg
P16MFN_Find1:
        cmp     ebx, SymBuffer_End
        jae     short P16MFN_NotFound
        cmp     [ebx].sh16_Size, 0      ;size of this module
        je      short P16MFN_NotFound
        cmp     cl, [ebx].sh16_ModName  ;length of the module name
        jne     short P16MFN_Find2
        lea     edi, [ebx].sh16_ModName[1]
        call    strncmp
        jnc     short P16MFN_Find3

P16MFN_Find2:
        add     ebx, [ebx].sh16_Size    ;end of module (next module)
        jmp     short P16MFN_Find1

P16MFN_Find3:
        ; ebx will be preserved
PUBPROC P16ModuleHandleFromName
        call    GetHeadExe
        jnc     short P16MHFN_Loop
VAFN_NotFound:
P16MFN_NotFound:
P16MHFN_NotFound:
        stc
        ret

P16MHFN_Next:
        movzx   eax, [edx].ne_pnextexe
P16MHFN_Loop:
        push    esi
        call    Get_Selector
        pop     esi
        jc      short P16MHFN_NotFound
        call    Mod16ResidentName
        jc      short P16MHFN_NotFound

        xchg    edx, eax
        ; first entry is always the module name (lstring)
        jne     short P16MHFN_Next      ; same length?
        inc     edi                     ; skip length
        call    strncmp
        jc      short P16MHFN_Next
        add     esi, ecx
        ; edx = ptr NE-Header
        ret

; ---------------------------------------------------------------------------
getVxdServices:
        inc     esi                     ;skip '.'
        call    Parse_LineNoSkip
        FullCmd 'CP'    GOTO_REL16 VAFN_SpcProc DDB_Control_Proc
        FullCmd 'V86'   GOTO_REL16 VAFN_SpcProc DDB_V86_API_Proc
        FullCmd 'PM'    GOTO_REL16 VAFN_SpcProc DDB_PM_API_Proc
IFDEF   _W95_
        PartCmd 'W32.'  GOTO_REL16 VAFN_W32Svrc DDB_HAS_WIN32_SVCS
ENDIF
        db      0

        DBGBRK  4
        ; Is it VxD.hhhh (hhhh=service number in hex)?
        call    Scan_Hex
        jc      VxdAddressFromName

        DBGBRK  2
        cmp     ebx, [edx].DDB_Service_Table_Size
        jae     VAFN_CtrlProc
        mov     eax, [edx].DDB_Service_Table_Ptr
        lea     edx, [ebx*4]
VAFN_SpcProc:
        mov     ebx, [edx+eax]
        mov     edx, VXD_CODESELECTOR
        clc
        ret

IFDEF   _W95_
VAFN_W32Svrc:
        DBGBRK  4
        test    dword ptr [edx].DDB_Flags, eax ; DDB_HAS_WIN32_SVCS
        jz      short VAFN_W32SvcNotFound

        ; Is it VxD.W32.hhhh (hhhh=Win32 service number in hex)?
        call    Scan_Hex
        jc      short VAFN_W32SvcNotFound
        mov     ecx, [edx].DDB_Win32_Service_Table
        jecxz   short VAFN_W32SvcNotFound
        cmp     [ecx], ebx
        jbe     short VAFN_W32SvcNotFound
        mov     ebx, [ecx+ebx*8+8]
        mov     edx, VXD_CODESELECTOR
        ret

VAFN_W32SvcNotFound:
        stc
        ret
ENDIF

; ---------------------------------------------------------------------------
GetServiceFromName:
        ; esi = ptr name.ssss   VXD.name   MOD16.expname   MOD32.expname
        ;                       VXD.svc#   MOD16.ord#      MOD32.ord#
        ;                       VXD.CP                     MOD32.MDB
        ;                       VXD.V86
        ;                       VXD.PM
        ;                       VXD.W32.svc#
        ;
        ; ecx = len(name)
;;      cmp     ecx, 9
;;      jae     short P16MFN_NotFound

        call    FindVxdByName
        jnc     getVxdServices

IFDEF   _W95_
        push    esi
        push    ecx
        call    GetP32ModuleFromName
        pop     ecx
        pop     esi
        jnc     GetP32NameFromOrd
ENDIF ; _W95_

        DBGBRK  3
        call    P16ModuleFromName
        jc      VAFN_NotFound
        ; EBX = ptr module symbolic info
        ; EDX = ptr NE-Header
        DBGBRK  3
        inc     esi                     ;skip '.'

;       call    Parse_LineNoSkip
;       FullCmd 'MDB'  JUMP_ADDRS <OFFSET32 P16ModDBSelector>
;       db      0

        DBGBRK  3
        push    ebx
        call    Scan_Hex
        pop     eax                      ; ptr module symbolic info
        xchg    ebx, eax
        jnc     short FindP16ExportByOrd ; eax = ordinal number

        call    GetSymbolLen

; ---------------------------------------------------------------------------
; In:   ESI = ptr symbolic name
;       ECX = length
;       EBX = ptr module symbolic info
PUBPROC FindMod16ExportedName
        lea     edi, [ebx].sh16_ModName[1] ;points the mod name
        mov     edx, ebx                ;keep it for module handle
        add     ebx, [ebx].sh16_Size    ;end of module (next module)
        DBGBRK  2
FM16XN_Loop:
        movzx   eax, byte ptr [edi-1]   ;length of the name
        lea     edi, [edi+eax].p16si_Name[1]
        cmp     edi, ebx
        jae     short FM16XN_NotFound
        cmp     cl, [edi-1]
        jne     short FM16XN_Loop
        call    strncmp
        jc      short FM16XN_Loop
        add     esi, ecx

        mov     cl, [edx].sh16_ModName
        push    dword ptr [edi-p16si_Name-1].p16si_Offset ;segment#:offset
        push    esi
        lea     esi, [edx].sh16_ModName[1]
        ; Find module from its name (ESI=module name, ECX=length)
        call    P16ModuleHandleFromName
        pop     esi
        pop     eax
        jc      short FM16XN_Done

GetAcutalSelector:
        ; EDX = ptr NE-Header
        ; eax = seg#:offset
        DBGBRK  3
        movzx   ebx, [edx].ne_segtab
        add     edx, ebx
        movzx   ebx, ax                 ;offset
        shr     eax, 16                 ;seg#
        imul    eax, size SEGMENT_TABLE_STRUC
        movzx   edx, [edx+eax-size SEGMENT_TABLE_STRUC].sg_handle
        HandleToSelector edx
;       clc
FM16XN_Done:
        ret

FM16XN_NotFound:
        stc
        ret

; ---------------------------------------------------------------------------
; In:   ESI = ptr symbolic name
;       EAX = ordinal number
;       EBX = ptr module symbolic info
;       EDX = ptr NE-Header
PUBPROC FindP16ExportByOrd
        mov     edi, ebx
        add     ebx, [ebx].sh16_Size    ;end of module (next module)
        DBGBRK  3
FX16FO_Loop:
        movzx   ecx, byte ptr [edi].p16si_Name ;length of the name
        lea     edi, [edi+ecx].p16si_Name[1]
        cmp     edi, ebx
        jae     FM16XN_NotFound
        cmp     ax, [edi].p16si_Ordinal
        jne     short FX16FO_Loop

        DBGBRK  3
        mov     eax, dword ptr [edi].p16si_Offset ;segment#:offset
        ; eax = seg#:offset
        ; EDX = ptr NE-Header
        jmp     GetAcutalSelector

; ---------------------------------------------------------------------------
; In:   ESI = ptr name
; Out:  CF=0  found the name, edx:ebx=address
;       CF=1  not found
PUBPROC GetAddressFromName
        call    GetSymbolLen
        jecxz   short P16AFN_NotFound

        DBGBRK  3
        cmp     al, '.'
        je      GetServiceFromName
;;      cmp     al, '('
;;      je      GetSectionNumber

        call    VxdAddressFromNameLen
        jnc     short P16AFN_Done

IFDEF   _W95_
        push    ecx
        call    P32AddressFromName
        pop     ecx
        jnc     short P16AFN_Done
ENDIF ; _W95_

; ---------------------------------------------------------------------------
PUBPROC P16AddressFromName
        DBGBRK  4
        mov     ebx, SymBuffer_Beg
P16AFN_Find:
        cmp     ebx, SymBuffer_End
        jae     short P16AFN_NotFound
        mov     eax, [ebx].sh16_Size    ;size of this module
        test    eax, eax
        jz      short P16AFN_NotFound
        call    FindMod16ExportedName
        jc      short P16AFN_Find
P16AFN_Done:
        ret

; ---------------------------------------------------------------------------
PUBPROC FindVxdByName
        DBGBRK  2
        mov     edx, VMM_DDB_BASE
VFBN_Find1:
        lea     edi, [edx].DDB_Name
        call    strncmp
        jc      short VFBN_Find2
        cmp     ecx, 8
        jae     short VFBN_Find3
        cmp     ah, 21h
        jb      short VFBN_Find3
VFBN_Find2:
        mov     edx, [edx].DDB_Next
        test    edx, edx
        jnz     short VFBN_Find1
P16AFN_NotFound:
        stc
        ret
VFBN_Find3:
        add     esi, ecx
;       clc
        ret

; ---------------------------------------------------------------------------

PUBPROC Stack_Walk
        DBGBRK  3

        mov     eax, [ebp].R_CS
        test    eax, eax
        js      short S16Wlk_Loop1
        lar     esi, eax
        bt      esi, 22
        jc      short S32Wlk_Loop1
S16Wlk_Loop1:
        DBGBRK  3
        push    ecx
        push    eax
S16Wlk_Loop2:
        ; Check for a near call (E8xxxx)
        call    SC16_NCall
        jnc     short S16Wlk_PushCsChk
        ; Check for a far call (9Aoooossss)
        call    SC16_FCall
        jnc     short S16Wlk_Next
        call    StkChk_Pop2
        jnc     short S16Wlk_Loop2
        pop     eax
        pop     ecx
        ret

S16Wlk_PushCsChk:
        call    SC16_PushCsCall
S16Wlk_Next:
        mov     ebx, ecx
        pop     ecx                     ; target CS
        pop     ecx
        loop    short S16Wlk_Loop1
S16Wlk_Done:
        ret

S32Wlk_Loop1:
        DBGBRK  3
        push    ecx
        push    eax
S32Wlk_Loop2:
        ; Check for a near call (E8xxxxxxxx)
        call    SC32_NCall
        jnc     short S32Wlk_PushCsChk
        ; Check for a far call (9Aoooooooossss)
        call    SC32_FCall
        jnc     short S32Wlk_Next
        test    def_segsize, DEFSEG_ZBASE
        jz      short @f
        call    SC32_WCall
        jnc     short S32Wlk_Next
@@:     call    StkChk_Pop4
        jnc     short S32Wlk_Loop2
        pop     ecx
        pop     ecx
        ret

S32Wlk_PushCsChk:
        call    SC32_PushCsCall
S32Wlk_Next:
        mov     ebx, ecx
        pop     ecx                     ; target CS
        pop     ecx
        cmp     ebx, OFFSET32 SPWIN_Beg_Of_LCode
        jb      short @f
        cmp     ebx, OFFSET32 SPWIN_End_Of_SCode
        jb      short S32Wlk_Done
@@:     loop    short S32Wlk_Loop1
        ; eax:ebx CALL edx:esi
        ; edi=SS:ESP
S32Wlk_Done:
        ret

PUBPROC Cmd_Stack
        DBGBRK  3
        mov     ebx, [ebp].R_ESP
        mov     eax, [ebp].R_SS
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      short S16Wlk_Done
        mov     dword ptr [StkWlk_SSBase], eax
        mov     eax, 2000h              ; max 8k of stack
        add     eax, ebx
        sbb     esi, esi
        or      eax, esi
        cmp     eax, edx                ; over the limit?
        jb      short @f
        xchg    eax, edx
@@:     mov     dword ptr [StkWlk_EspLimit], eax

        push    ebx                     ; sl_context lin address for SS:ESP

        mov     edi, ebx                ; linear address for SS:ESP
        xor     ecx, ecx
        mov     cl, 50                  ; maximum 50 levels
        call    Stack_Walk
        mov     al, 50
        sub     al, cl
        mov     cl, al
        push    ecx                     ; sl_limit
        push    0                       ; sl_index
        push    [ebp].R_ESP
        push    [ebp].R_SS
        call    scrollLines
        db      '   SS:ESP'
        db      d_lf,' ',d_h48,'  Caller CS:EIP  Callee CS:EIP',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        mov     edi, esi                ; linear address for SS:ESP
        inc     ecx
        call    Stack_Walk
        ; eax:ebx CALL edx:esi
        ; edi=SS:ESP

        push    esi

        push    esi
        push    edx
        push    ebx
        push    eax
        sub     edi, 80094d5bh          ; linear - base => ESP
StkWlk_SSBase   equ $-4
        push    edi
        push    [ebp].R_SS
        call    Printf
        db      ' ',d_h48,'  ',d_h48,'  ',d_h48,'  ',d_ret
        DBGBRK  3
        pop     eax
        push    edx
        push    eax
        ; edx:eax=address
        call    GetSymNameForAddress
        pop     ebx
        pop     edx
        ; edx:ebx=address
        jnc     short stk_show2
        mov     al, def_segsize
        xor     al, DEFSEG_ZBASE + DEFSEG_ADR32
        and     al, DEFSEG_ZBASE + DEFSEG_ADR32
        jnz     short stk_show1
        DBGBRK  3
        push    edx
        push    ebx
        call    SpecialGetP32Names
        pop     ebx
        pop     edx
        ; edx:ebx=address
        jnc     short stk_show2
stk_show1:
        jmp     SectionNameFromAddress
stk_show2:
        ret

; ---------------------------------------------------------------------------
; This function is called by the API command SPWCMD_SYMINFO
; In:   edi = ptr spapi_Data[0x2000]
;       ebx = command packet
; Out:  CF=0: ok
PUBPROC SPAPI_SYMINFO
        mov     edx, SymBuffer_Beg
        mov     eax, SymBuffer_End
        sub     eax, edx                ; Buffer size
        stosd
SymInfo_Loop:
        cmp     edx, SymBuffer_End
        jae     short SymInfo_Done
        mov     ecx, [edx].sh16_Size    ;size of module (next module)
        jecxz   short SymInfo_Done
        xchg    eax, ecx
        stosd
        cmp     [edx].sh16_Type, SYM_P32
        je      short SymInfo_P32
        lea     esi, [edx].sh16_ModName ;Lstring module name
        movzx   ecx, byte ptr [esi]     ;length of the module name
        inc     ecx                     ;include length
SymInfo_Name:
        rep     movsb
        add     edx, [edx].sh16_Size    ;end of module (next module)
        jmp     short SymInfo_Loop
SymInfo_P32:
        mov     esi, [edx].pex_Name
        add     esi, edx
        call    str_len
        mov     al, cl
        stosb
        jmp     short SymInfo_Name

SymInfo_Done:
        xor     eax, eax                ;terminator
        stosd
        xchg    eax, edx
        sub     eax, SymBuffer_Beg
        stosd                           ;size of buffer used
        clc
        ret

; In:   edi = ptr spapi_Data[0x2000]
;       ebx = command packet
; Out:  CF=0: ok
PUBPROC SPAPI_SYMLOAD
        mov     esi, edi
        ; first locate end of the sym memory and verify its size
        mov     edi, SymBuffer_Beg
        mov     eax, SymBuffer_End
SymAdd_FindEnd:
        mov     ecx, [edi].sh16_Size    ;end of module (next module)
        jecxz   short SymAdd_Found
        add     edi, ecx
        cmp     edi, eax
        jb      short SymAdd_FindEnd
SymAdd_Failed:
        stc                             ;failed
        ret
SymAdd_Found:
        mov     ecx, [ebx].spapi_Length
        add     edi, [ebx].spapi_Offset
        lea     edx, [edi+ecx]
        cmp     eax, edx                ;memory enough?
        jb      short SymAdd_Failed
        rep     movsb
;       clc
        ret

; In:   edi = ptr spapi_Data[0x2000]
;       ebx = command packet
; Out:  CF=0: ok
PUBPROC SPAPI_SYMREMV
        mov     ecx, [edi]              ;sym index to remove
        mov     edi, SymBuffer_Beg
        mov     eax, SymBuffer_End
        jecxz   short SymRmv_Found
SymRmv_Loop1:
        cmp     edi, eax
        jae     short SymRmv_Done
        mov     esi, [edi].sh16_Size    ;end of module (next module)
        test    esi, esi                ;size of this module
        jz      short SymRmv_Done
        add     edi, esi                ;end of module (next module)
        loop    short SymRmv_Loop1
SymRmv_Found:
        mov     esi, [edi].sh16_Size    ;end of module (next module)
        add     esi, edi
        xchg    ecx, eax                ;end of buffer
        sub     ecx, esi
        jb      short SymRmv_Done
        rep     movsb
SymRmv_Done:
        ret

LCODE_ENDS      ; ===========================================================
end

