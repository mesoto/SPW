title.  SoftProbe - Parallel Remote support

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

SP_PARA EQU 1
include SP_DEFS.inc
include SP_SCRN.inc
include SP_COMM.inc

; ---------------------------------------------------------------------------
LDATA_SEG

Saved_iPort     db 0
Saved_oPort     db 0
Saved_KBShift   db 0

LDATA_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG

prt_col:mov     ch, [esi]
        inc     esi
        sub     ch, cl
        ja      short prt_bl
        jz      short prt_next
        jmp     short prt_cr

prt_spc:mov     ch, [esi]
        inc     esi
        jmp     short prt_bl

prt_dup:mov     ch, [esi]
        inc     esi
        mov     ah, [esi]
        inc     esi
        jmp     short prt_nchr

prt_tab:mov     ch, 7
        add     ch, cl
        and     ch, 7
        inc     ch
prt_bl: mov     ah, ' '
prt_nchr:
        mov     al, ah
        inc     cl
        call    PrintChar
        dec     ch
        jnz     short prt_nchr
        jmp     short prt_next

prt_any:lodsb
        cmp     al, 20h
        jae     short prt_loop
        mov     al, '.'
        jmp     short prt_loop

prt_lf:
        if      s_lf-0ah
        mov     al, 0ah
        endif
        call    PrintChar
        ; follow it with CR
; ---------------------------------------------------------------------------
; In:   ESI = ptr text  to print
; Out:  None
PUBPROC PrintLine
        DBGBRK  3
prt_cr: mov     al, 0dh
        mov     cl, 0ffh                ; cl=col#
prt_loop:
        call    PrintChar
        inc     cl
prt_next:
        DBGBRK  3
        lodsb
        cmp     al, 20h
        jae     short prt_loop
        cmp     al, s_lf
        je      short prt_lf
        cmp     al, s_col
        je      short prt_col
        cmp     al, s_tab
        je      short prt_tab
        cmp     al, s_spc
        je      short prt_spc
        cmp     al, s_dup
        je      short prt_dup
        cmp     al, s_chr
        je      short prt_any

        cmp     al, s_el
        jne     short prt_next

PUBPROC Cmd_PrintLF
        mov     al, 0ah
        ; PrintChar and return.

; ---------------------------------------------------------------------------
; In:   AL = character to print
; Out:  None
PUBPROC PrintChar

        push    edx
        movzx   edx, DosInfo.PrinterPort

        push    eax                     ; save the character

        ; wait for printer ready

        inc     edx                     ; status port
Wait_For_Printer_Ready:
        call    Check_Abort

        in      al, dx
        xor     al, 88h                 ; !BUSY (1=ready) & !ERR
        and     al, 0a8h                ; BUSY+PE+ERR
        jnz     short Wait_For_Printer_Ready

        pop     eax
        ; put character on line

        push    eax
        dec     edx                     ; back to data port
        call    Out_Delay

        ; send the strobe now

        inc     edx                     ; status port
        inc     edx                     ; command port
        mov     al, 0dh                 ; strobe low
        call    Out_Delay
        xor     al, 01h                 ; strobe high
        call    Out_Delay

        pop     eax
        pop     edx
        ret

PUBPROC Cmd_PrintFF
        mov     al, 0ch
        jmp     PrintChar

Out_Delay:
        out     dx, al
        mov     ah, 20
@@:     dec     ah
        jnz     short @b
Return1:ret

PUBPROC Check_Abort
        ; check if ABORT requested
        call    key_check
        cmp     al, K_ESC
        jne     short Return1

        reportError 'Print Aborted.'

; ---------------------------------------------------------------------------
; In:   ESI = start of block
;       EDI = end of block
Para_Display label near
        DBGBRK  3
        mov     al, a_n
Para_DispLoop:
        call    Para_Putc
        lodsb
        cmp     esi, edi
        jbe     short Para_DispLoop
        ret

; ---------------------------------------------------------------------------
Para_Input label near
        DBGBRK  3
        mov     al, s_retkey            ;dsp_RetKey
        call    Para_Putc               ;send command
        mov     al, 0
        call    Para_Putc               ;read the key
        DBGBRK  3
        and     eax, 0ffh
        ret

; ---------------------------------------------------------------------------
; In:   AL = col
;       AH = row
Para_Cursor label near
        DBGBRK  3
        push    edx
        xchg    edx, eax
        mov     al, s_cursor            ;set cursor position
        call    Para_Putc               ;dsp_cursor
        mov     al, dl                  ;col
        call    Para_Putc
        mov     al, dh                  ;row
        pop     edx

        ; gall through Para_Putc

; ---------------------------------------------------------------------------
;
; IN:   AL = char to send
Para_Putc label near
        push    edx
        movzx   edx, DosInfo.ParaPort
        PARA_HostXchg CheckAbortConnection
        pop     edx
        ret

        PARA_HostIO

; ---------------------------------------------------------------------------
PUBPROC Para_Init
        push    dword ptr DosInfo.ParaPort
        call    Printf
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,'ð Connecting Through Parallel Port ',d_h16,'...'
        db      d_spc,input_line_size-41,'³ESC=Cancel',d_clreol,d_el

        ; connect to the Remote
Para_Connect:
        DBGBRK  3

        mov     al, s_reconnect
        CALL    Para_Putc
        cmp     al, '+'
        jne     Para_Connect

        mov     al, 1ch
        CALL    Para_Putc
        cmp     al, '-'
        jne     Para_Connect

        call    Usr_Screen_NP
        call    Select_Screen
        db      SCR_PARA
        dd      OFFSET32 Para_Input
        dd      OFFSET32 Para_Display
        dd      OFFSET32 Para_Cursor
        dd      OFFSET32 Para_ProbeScreen
        dd      OFFSET32 Para_UserScreen
        dd      00000000h               ; a_f a_r a_b a_n
Para_ProbeScreen label near
Para_UserScreen  label near
        mov     al, Saved_KBShift
        xchg    al, KeyShift
        mov     Saved_KBShift, al
        ret

; ---------------------------------------------------------------------------
Handle_Line2:
        cmp     [ebx], ch
        je      short @f
        mov     al, s_lf
        stosb
        mov     eax, dword ptr [dissBuffSeg]
        stosd
        mov     al, ':'
        stosb
        ret
@@:     inc     esi                     ; skip d_text,80
        inc     esi
        ret

PUBPROC Cmd_PrintCode
        DBGBRK  3
        mov     edi, OFFSET32 dissBuffSeg
        mov     eax, edx
        call    hex_16
        mov     al, ':'
        stosb
        mov     actual_IP, ebx          ; used by dispins
        push    edx
        push    ecx
        xchg    eax, edx
        call    Get_Def_SegSize
        pop     ecx
        pop     edx
        call    Print_Setup

printc_loop:
        push    ecx

        call    dispins
        push    ebx

        mov     ebx, OFFSET32 dissBuffSeg
        call    Printf
        db      d_text,80
        _jsr    Handle_Line2
        db      d_text,80,d_ret

        DBGBRK  3
        call    Log_DisplayBuffer
        call    Check_Abort
        pop     ebx
        pop     ecx
        cmp     ebx, ecx
        jb      printc_loop
        ret

; In:   edx:ebx = address
;       ecx=size
; Out:  edx=selector base
;       ebx=linear address
;       ecx=linear address end
;       dissBuffSeg => ssss:
PUBPROC Print_Setup
        push    ecx

        xchg    eax, edx
        call    Get_FlatAddress         ; eax=base, ebx=linear address
        jc      addressError
        xchg    edx, eax                ; base needed for Cmd_PrintCode

        test    Log_Falgs, LF_LOGCMD
        jnz     short @f
        or      Log_Falgs, LF_PRINT
@@:
        call    Printf
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,' Printing...',d_spc,49,'³ESC=Cancel'
        db      d_clreol,d_el

        pop     ecx
        add     ecx, ebx                ; end of block
        ret

; ---------------------------------------------------------------------------
sub_ebx_16:
        sub     ebx, 16
        ret

PUBPROC Cmd_PrintData                   ; eax = format
        DBGBRK  3
        push    eax                     ; format
        call    Scan_BlockData          ; edx:ebx = address, ecx=size
        push    edx                     ; segment
        push    ebx                     ; offset
        call    Print_Setup
        pop     esi                     ; offset

printd_loop:
        ; [esp+0] = segment
        ; [esp+4] = format
        mov     edx, [esp+4]            ; format
        movzx   eax, byte ptr [edx]     ; size
        inc     edx                     ; skip size
        add     eax, esi

        push    ecx
        push    eax                     ; offset

        push    esi                     ; offset
        push    dword ptr [esp+0ch]     ; segment
        call    Printf
        db      d_h48,' ',d_sub,d_ret

        DBGBRK  3
        push    ebx
        call    Log_DisplayBuffer
        call    Check_Abort
        pop     ebx

        pop     esi
        pop     ecx
        cmp     ebx, ecx
        jb      printd_loop
        pop     edx                     ; segment
        pop     eax                     ; format
        ret

LCODE_ENDS
END

