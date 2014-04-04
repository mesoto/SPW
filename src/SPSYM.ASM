INCLUDE SPXPO.ASM

; -------------------------------------------------------------------------**
; In:   DS:IO_Buffer = file name (can be used as scratch memory, size=2000h)
;       DS=ES = CS
Sym_Load:
        DBGBRK  2, 60H
        call    message
        db      13,10,'Loading: ',0
        mov     si, offset IO_Buffer
        call    disp_msg

        DBGBRK  2, 60H
        mov     ax, Sym_Save_Seg
        push    ax
        push    0                       ;xl_savebuffer (64k)
        add     ax, 1000h
        push    ax
        push    0                       ;xl_sortbuffer (64k)
        push    cs
        push    offset Sym_Buffer       ;xl_tempbuffer (512 bytes)
        push    cs
        push    offset IO_Buffer        ;xl_filename
        push    cs
        call    near ptr XportLoader
        movzx   ecx, ax                 ;0=error, else length
        jcxz    short xpo_failed

        DBGBRK  2, 60H
        mov     edi, xms_symBuff_beg    ;destination offset
        lea     eax, [edi+ecx+4]
        cmp     eax, xms_symBuff_end    ;end of symbol information
        jae     short sym_not_loaded

        add     xms_symBuff_beg, ecx
        xor     ax, ax
        mov     dx, Sym_Save_Seg
        add     cx, 4                   ;+4 for length of next module
                                        ;length of block to copy to xms
        ; dx:ax seg:off for the source
        ; cx    length in bytes
        ; edi   destination offset
        jmp     Copy_To_Xms

sym_not_loaded:
        call    message
        db      13,10,'Not enough SYM memory allocated.'
        db      13,10,'Press any key to continue.',0
        mov     ah, 8
        int     21h
        ret

xpo_failed:
        call    message
        db      '  FAILED.',0
        ret
