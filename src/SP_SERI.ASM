title.  SoftProbe - Serial Remote support

SP_SERI EQU 1
include SP_DEFS.inc
include SP_SCRN.inc
include SP_COMM.inc

; ---------------------------------------------------------------------------
LDATA_SEG

Saved_KBShift   db 0

LDATA_ENDS

LCODE_SEG
; ---------------------------------------------------------------------------
; In:   ESI = start of block
;       EDI = end of block
Serial_Display label near
        DBGBRK  3
        mov     al, a_n
Seri_DispLoop:
        call    Serial_Xchange
        lodsb
        cmp     esi, edi
        jbe     short Seri_DispLoop
        ret

Serial_Input label near
        mov     al, s_retkey            ;dsp_RetKey
        call    Serial_Xchange          ;send command
        call    Serial_Xchange          ;get the keystroke
        and     eax, 0ffh
        ret

; ---------------------------------------------------------------------------
; In:   AL = col
;       AH = row
Serial_Cursor label near
        xchg    ecx, eax
        mov     al, s_cursor            ;set cursor position
        call    Serial_Xchange          ;dsp_cursor
        mov     al, cl                  ;col
        call    Serial_Xchange
        mov     al, ch                  ;row

        ; fall through Serial_Xchange

; ---------------------------------------------------------------------------
;
;       Read a character from 8250 if one is available and return it in AL.
;       ZF=1 indicats no character is available
;
Serial_Xchange  label near
        push    edx
        push    ebx
        push    ecx
        movzx   ebx, DosInfo.SerialPort ;base 8250
        SERIAL_Host ebx, ecx, edx
        pop     ecx
        pop     ebx
        pop     edx
        ret

Serial_Sync     label near
        push    edx
        push    ebx
        push    ecx
        movzx   ebx, DosInfo.SerialPort ;base 8250
        SERIAL_HostSync ebx, ecx, edx, CheckAbortConnection
        pop     ecx
        pop     ebx
        pop     edx
        ret

; ---------------------------------------------------------------------------

PUBPROC Serial_Init
        DBGBRK  5
        mov     eax, 115200
        movzx   ecx, DosInfo.SerialDivisor
        jecxz   short @f
        xor     edx, edx
        div     ecx
@@:     push    eax
        push    dword ptr DosInfo.SerialPort
        call    Printf
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,'ð',d_spc,input_line_size,'³ESC=Cancel',d_clreol
        db      d_col,2,'Connecting Through Serial Port ',d_h16
        db      ', Baud=',d_deci,'...',d_el

        DBGBRK  4
        ; set up the port
        movzx   ebx, DosInfo.SerialPort ;base 8250
        movzx   ecx, DosInfo.SerialDivisor
        COM_Init ebx, ecx, edx, 00000011b ;N81

        ; connect to the Remote
Seri_Connect:
        DBGBRK  4

        mov     al, s_reconnect
        CALL    Serial_Sync
        cmp     al, '+'
        jne     Seri_Connect

        mov     al, 1ch
        CALL    Serial_Sync
        cmp     al, '-'
        jne     Seri_Connect

        call    Usr_Screen_NP
        call    Select_Screen
        db      SCR_SERIAL
        dd      OFFSET32 Serial_Input
        dd      OFFSET32 Serial_Display
        dd      OFFSET32 Serial_Cursor
        dd      OFFSET32 Serial_ProbeScreen
        dd      OFFSET32 Serial_UserScreen
        dd      00000000h               ; a_f a_r a_b a_n
Serial_ProbeScreen label near
Serial_UserScreen label near
        mov     al, Saved_KBShift
        xchg    al, KeyShift
        mov     Saved_KBShift, al
        ret

LCODE_ENDS
END

