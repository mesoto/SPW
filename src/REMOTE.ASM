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

        name    REMOTE

        _16BIT_ EQU 1
        INCLUDE SP_DEFS.INC
        INCLUDE SP_COMM.INC

BRKDBG  MACRO
        IF DBG GE 4
        push    word ptr CS:KeyBuff_Head
        int     60h
        pop     word ptr CS:KeyBuff_Head
        ENDIF
        ENDM

.8086
_TEXT   segment word public 'CODE'
        assume  cs:_TEXT
        assume  ds:_TEXT
        assume  es:_TEXT

; ---------------------------------------------------------------------------
code_start:
                even
                db  512 dup (0) ; stack area
stack_bot       equ this word

Para_Port       dw 0
Serial_Port     dw 0                    ;base 8250 address
Serial_Divisor  dw DIVISOR_9600         ;default speed

IO_Xchange      dw offset Para_Xchange

; ---------------------------------------------------------------------------
KeyBuff         db 256 dup( 0 )
KeyBuff_Head    db 0
KeyBuff_Tail    db 0
Exit_Flag       db 0

Saved_iPort     db 0
Saved_oPort     db 0

Int09_Handler:
        pushf
        push    ax
        push    bx
        in      al, 60h
        mov     bl, cs:KeyBuff_Tail
        inc     bx
        cmp     bl, cs:KeyBuff_Head
        je      short @f
        dec     bx
        mov     bh, 0
        mov     cs:KeyBuff[bx], al
        inc     cs:KeyBuff_Tail
@@:     pop     bx
        pop     ax
        db      9ah             ;call seg:off
prev_Int09      dd 0
        ; flush kb-buffer
        push    ds
        push    bx
        mov     bx, 40h
        mov     ds, bx
        mov     bx, ds:[1ch]  ;kb-buffer-tail
        mov     ds:[1ah], bx  ;kb-buffer-head
        cmp     word ptr [bx-2], 6700h  ; Ctrl-F10
        jne     short @f
        not     byte ptr [bx-2]         ; no match next time
        test    byte ptr ds:[17h], 3    ; shift?
        jz      short @f
        mov     cs:Exit_Flag, 0ffh
@@:     pop     bx
        pop     ds
        iret

Idle_Proc label near
        cmp     Exit_Flag, 0ffh
        je      short Exit_Remote
        ret

Exit_Remote:
        lds     dx, cs:prev_Int09
        mov     ax, 2509h
        int     21h

        mov     ax, 3
        int     10h

        call    msg_quit
        db      13,10,'SP-Remote terminated.',0,0

; ---------------------------------------------------------------------------
;
        PARA_SlaveIO Idle_Proc

Para_Xchange    label near
        push    dx
        mov     dx, Para_Port
        PARA_SlaveXchg
        and     ax, 0ffh
        pop     dx
        ret

; ---------------------------------------------------------------------------
;
;       Read a character from 8250 if one is available and return
;       ZF=1 indicats no character is available
;
Serial_Xchange label near
        push    dx
        mov     bx, Serial_Port         ;base 8250
        SERIAL_Slave Idle_Proc
        and     ax, 0ffh
        pop     dx
        ret

; ---------------------------------------------------------------------------
disp_mesg:
        push    cs
        pop     ds
        mov     dx, si
        cld
@@:     lodsb
        cmp     al, 0
        jne     @b
        lea     cx, [si-1]
        sub     cx, dx
        mov     ah, 40h
        mov     bx, 1                   ;stdout
        int     21h
        ret

disp_Msg:
        pop     si
        call    disp_mesg
        jmp     si

msg_quit:
        pop     si
        call    disp_mesg
        lodsb
        mov     ah, 4ch
        int     21h

; ---------------------------------------------------------------------------
even
dsp_cmdTable    dw @@s_el               ;00
                dw @@s_norm             ;01 a_n
                dw @@s_bold             ;02 a_b
                dw @@s_rvrs             ;03 a_r
                dw @@s_fram             ;04 a_f
                dw @@s_wtop             ;05 1st scrollable line
                dw @@s_col              ;06 go column x (change it to mv2)
                dw @@s_row              ;07 go row x, col 0
                dw @@s_dup              ;08
                dw @@s_tab              ;09
                dw @@s_lf               ;0a scroll output window
                dw @@s_spc              ;0b
                dw @@s_window           ;0c open full sized window
                dw @@s_clreol           ;0d
                dw @@s_chr              ;0e
                dw @@s_el               ;0f
                dw @@s_el               ;10
                dw @@s_el               ;11
                dw @@s_el               ;12
                dw @@s_el               ;13
                dw @@s_el               ;14
                dw @@s_el               ;15
                dw @@s_el               ;16
                dw @@s_el               ;17
                dw @@s_el               ;18
                dw @@s_el               ;19
                dw @@s_el               ;1a
                dw @@s_reconnect        ;1b
                dw @@s_el               ;1c
                dw @@s_el               ;1d
                dw @@s_RetKey           ;1e
                dw @@s_cursor           ;1f

; ---------------------------------------------------------------------------
line_start      dw 0
win_1stLine     dw 0
win_lastLine    dw 24*160
PrevPos         dw 0

                ;   a_n, a_b, a_r, a_f
Attrib          db  07h, 0fh, 70h, 07h  ; Mono Attributes
Mono_Attrib     db  07h, 0fh, 70h, 07h  ; Mono Attributes
Color_Attrib    db  17h, 1eh, 71h, 13h  ; Color Attributes

;Color_Attrib    db  07h, 0fh, 71h, 0bh, 0cbh    ; Color Attributes
;Color_Attrib    db  17h, 1fh, 70h, 13h, 0c3h    ; Color Attributes

; ---------------------------------------------------------------------------
@@s_RetKey:
        cli
        mov     al, KeyBuff_Head
        mov     bl, al
        xor     al, KeyBuff_Tail
        jz      short @f
        mov     bh, 0
        mov     al, KeyBuff[bx]
        inc     KeyBuff_Head
@@:     sti
        call    IO_Xchange
        jmp     Msg_Loop

Init_CommPort:
        cmp     IO_Xchange, offset Serial_Xchange
        jne     short Init_Paral

        mov     ax, Serial_Port
        call    get_PortAddress
        mov     Serial_Port, ax
        jmp     short Init_Sys

Init_Paral:
        mov     ax, Para_Port
        add     ax, 4
        call    get_PortAddress
        mov     Para_Port, ax
Init_Sys:
        mov     ax, 3509h
        int     21h
        mov     word ptr prev_Int09[0], bx
        mov     word ptr prev_Int09[2], es
        mov     dx, offset Int09_Handler
        mov     ax, 2509h
        int     21h

        call    disp_Msg
        db      13,10,'Using: '
commPort        db 'LPT1:'
        db      13,10,'Press Shift-Ctrl-F10 to quit.'
        db      13,10,'Waiting for connection....',0

        BRKDBG
        cmp     IO_Xchange, offset Serial_Xchange
        jne     short Connect_Loop

        mov     bx, Serial_Port         ;base 8250
        mov     cx, Serial_Divisor
        COM_Init bx, cx, dx, 00000011b  ;N81

Connect_Loop:
        mov     al, 0ffh
        CALL    IO_Xchange
        cmp     al, s_reconnect
        jne     short Process_Commands

@@s_reconnect:
        mov     al, '+'
        CALL    IO_Xchange
        cmp     al, s_reconnect
        jne     Connect_Loop
        mov     al, '-'
        CALL    IO_Xchange
        cmp     al, 1ch
        jne     Connect_Loop

Process_Commands:
        BRKDBG
        mov     KeyBuff_Head, 0          ; flush keyboard buffer
        mov     KeyBuff_Tail, 0
        mov     ax, 0b800h
        mov     es, ax
        cld
        xor     di, di
@@s_el:
@@s_norm:
        mov     dh, Attrib[a_n-a_n]
        jmp     short Msg_Loop
@@s_bold:
@@s_rvrs:
@@s_fram:
        shr     bx, 1
        mov     dh, Attrib[bx-a_n]
        jmp     short Msg_Loop

@@s_chr:call    IO_Xchange
dsp_put:mov     ah, dh                  ; restore attributes
        stosw
Msg_Loop:
        call    IO_Xchange
        BRKDBG
        cmp     al, 20h
        jae     dsp_put
        mov     bx, ax
        shl     bx, 1
        BRKDBG
        jmp     dsp_cmdTable[bx]

@@s_col:call    IO_Xchange
        mov     di, line_start
        shl     ax, 1
        add     di, ax
        jmp     Msg_Loop

@@s_tab:mov     ax, di
        shr     ax, 1
        or      ax, not 7
        neg     ax
        xchg    cx, ax
        mov     al, ' '
        mov     ah, dh
        rep     stosw
        jmp     Msg_Loop

@@s_clreol:
        mov     ax, di
        shr     ax, 1
        mov     cx, 80
        div     cl
        sub     cl, ah
        mov     al, ' '
        mov     ah, dh
        rep     stosw
        jmp     Msg_Loop

@@s_cursor:
        push    dx                      ;save attrib
        call    IO_Xchange              ;col
        xchg    dx, ax
        call    IO_Xchange              ;row
        mov     dh, al
        mov     bh, 0                   ;page
        mov     ah, 2                   ;set cursor position
        int     10h
        pop     dx                      ;attribute
        jmp     Msg_Loop

@@s_window:
        call    IO_Xchange               ;window height
        and     al, 3fh
        mov     cl, 80
        mul     cl
        xchg    cx, ax
        xor     di, di
        mov     ah, Attrib[a_n-a_n]
        mov     al, ' '
        rep     stosw
        xchg    dx, ax                  ;dh=attr
        mov     win_lastLine, di
        xor     di, di
@@s_wtop:
        mov     win_1stLine, di
        mov     line_start, di
        jmp     Msg_Loop

@@s_lf: mov     di, line_start
        mov     cx, win_lastLine
        add     di, 160
        cmp     di, cx
        jb      short clrNewLine
        mov     di, win_1stLine
        lea     si, 160[di]
        sub     cx, si
        shr     cx, 1
        rep     movs word ptr es:[di], word ptr es:[si]
clrNewLine:
        mov     cx, 80
        mov     ah, dh                  ;dh=attr
        mov     al, ' '
        push    di
        rep     stosw
        pop     di
        mov     line_start, di
        jmp     Msg_Loop

@@s_dup:call    IO_Xchange               ;number of times
        push    ax
        call    IO_Xchange               ;char
        pop     cx
        mov     ah, dh
        rep     stosw
        jmp     Msg_Loop

@@s_spc:call    IO_Xchange               ;number of times
        xchg    cx, ax
        mov     ah, dh
        mov     al, ' '
        rep     stosw
        jmp     Msg_Loop

@@s_row:call    IO_Xchange               ;row number
        xor     di, di
        shl     al, 1
        jnc     short @f
        mov     di, line_start
@@:     mov     cl, 80
        mul     cl
        add     di, ax
        mov     line_start, di
        jmp     @@s_norm

; ---------------------------------------------------------------------------
blank_skip:
        lodsb
        cmp     al, 9
        je      short blank_skip
        cmp     al, ' '
        je      short blank_skip
        dec     si
        ret

; ---------------------------------------------------------------------------
decimal_val:
        call    blank_skip
        xor     bx, bx
        xor     dx, dx                  ;dx:bx=32-bit accumulator
        mov     ah, 1
get_val1:
        lodsb
        sub     al, '0'
        cmp     al, 10
        jae     get_val2
        and     ax, 0fh
        xor     cx, cx
        shl     bx, 1
        rcl     dx, 1                   ;2*n
        add     ax, bx
        adc     cx, dx                  ;2*n+a
        shl     bx, 1
        rcl     dx, 1                   ;4*n
        shl     bx, 1
        rcl     dx, 1                   ;8*n
        add     bx, ax
        adc     dx, cx
        mov     ah, 0
        jmp     short get_val1

get_val2:
        dec     si
        shr     ah, 1                   ; CF=1 if no digit found
        xchg    ax, bx                  ; dx:ax=value
        ret

; ---------------------------------------------------------------------------
ChkCmd  macro c, a
        local t1, t2
        db    t2
t1      db    c
t2      equ   ($-t1)
        dw    a
        endm

DecodeLine:
        call    blank_skip
        pop     di
        jmp     short pl_search1
pl_search3:
        mov     bl, ah
        lea     di, [di+bx+2]
pl_search1:
        xor     bx, bx
        mov     ah, [di]        ;len + type*16
        inc     di
        and     ah, 15          ;len
        jz      short pl_not_found
pl_search2:
        mov     al, [si+bx]
        xor     al, [di+bx]
        jz      short pl_search4
        cmp     al, 20h
        jne     short pl_search3
        mov     al, [si+bx]
        sub     al, 'a'
        cmp     al, 'z'-'a'+1
        jae     short pl_search3
pl_search4:
        inc     bx
        cmp     bl, ah
        jb      short pl_search2
        add     si, bx
        jmp     word ptr [di+bx]

pl_not_found:
        stc
        jmp     di

; ---------------------------------------------------------------------------
SP_Remote:
        BRKDBG
        mov     dx, cs
        mov     ss, dx
        mov     sp, offset stack_bot
        mov     es, dx

        cld
        mov     si, 80h
        mov     di, offset cmd_line
        lodsb
        mov     ah, 0
        xchg    cx, ax
        rep     movsb
        mov     ds, dx

        int     11h
        and     al, 30h
        cmp     al, 30h
        je      @f
        mov     si, offset Color_Attrib
        mov     di, offset Attrib
        movsw
        movsw
@@:
        mov     ax, 3
        int     10h

        call    disp_Msg
        db      'SoftProbe Remote - Release ',VER_STR,13,10
        db      'Copyright (C) Mehdi Sotoodeh 1995.  '
        db      'All rights reserved.',13,10,0

        mov     si, offset cmd_line
Cmd_Decode:
        call    DecodeLine
        ChkCmd  <0>     Init_CommPort
        ChkCmd  'LPT'   define_ParaPort
        ChkCmd  'COM'   define_SeriPort
        ChkCmd  'MONO'  force_MonoScreen
        ChkCmd  'COLOR' force_ColorScreen
        ChkCmd  '-?'    show_syntax
        ChkCmd  '/?'    show_syntax
        ChkCmd  '-H'    show_syntax
        ChkCmd  '/H'    show_syntax
        db 0

        call    disp_Msg
        db      13,10,'Command line error.',0
show_syntax:
        call    msg_quit
        db      13,10,'USAGE:'
        db      13,10,'REMOTE [LPTx | [COMx[:baud]]] [MONO | COLOR]',0,1

force_ColorScreen:
        mov     ax, offset Color_Attrib
set_colors:
        xchg    si, ax
        mov     di, offset Attrib
        movsw
        movsw
        xchg    si, ax
Cmd_Decode1:
        jmp     Cmd_Decode

force_MonoScreen:
        mov     ax, offset Mono_Attrib
        jmp     short set_colors

define_SeriPort:
        call    decimal_val
        jc      undefPort_error
        dec     ax
        cmp     ax, 4
        jae     badPort_error
        mov     Serial_Port, ax
        mov     word ptr commPort[0], 'OC'
        mov     word ptr commPort[2], '1M'
        add     byte ptr commPort[3], al
        mov     IO_Xchange, offset Serial_Xchange

        cmp     byte ptr [si], ':'
        jne     Cmd_Decode1
        inc     si

        call    decimal_val             ;baud rate?
        jc      Cmd_Decode1
        ; dx:ax = baud rate
        shr     dx, 1
        jnz     baudRate_error          ;max is 1 (115200=1c200h)
        rcr     ax, 1
        xchg    cx, ax
        jcxz    baudRate_error
        mov     ax, 0e100h              ;115200/2=1c200/2
        div     cx
        test    ax, ax
        jz      baudRate_error
        test    dx, dx
        jnz     baudRate_error
        mov     Serial_Divisor, ax
        jmp     Cmd_Decode

undefPort_error:
        call    msg_quit
        db      13,10,'Port number not defined.',0,1

baudRate_error:
        call    msg_quit
        db      13,10,'Invail baud rate.',0,1

badPort_error:
        call    msg_quit
        db      13,10,'COM1-COM4 and LPT1-LPT3 are supported.',0,1

define_ParaPort:
        call    decimal_val
        jc      undefPort_error
        dec     ax
        cmp     ax, 3
        jae     badPort_error
        mov     Para_Port, ax
        mov     word ptr commPort[0], 'PL'
        mov     word ptr commPort[2], '1T'
        add     byte ptr commPort[3], al
        mov     IO_Xchange, offset Para_Xchange
        jmp     Cmd_Decode

get_PortAddress:
        push    ds
        xchg    bx, ax
        shl     bx, 1
        mov     ax, 40h
        mov     ds, ax
        mov     ax, ds:[bx]
        pop     ds
        test    ax, ax
        jz      short port_notAvail
        ret

port_notAvail:
        call    msg_quit
        db      13,10,'Port not available.',0,1

cmd_line        db 80h dup(0)

_TEXT   ends
        end     SP_Remote





