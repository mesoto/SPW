title.  SoftProbe - DOS and v86 support

SP_MDOS EQU 1
include SP_DEFS.inc

; ---------------------------------------------------------------------------
LDATA_SEG
; ---------------------------------------------------------------------------

int_buf dd 256 dup (0)

public  DosInfo
DosInfo DosInfoStru <>

LDATA_ENDS

; ---------------------------------------------------------------------------
SCODE_SEG       ; Safe code area (No Pushes inside calls)
; ---------------------------------------------------------------------------
Walk_v86mem:
        movzx   edx, DosInfo.FirstMemBlock
walk_mem1:
        imul    ebx, edx, 16
        mov     al, [ebx]
        movzx   esi, word ptr [ebx+3]   ;LEN
        cmp     al, 'M'
        loope   short walk_mem3
        je      short walk_mem2
        cmp     al, 'Z'
        jne     short walk_mem4
walk_mem2:
        movzx   edi, word ptr [ebx+1]   ; PSP
        cmp     edi, 40h                ; PSP < 40h
        jb      short walk_mem5
        imul    ebx, edi, 16
        cmp     di, [ebx-16][1]         ; Should be PSP again
        jne     short walk_mem4
        movzx   eax, word ptr [ebx+2ch] ; ENV
        sub     ebx, 8                  ; ARENA:8=name
        ret
walk_mem3:
        stc
        adc     dx, si
        jnc     short walk_mem1
walk_mem4:
        xor     eax, eax                ; ENV
        stc
        ret
walk_mem5:
        test    edi, edi
        mov     ebx, OFFSET32 Owner_System
        jnz     short walk_mem6
        mov     ebx, OFFSET32 Owner_Free
walk_mem6:
        xor     eax, eax                ; ENV
        ret

; ---------------------------------------------------------------------------
; In:   ecx = logical record number
;       ah  = last block device letter
; Out:  CF  = 0 if found, ebx=ptr device header, edx=seg:off
Walk_v86Dev:
        mov     edx, DosInfo.NullDevicePtr
walk_Dev1:
        mov     edi, edx
        xor     ebx, ebx
        xchg    bx, di
        shr     edi, 12
;;      add     ebx, VM_Base_Address
        add     ebx, edi
        mov     al, [ebx+5]
        test    al, 80h
        jnz     short walk_Dev2
        sub     ah, [ebx+10]
walk_Dev2:
        loop    short walk_Dev3
        ret

walk_Dev3:
        mov     edx, [ebx]
        cmp     dx, -1
        jne     short walk_Dev1
walk_Dev4:
        stc
        ret

;----------------------------------------------------------------------------
; In:   AX:BX = seg:off
; Out:  EDX = PSP of the owner (if CF=0)
;       ESI = max 8 char name
;       CF = 0 if name found
PUBPROC V86_Owner
        ; ax:bx=seg:off
        DBGBRK  5
        mov     esi, OFFSET32 Zeros
        movzx   ecx, ax
        movzx   ebx, bx
        shr     ebx, 4
        add     ecx, ebx
        movzx   edx, DosInfo.FirstMemBlock
        sub     ecx, edx
        jb      short get_ownr2

get_ownr1:
        imul    ebx, edx, 16
        movzx   eax, word ptr [ebx][3] ;block length
        inc     eax
        sub     ecx, eax
        jc      short get_ownr3
        add     edx, eax                ;next bloxk
        cmp     byte ptr [ebx], 'M'
        je      short get_ownr1
get_ownr2:
        stc
        ret                     ;proc name not found
get_ownr3:
        movzx   edx, word ptr [ebx+1]   ;PSP
        cmp     edx, 40h
        jb      short get_ownr2
        imul    ebx, edx, 16            ;ptr PSP
        cmp     word ptr [ebx], 20cdh   ;int 20 marker?
        jne     short get_ownr2         ;corrupted memory block
        cmp     dx, [ebx-15]            ;block blongs to PSP?
        jne     short get_ownr2         ;no, name not found
        lea     esi, [ebx-8]            ;arena:8 = name
        ret

;----------------------------------------------------------------------------
; In:   AX:BX = seg:off
; Out:  EBX = PSP of the owner
;       ECX = ENV
;       CF = 0 if name found
PUBPROC V86_Owner_Path
        call    V86_Owner
        jc      short get_procnam2

        ; edx = PSP
        ; esi = arena:8

        movzx   ecx, word ptr [esi+8][2ch] ;environment
        jecxz   short get_procnam2
        imul    edi, ecx, 16
        cmp     dx, [edi-16+1]          ;block blongs to PSP?
        jne     short get_procnam2      ;no, name not found

        ; locate the pathname in the ENV

        mov     ch, 80h                 ;max 32k
        xor     eax, eax
get_procnam1:
        repne   scasb
        jne     short get_procnam3
        scasb
        jne     short get_procnam1

        mov     ax, [edi]
        dec     ax                      ;1,0 if progname there
        jne     short get_procnam3
        mov     ah, 80+1
        lea     esi, [edi+2]
        jmp     short get_procnam4
get_procnam2:
get_procnam3:
        mov     ah, 8+1                 ;max 8 chars
get_procnam4:
        mov     edi, OFFSET32 dissBuffOff
        movzx   ecx, ah
        jmp     strncpy

PUBPROC saveIntrs
;;      mov     esi, VM_Base_Address
        xor     esi, esi
        mov     edi, OFFSET32 int_buf
        xor     ecx, ecx
        mov     ch, 1                   ;ecx=100h
        rep     movsd
        ret

SCODE_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------

mem_types       db 3,'   ','PSP','ENV'
Owner_System    db 'System',0
Owner_Free      db 'Free',0

PUBPROC Cmd_MapV86Mem
        DBGBRK  3
        xor     ecx, ecx
        call    Walk_v86mem
        neg     ecx
        push    ecx                     ;sl_limit
        push    0                       ;sl_index
        call    scrollLines
        db      'TYPE  START  LEN   ENV   PSP   OWNER',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        inc     ecx
        call    Walk_v86mem
        jc      short map_mem1
        ; edx=Block start, esi=Len, edi=PSP, eax=ENV, ebx=ptr Name
        inc     edx
        push    edi                     ; PSP
        push    eax                     ; ENV
        push    esi                     ; LEN
        push    edx                     ; START
        cmp     edx, edi
        sete    cl                      ; 0=Psp
        cmp     edx, eax
        jne     short @f
        mov     cl, 2                   ; 2=Env
@@:     push    ecx                     ; type
        call    Printf
        db      ' '
        _table  mem_types
        db      '  ',d_h16,'   ',d_h16,'  ',d_h16,'  '
        db      d_h16,'  ',d_text,t_fill+8,d_ret
        ret

map_mem1:
        inc     edx
        push    edi                     ; PSP
        push    esi                     ; LEN
        push    edx                     ; START
        call    Printf
        db      d_col,6,d_h16,'   ',d_h16,d_spc,8,d_h16,'  ?',d_ret
        ret

PUBPROC Cmd_DosDevices
        DBGBRK  3
        xor     ecx, ecx
        mov     ah, 0
        call    Walk_v86Dev
        neg     ah                      ;#block devices
        add     ah, 'A'                 ;last block dev
        neg     ecx                     ;#devices
        push    eax                     ;sl_context
        push    ecx                     ;sl_limit
        push    0                       ;sl_index
        call    scrollLines
        db      'HEADER     Stra  Intr  Attr  Device',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        xchg    eax, esi                ;ah=last device
        inc     ecx
        call    Walk_v86Dev
        ; ebx points to device header
        ; ah is the drive letter (if block device)
        ; edx=seg:off

        mov     ecx, [ebx+4]            ;attribute
        push    ecx                     ;attribute
        push    dword ptr [ebx+8]       ;Interrupt
        push    dword ptr [ebx+6]       ;Strategy
        push    edx                     ;off (header)
        shr     edx, 16
        push    edx                     ;seg (header)
        test    ch, ch
        jns     short map_device4
        mov     edx, [ebx+10]
        mov     eax, [ebx+14]
        jmp     short map_device5
map_device4:    
        mov     cl, [ebx+10]
        mov     edx, '  : '
        mov     dl, ah
        mov     eax, '    '
        dec     cl
        jz      short map_device5
        add     edx, ('-' - ' ') shl 24
        mov     eax, ' :  '
        mov     ah, dl
        add     ah, cl
map_device5:    
        mov     dword ptr ds:device_name[0], edx
        mov     dword ptr ds:device_name[4], eax
        call    Printf
        db      d_h16,':',d_h16,'  ',d_h16,'  '
        db      d_h16,'  ',d_h16,'  '
device_name     db '        ',d_ret
        ret

PUBPROC Cmd_DosInts
        DBGBRK  3
        jz      short @f
        call    Parse_Line
        FullCmd 'GET'  JUMP_ADDRS <OFFSET32 saveIntrs>
        db      0

        DBGBRK  3
        call    Scan_Dword
        xchg    eax, ebx
@@:     movzx   eax, al
;;      push    VM_Base_Address         ; sl_context -> esi
        push    100h                    ; sl_limit (max 100h ints)
        push    eax                     ; sl_index  -> edx
        call    scrollLines
        db      'INT#    WAS        NOW     OWNER',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        mov     ebx, [edx*4]
        mov     edi, int_buf[edx*4]
        mov     eax, ebx
        shr     eax, 16                 ;seg
        push    ebx                     ;now
        push    eax
        mov     ecx, edi                ;off
        shr     ecx, 16                 ;seg
        push    edi                     ;was
        push    ecx
        push    edx                     ;int#
        xor     edi, ebx
        push    edi                     ;d_skpz
        call    V86_Owner_Path          ;ax:bx=seg:off
        mov     ebx, OFFSET32 dissBuffOff
        call    Printf
        db      ' ',d_skpz,a_b,d_h08
        db      '  ',d_h16,':',d_h16
        db      '  ',d_h16,':',d_h16,'  ',d_text,t_fill+52,d_ret
        ret

LCODE_ENDS
END
