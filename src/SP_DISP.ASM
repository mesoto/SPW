title.  SoftProbe - Display support

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

SP_DISP EQU 1
include SP_DEFS.inc
include SP_SCRN.inc

LDATA_SEG
; ---------------------------------------------------------------------------
PUBBYTE Display_Buffer <512 dup(0)>
PUBWORD SavedSCREEN <SCREENSIZE dup (0)> ;USER screen image buffer
PUBDWRD watchwin_ptr   <OFFSET32 watch_expressions+1>
PUBDWRD datawin_format <OFFSET32 disp_as_byte>
PUBDWRD datawin_ptr    0
PUBDWRD code_win_end   0

; ---------------------------------------------------------------------------
; DO NOT CHANGE THE ORDER OF THE BLOCK BELOW
; ---------------------------------------------------------------------------
Screen_Functions         label dword
PUBDWRD Input_Proc       <OFFSET32 Return1>     ; +00
PUBDWRD Output_Proc      <OFFSET32 Return1>     ; +04
PUBDWRD Cursor_Proc      <OFFSET32 Return1>     ; +08
PUBDWRD SPW_Screen_Proc  <OFFSET32 Return1>     ; +0C
PUBDWRD Usr_Screen_Proc  <OFFSET32 Return1>     ; +10
PUBBYTE ScreenColors     <17h, 1fh, 74h, 13h>   ; +14 Color Attributes
;;;;;;; ScreenColors     <07h, 0fh, 70h, 07h>   ; +14 Mono Attributes

; ---------------------------------------------------------------------------
PUBDWRD ScreenBase      <OFFSET32 SavedSCREEN>
PUBDWRD win_1stLine     0
PUBDWRD win_lastLine    24*160
PUBBYTE ScreenFlags     <SF_OUTP+SF_CODE+SF_DATA+SF_REGS>
PUBBYTE Window_Rows here
        db 4            ; _RGSTWIN_
        db 4            ; _DATAWIN_
        db 9            ; _CODEWIN_
        db 4            ; _VIEWWIN_

PUBBYTE Window_Line here
        db 0            ; _RGSTWIN_
        db 4            ; _DATAWIN_
        db 9            ; _CODEWIN_
        db 19           ; _VIEWWIN_
        db 24           ; _CMDLINE_
        db 1            ; _TOPLINE_
PUBBYTE CurrentRow  0   ; _CURLINE_

PUBBYTE watchwin_num, 0
PUBBYTE datawin_height, 4

LineCount       db 1
EIP_In_Middle   db 0

LDATA_ENDS

; ---------------------------------------------------------------------------
SCODE_SEG       ; Safe code area (No Pushes inside calls)
; ---------------------------------------------------------------------------

PUBPROC ConvertUserString
; In:   ax:esi = string
;       [esp+PARAM1] = max length
;       [esp+PARAM2] = address of filter function
; Out:  cf=1 if error
        mov     ds, ax
cnv_str1:
        lodsb
        cmp     al, 20h
        jb      short cnv_str2
        call    [esp+PARAM2]            ; call the filter function
cnv_str4:
        dec     byte ptr [esp+PARAM1]
        jnz     short cnv_str1
cnv_str5:
        ret
cnv_str2:
        cmp     al, 0                   ; end of string?
        je      short cnv_str5
        cmp     al, 0ah                 ; LF?
        if d_lf ne 0ah
        .err
        endif
        je      short cnv_str3
        cmp     al, 09h                 ; TAB?
        if d_tab ne 09h
        .err
        endif
        je      short cnv_str3
        cmp     al, 07h                 ; Beep?
        je      short cnv_str6
        cmp     al, 0dh                 ; CR?
        jne     short cnv_str4
        cmp     byte ptr [esi], 0ah     ; LF?
        je      short cnv_str1
        mov     al, d_col
        stosb
        mov     al, 0
cnv_str3:
        stosb
        jmp     short cnv_str4

cnv_str6:
        call    Local_Beep
        jmp     cnv_str1

; In:   ax = data selector
;       esi = offset
;       ecx = length
PUBPROC Display_lStr
        mov     ds, ax
dsp_lstr1:
        lodsb
        cmp     al, 20h
        jb      short dsp_lstr2
        stosb
        loop    short dsp_lstr1
dsp_lstr2:
        ret

PUBPROC Display_ModName
        mov     ecx, 8                  ; max size
dsp_name1:
        lodsb
        cmp     al, 21h
        jb      short dsp_name2
        cmp     al, '.'
        je      short dsp_name2
        stosb
        loop    short dsp_name1
dsp_name2:
        ret

PUBPROC Display_Text
dsp_text1:
        mov     al, [ebx]
        inc     ebx
        cmp     al, 20h
        jb      short dsp_text2
        stosb
        loop    short dsp_text1
dsp_text2:
        ret

SCODE_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------

dsp_cmdTable label dword
        dd OFFSET32 @@d_el     ;00
        dd OFFSET32 @@d_norm   ;01
        dd OFFSET32 @@d_bold   ;02
        dd OFFSET32 @@d_rvrs   ;03
        dd OFFSET32 @@d_fram   ;04
        dd OFFSET32 @@d_wtop   ;05 1st scrollable line
        dd OFFSET32 @@d_col    ;06 go column x
        dd OFFSET32 @@d_row    ;07 go row x, col 0
        dd OFFSET32 @@d_dup    ;08
        dd OFFSET32 @@d_tab    ;09 n spaces
        dd OFFSET32 @@d_lf     ;0a scroll output window
        dd OFFSET32 @@d_spc    ;0b n spaces
        dd OFFSET32 @@d_sub    ;0c
        dd OFFSET32 @@d_clreol ;0d
        dd OFFSET32 @@d_chr    ;0e char on the stack
        dd OFFSET32 @@d_bits   ;0f
        dd OFFSET32 @@d_table  ;10
        dd OFFSET32 @@d_jsr    ;11 call a function
        dd OFFSET32 @@d_skpz   ;12 skip next if *sp++ = 0
        dd OFFSET32 @@d_text   ;13 at ds:ebx (text only)
        dd OFFSET32 @@d_fname  ;14 pushed offset, max 8 bytes (text, no '.')
        dd OFFSET32 @@d_el
        dd OFFSET32 @@d_r16    ;16 word at [ebp].xxx
        dd OFFSET32 @@d_r32    ;17 dword at [ebp].xxx
        dd OFFSET32 @@d_h04    ;18
        dd OFFSET32 @@d_h08    ;19 dword on stack top
        dd OFFSET32 @@d_h16    ;1a dword on stack top
        dd OFFSET32 @@d_h32    ;1b dword on stack top
        dd OFFSET32 @@d_h48    ;1c 2 dwords on stack top
        dd OFFSET32 @@d_deci   ;1d
        dd OFFSET32 @@d_mem    ;1e from ds:ebx, check limit (edx)
        dd OFFSET32 @@d_ret    ;1f Return without display

watchtype_fmt label dword
        dd OFFSET32 watch_bytes
        dd OFFSET32 watch_words
        dd OFFSET32 watch_dwords
        dd OFFSET32 watch_ascii

PUBPROC PrintfMainScr
        DBGBRK  5
        mov     al, SF_OUTP
        call    Refresh_Screen
PUBPROC Printf
        DBGBRK  5
        mov     edi, OFFSET32 Display_Buffer
PUBPROC PrintfAt
        pop     esi
        jmp     short message

@@d_text:
        mov     cl, 7fh                 ; remove t_fill
        and     cl, ds:[esi]
        ; ds:ebx = text string
        call    Display_Text
        lodsb
        and     al, t_fill
        jz      short message
        jecxz   short message
        mov     al, s_spc
        stosb
        mov     al, cl
        stosb
        jmp     short message

PUBPROC Win_Printf
        DBGBRK  5
        mov     ScreenFlags, SF_VWIN
        mov     CurrentRow, 0
        mov     al, s_window
        mov     edi, OFFSET32 Display_Buffer
        pop     esi
        stosb
        mov     al, Window_Line[_CMDLINE_]
@@d_wtop:
        stosb
        mov     al, CurrentRow
        mov     Window_Line[_TOPLINE_], al
        jmp     short message

@@d_chr:pop     eax
        cmp     al, 20h
        jae     short @f
        mov     byte ptr [edi], s_chr
        inc     edi
@@:     stosb
        jmp     short message

@@d_lf: mov     cl, CurrentRow
        inc     ecx
        mov     ch, Window_Line[_CMDLINE_]
        cmp     cl, ch
        jb      short @f
        mov     cl, ch
        dec     ecx
@@:     mov     CurrentRow, cl
@@d_clreol:
@@d_norm:
@@d_bold:
@@d_rvrs:
@@d_fram:
@@d_tab:
dsp_put:stosb
message:lodsb
        test    al, not 1fh
        jnz     dsp_put
        ; cf=0
        movzx   ecx, al
        jmp     dsp_cmdTable[ecx*4]

@@d_ret:mov     [edi], ch
        jmp     esi

@@d_jsr:movsx   eax, word ptr [esi]
        inc     esi
        inc     esi
        add     eax, esi
        call    eax
        jmp     short message

@@d_el: push    esi
PUBPROC Display_Line
        ; edi = end of Display_Buffer
        mov     byte ptr [edi], 0               ; make sure line ends here
        mov     esi, OFFSET32 Display_Buffer
        jmp     Output_Proc

@@d_sub:xchg    esi, edx
        jmp     short message

@@d_skpz:
        pop     ecx
        inc     esi
        jecxz   short message
        dec     esi
        jmp     short message

@@d_fname:
        xchg    esi, [esp]              ; esi=linear address
        call    Display_ModName
        pop     esi
        jmp     message

@@d_table:
        lods    dword ptr ds:[esi]      ;offset
        xchg    esi, eax
        xchg    eax, [esp]              ;index
        and     eax, 7fh                ;max 128 entries
        mov     cl, ds:[esi]            ;table width
        inc     esi
        mul     cl
        add     esi, eax
        rep     movsb
        pop     esi
        jmp     message

@@d_row:stosb
        lodsb
        cmp     al, 80h                 ; 80-ff formatted decimal number
        jae     short dsp_numb
        ; 00-3f = actual row#
        cmp     al, POS_CURLIN_BASE     ; 40
        jb      short new_row
        ; 40-5f = relative to currect row
        cmp     al, POS_WINDOW          ; 60
        jb      short rel_row
        ; 60-7f = different window components
        mov     cl, al
        mov     al, Window_Line[ecx-POS_WINDOW]
new_row:stosb
        mov     CurrentRow, al
        jmp     message

rel_row:sub     al, POS_CURLINE         ;-16...+15
        add     al, CurrentRow
        jmp     short new_row

dsp_numb:
        ; [1SCCLLLL]
        ; CC=00 left-justified, variable length  [-]nnnn
        ; CC=01 left-justified, fixed length     [-]nnnnnn
        ; CC=10 right-justified, blank fill      ....[-]nn
        ; CC=11 right-justified, 0 fill          [-]0000nn
        ; S=Signed
        ; LLLL=max length (1..16)
        DBGBRK  3
        dec     edi                     ;undo d_numb
        pop     ecx                     ;the number
        push    edx
        test    al, 40h                 ;signed?
        jz      short dn_val2
        mov     al, '+'
        test    ecx, ecx                ;negative?
        jns     short dn_val1
        neg     ecx
        mov     al, '-'
dn_val1:stosb
dn_val2:xchg    eax, ecx
        push    edi
        call    Convert_Decimal
        pop     edx                     ;EDI at start
        mov     al, [esi-1]
        test    al, 30h
        jz      short lj_num2           ;left-aligned, variable
        mov     cl, 0fh
        and     cl, al
        inc     ecx                     ;max size
        add     ecx, edx
        test    al, 20h
        jnz     short rj_num1
        ; left-aligned, fixed length
        sub     ecx, edi
        jbe     short lj_num1
        mov     al, 20h
        rep     stosb
lj_num1:add     edi, ecx
lj_num2:pop     edx
        jmp     message

rj_num1:push    ecx
        sub     ecx, edi
        jbe     short rj_num3
        test    al, 10h                 ;zero-fill?
        jz      short rj_num2
        cmp     byte ptr [edx], '-'
        jne     short rj_num2
        inc     edx
rj_num2:dec     edi
        mov     ah, [edi]
        mov     [edi+ecx], ah
        cmp     edx, edi
        jb      short rj_num2
        and     al, 30h
        rep     stosb
rj_num3:pop     edi
        pop     edx
        jmp     message

@@d_deci:
        pop     eax
        push    edx
        call    Convert_Decimal
        pop     edx
        jmp     message

@@d_dup:stosb
        lodsb
@@d_spc:
@@d_col:stosb
        movsb
        jmp     message

@@d_r16:mov     cl, [esi]
        inc     esi
        mov     eax, [ebp+ecx]
        call    hex_16
        jmp     message

@@d_r32:mov     cl, [esi]
        inc     esi
        mov     eax, [ebp+ecx]
        call    hex_32
        jmp     message

@@d_h04:pop     eax
        call    hex_04
        jmp     message

@@d_h08:pop     eax
        call    hex_08
        jmp     message

@@d_h16:pop     eax
        call    hex_16
        jmp     message

@@d_h48:pop     eax
        call    hex_16
        mov     al, ':'
        test    eax, eax                ;segment or selector
        jns     short @f
        mov     al, '!'
@@:     stosb
@@d_h32:pop     eax
        call    hex_32
        jmp     message

@@d_mem:lodsb                           ;[ttllllll]
                                        ;tt=00:ascii 01:byte 10:word 11:dword
                                        ;llllll=number of times-1
        mov     cl, 3fh
        and     cl, al                  ;number of times to repeat
        inc     ecx

        shl     al, 1
        jc      short dsp_wrd_dwrd
        js      short dsp_mm081
dsp_asci1:
        call    read_byte_ltd
        jc      short dsp_asci2
        cmp     al, 20h
        jge     short dsp_asci3
dsp_asci2:
        mov     al, '.'
dsp_asci3:
        stosb
        loop    dsp_asci1
        jmp     message

dsp_mm080:
        mov     al, ' '
        stosb
dsp_mm081:
        call    read_byte_ltd                 ; edx=limit
        jnc     short dsp_mm082
        mov     al,'?'
        stosb
        stosb
        loop    dsp_mm080
        jmp     message
dsp_mm082:
        call    hex_08
dsp_mm083:
        loop    dsp_mm080
        jmp     message

dsp_wrd_dwrd:
        js      short dsp_mm321
        jmp     short dsp_mm161

dsp_mm160:
        mov     al, ' '
        stosb
        stosb
dsp_mm161:
        call    read_word_ltd
        jc      short dsp_mm163
        call    hex_16
dsp_mm162:
        loop    dsp_mm160
        jmp     message
dsp_mm163:
        mov     eax, '????'
        stosd
        jmp     dsp_mm162

dsp_mm320:
        mov     al, ' '
        stosb
        stosb
dsp_mm321:
        call    read_dword_ltd
        jc      short dsp_mm323
        call    hex_32
dsp_mm322:
        loop    dsp_mm320
        jmp     message
dsp_mm323:
        mov     eax, '????'
        stosd
        stosd
        jmp     short dsp_mm322

@@d_bits:
        xchg    edx, [esp+4]            ; edx=value
        xchg    ebx, [esp]
        lods    dword ptr ds:[esi]      ; eax=mask
        mov     cl, ds:[esi]            ; ecx=width (chars/case)
        inc     esi
dsp_bit1:
        shl     eax, 1
        jc      short dsp_bit2
        jz      short dsp_bit6
        shl     ebx, 1
        shl     edx, 1
        jmp     short dsp_bit1
dsp_bit2:
        test    ebx, ebx
        jns     short dsp_bit3
        mov     byte ptr [edi], a_b
        inc     edi
dsp_bit3:
        push    ecx
        shl     edx, 1
        jnc     short dsp_bit4
        add     esi, ecx
        rep     movsb
        pop     ecx
        shl     ebx, 1
        jnc     short dsp_bit1
        mov     byte ptr [edi], a_n
        inc     edi
        jmp     short dsp_bit1
dsp_bit4:
        rep     movsb
        pop     ecx
        add     esi, ecx
        shl     ebx, 1
        jnc     short dsp_bit1
        mov     byte ptr [edi], a_n
        inc     edi
        jmp     short dsp_bit1
dsp_bit6:
        pop     ebx
        pop     edx
        jmp     message

dspLineStruc    struc
  sl_callBack   dd  ?
  sl_index      dd  ?
  sl_limit      dd  ?
  sl_context    dd  ?           ; optional
dspLineStruc    ends

PUBPROC scrollLinesNoLog
        and     Log_Falgs, not LF_LOGCMD
PUBPROC scrollLines
        DBGBRK  5
        pop     edx
        call    Win_Printf
        db      d_sub,d_lf,a_f,d_dup,80,'-',d_wtop,d_el
        ; edx = callBack address
        push    edx                     ; sl_callBack
        call    Log_DisplayBuffer
scrollLine1:
        ; draw whole window
        mov     edx, [esp].sl_index
        call    Printf
        db      d_row, POS_WINDOW + _TOPLINE_
        db      d_el
        mov     bl, Window_Line[_TOPLINE_]
        inc     ebx
scrollLine2:
        call    Printf
        db      d_lf,d_el
        cmp     edx, [esp].sl_limit
        jae     short scrollLine3
        mov     esi, [esp].sl_context
        push    ebx
        push    edx
        mov     ecx, edx
        ; esi = context
        ; edx = ecx = index
        mov     edi, OFFSET32 Display_Buffer
        call    [esp+8].sl_callBack
        ; edi = end of Display_Buffer
        call    Display_Line
        call    Log_DisplayBuffer
        pop     edx
        pop     ebx
        inc     edx
scrollLine3:
        inc     ebx
        cmp     bl, Window_Line[_CMDLINE_]
        jb      short scrollLine2
        cmp     edx, [esp].sl_limit
        jb      short scrollLine4
        cmp     [esp].sl_index, 0
        je      short sl_Exit
        test    Log_Falgs, LF_LOGCMD OR LF_PRINT ; LOG|PRINT <cmd>?
        jnz     short sl_Exit
scrollLine4:
        test    Log_Falgs, LF_LOGCMD OR LF_PRINT ; LOG|PRINT <cmd>?
        jz      scrollLine5
        mov     [esp].sl_index, edx
        if      LF_PRINT - 80h
        .err
        endif
        js      short sl_printing
        call    Printf
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,' LOGGING: Press a key to continue or ESC to cancel.'
        db      d_clreol,d_el
        call    key_read
        cmp     al, K_ESC
        jne     scrollLine1
sl_Exit:jmp     Main_Menu
sl_printing:
        call    Printf
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,' PRINTING: Press a key to continue or ESC to cancel.'
        db      d_clreol,d_el
        jmp     scrollLine1

scrollLine5:
        call    Printf
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,' Use key pad to scroll, or other keys to cancel.'
        db      d_clreol,d_el
scrollKey:
        call    key_read
        movzx   ecx, Window_Line[_CMDLINE_]
        sub     cl, Window_Line[_TOPLINE_]
        dec     ecx                             ;#scrollable lines
        mov     edx, [esp].sl_index
        lea     edi, [edx+ecx]

        cmp     ax, K_PGUP
        je      short scrollPgUp
        cmp     ax, K_PGDN
        je      short scrollPgDn
        cmp     ax, K_HOME
        je      short scrollHome
        cmp     ax, K_END
        je      short scrollEnd
        cmp     ax, K_UP
        je      short scrollUp
        cmp     ax, K_DOWN
        je      short scrollDown
        call    Force_Key
        jmp     Main_Menu

scrollPgDn:
        cmp     edi, [esp].sl_limit
        jae     scrollKey
scrollPnew:
        mov     [esp].sl_index, edi
        jmp     scrollLine1
scrollPgUp:
        sub     [esp].sl_index, ecx
        jnc     scrollLine1
        add     [esp].sl_index, ecx
scrollHome:
        xor     ecx, ecx
        xchg    ecx, [esp].sl_index
        jecxz   scrollKey
        jmp     scrollLine1
scrollEnd:
        mov     edi, [esp].sl_limit
        sub     edi, ecx
;;      jc      scrollKey                       ; should not happen
        cmp     edx, edi
        jne     scrollPnew
        jmp     scrollKey
scrollUp:
        cmp     edx, 1
        jb      scrollKey
        dec     [esp].sl_index
        jmp     scrollLine1
scrollDown:
        cmp     edi, [esp].sl_limit
        jae     scrollKey
        inc     [esp].sl_index
        mov     edx, edi
        call    Printf
        db      d_lf,d_el
        mov     esi, [esp].sl_context
        mov     ecx, edx
        ; esi = context
        ; edx = ecx = index
        mov     edi, OFFSET32 Display_Buffer
        call    [esp].sl_callBack
        ; edi = end of Display_Buffer
        call    Display_Line
        call    Log_DisplayBuffer
        jmp     scrollKey

PUBPROC set_Screen
        call    Skip_Equal
        DBGBRK  3
        call    Parse_Line
        FullCmd 'MONO'   JUMP_ADDRS, <OFFSET32 screen_mono>
        FullCmd 'VGA'    JUMP_ADDRS, <OFFSET32 screen_vga>
        PartCmd 'LPT'    SCAN_VAL32, <OFFSET32 screen_para>
        PartCmd 'COM'    SCAN_VAL32, <OFFSET32 screen_comx>
        db 0
        reportError 'Invalid SCR Type.'

screen_vga:
        DBGBRK  3
        push    esi
        call    SVGA_Init
        jc      short get_Scr_Colors
        reportError 'Error Initilizing VGA Screen.'

screen_mono:
        DBGBRK  3
        push    esi
        call    Mono_Init
        jc      short get_Scr_Colors
        reportError 'Secondary mono display not found!.'

get_Scr_Colors:
        DBGBRK  3
        pop     esi
        mov     ecx, 4
        mov     edi, OFFSET32 ScreenColors
@@:     call    Scan_Hex
        jc      short @f
        xchg    eax, ebx
        stosb
        loop    @b
@@:     call    SPW_Screen
        jmp     Display_AllWindows

screen_para:
        ; ebx=LPT port number
        ; esi=ptr optional attributes
        dec     ebx
        cmp     ebx, 3
        jae     short port_notAvail
        movzx   ecx, word ptr 408h[ebx+ebx]
        jecxz   short port_notAvail
        mov     DosInfo.ParaPort, cx

        push    esi

        call    Para_Init
Chk_Connect:
        jc      Display_AllWindows
        reportError 'Connection Failed.'

port_notAvail:
        reportError 'Port Not Available'

screen_comx:
        DBGBRK  4
        ; ebx=COM port number
        ; esi=ptr optional attributes
        dec     ebx
        cmp     ebx, 4
        jae     short port_notAvail
        movzx   ecx, word ptr 400h[ebx+ebx]
        jecxz   short port_notAvail
        mov     DosInfo.SerialPort, cx

        call    Skip_Blanks
        cmp     al, ':'
        jne     short @f
        inc     si
        call    Scan_Decimal
        jc      short baudRate_error
        dec     ebx
        mov     eax, 115200
        cmp     ebx, eax
        jae     short baudRate_error    ;max is 1 (115200=1c200h)
        inc     ebx
        xor     edx, edx
        div     ebx
        test    eax, eax
        jz      short baudRate_error
        test    edx, edx
        jnz     short baudRate_error

        mov     DosInfo.SerialDivisor, ax
@@:
        DBGBRK  4
        call    Serial_Init
        jmp     Chk_Connect

baudRate_error:
        reportError 'Baud Rate Error'

PUBPROC InitScreen
        DBGBRK  3
        cmp     DosInfo.ScreenType, SCR_SERIAL
        je      Serial_Init
        cmp     DosInfo.ScreenType, SCR_PARA
        je      Para_Init
        cmp     DosInfo.ScreenType, SCR_MONO
        je      Mono_Init
        jmp     SVGA_Init

PUBPROC Select_ScreenMem
        DBGBRK  3
        add     eax, Physical_Bias
        ; eax=linear address for video ram

        ; modify ScreenBase after restoring user screen.
        push    eax

        ; Restore current screen before switching to a different type
        call    Usr_Screen_NP           ; Restore user screen

        pop     eax
        mov     ScreenBase, eax
        mov     win_1stLine, eax
        add     eax, 24*160
        mov     win_lastLine, eax

PUBPROC Select_Screen
        pop     esi
        lodsb
        mov     DosInfo.ScreenType, al
        mov     edi, OFFSET32 Screen_Functions
        movsd                           ; Input_Proc
        movsd                           ; Output_Proc
        movsd                           ; Cursor_Proc
        movsd                           ; SPW_Screen_Proc
        movsd                           ; Usr_Screen_Proc
        movsd                           ; ScreenColors
        stc                             ; success
        push    esi

Return1:ret

PUBPROC Usr_Screen
        test    DosInfo.ScreenType, SCR_ALWAYS  ; is it always ON?
        jz      short Usr_Screen_NP

        call    Printf
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,' SoftProbe/W V',VER_STR,' (C) 1995  Mehdi Sotoodeh. '
        db      'All rights reserved.  [NOT ACTIVE]',d_clreol,d_el
PUBPROC Usr_Screen_NP
        btr     dword ptr SP_flags, SP_PROBESCR_BIT
        jnc     short Return1
        jmp     Usr_Screen_Proc

PUBPROC SPW_Screen
        bts     dword ptr SP_flags, SP_PROBESCR_BIT
        jc      short Return1
        jmp     SPW_Screen_Proc

PUBPROC CheckAbortConnection
        call    Local_Keyboard
        cmp     al, 1                   ; K_ESC
        jne     short Return2
        ; force screen update
        DBGBRK  3
        mov     ScreenFlags, SF_OUTP+SF_CODE+SF_DATA+SF_REGS
        cmp     DosInfo.ScreenType, SCR_MONO
        je      short @f
        mov     DosInfo.ScreenType, SCR_SVGA
@@:     call    InitScreen
        call    SPW_Screen
        reportError 'Connection Aborted.'
Return2:ret

watch_not_present:
        db      'Invalid Address',d_sub
        db      d_sub
        db      d_sub

watch_bytes:
        db      d_mem,DM_BYTE+8,d_sub
        db      d_mem,DM_BYTE+8,d_sub
        db      d_mem,DM_BYTE+8,d_sub

watch_words:
        db      d_mem,DM_WORD+4,d_sub
        db      d_mem,DM_WORD+4,d_sub
        db      d_mem,DM_WORD+4,d_sub

watch_dwords:
        db      a_b,'+00  ',a_n,d_mem,DM_DWRD+2,d_sub
        db      a_b,'+08  ',a_n,d_mem,DM_DWRD+2,d_sub
        db      a_b,'+10  ',a_n,d_mem,DM_DWRD+2,d_sub

watch_ascii:
        db      d_mem,DM_ASCI+24,d_sub
        db      d_mem,DM_ASCI+24,d_sub
        db      d_mem,DM_ASCI+24,d_sub

Skip_If_Line2:
        cmp     byte ptr [ebx], ch
        je      short sl2_skp
        dec     LineCount
        jnz     short sl2_ret
sl2_skp:add     esi, 3                  ; skip 'd_lf,d_text,t_fill+80'
sl2_ret:ret

;EAX=00000000  SS=0000  ESP=00000000  EBP=00000000   [0]SS:ESP+48................
;EBX=00000000  CS=0000  EIP=00000000  EFLAGS=00000000 ³ 00 00 00 00 00 00 00 00
;ECX=00000000  DS=0000  ESI=00000000  O D I S Z A P C ³ 0000  0000  0000  0000
;EDX=00000000  ES=0000  EDI=00000000  FS=0000 GS=0000 ³ +00 00000000  00000000

;EAX=00000000  EBP=00000000  CS=0000  EIP=00000000   [0]SS:ESP+48................
;EBX=00000000  ESP=00000000  SS=0000  EFLAGS=00000000 ³ 00 00 00 00 00 00 00 00
;ECX=00000000  ESI=00000000  DS=0000  O D I S Z A P C ³ 0000  0000  0000  0000
;EDX=00000000  EDI=00000000  ES=0000  FS=0000 GS=0000 ³ 00000000 00000000

RegValueColor   macro x, y
        mov     eax, [ebp].&x
  ifnb  <y>
        push    eax
  endif
        xor     eax, [esi].&x
        push    eax
        endm

PUBPROC Display_RegWindow

        DBGBRK  3
        mov     ebx, watchwin_ptr
        push    dword ptr watchwin_num
        mov     esi, OFFSET32 PrevRegs
        RegValueColor R_EIP
        RegValueColor R_CS
        RegValueColor R_EBP
        RegValueColor R_EAX
        call    Printf
        db      d_row,0
        db      'EAX=',d_skpz,a_b,d_r32,R_EAX,a_n,'  '
        db      'EBP=',d_skpz,a_b,d_r32,R_EBP,a_n,'  '
        db       'CS=',d_skpz,a_b,d_r16,R_CS ,a_n,'  '
        db      'EIP=',d_skpz,a_b,d_r32,R_EIP,a_n,'   '
        db      a_f,'[',d_h04,']',a_b,d_text,t_fill+25,d_el

        DBGBRK  3
        mov     esi, watchwin_ptr
        movzx   eax, byte ptr [esi-1]   ;.watchwinType
        push    watchtype_fmt[4*eax]
        call    Scan_AddressDS
        cmc
        sbb     eax, eax
        and     eax, edx
        jns     short dispW1
        movzx   ebx, bx
dispW1: mov     Code_Data_Ptrs[PNTR_WATCH][0], ebx
        mov     Code_Data_Ptrs[PNTR_WATCH][4], eax
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        pop     edx                     ;watchtype_fmt
        ; EBX = address of the watch
        ; EDX = display format
        jnc     short dispW2
        mov     edx, OFFSET32 watch_not_present
dispW2: mov     esi, OFFSET32 PrevRegs
        RegValueColor R_EFLAGS
        RegValueColor R_SS
        RegValueColor R_ESP
        RegValueColor R_EBX
        call    Printf
        db      d_lf
        db      'EBX=',d_skpz,a_b,d_r32,R_EBX,a_n,'  '
        db      'ESP=',d_skpz,a_b,d_r32,R_ESP,a_n,'  '
        db       'SS=',d_skpz,a_b,d_r16,R_SS ,a_n,'  '
        db      'EFLAGS=',d_skpz,a_b,d_r32,R_EFLAGS,a_n,' '
        db      a_f,'³',a_n,' ',d_sub,d_el

        DBGBRK  3
        mov     esi, OFFSET32 PrevRegs
        RegValueColor R_EFLAGS, PushVal ;_bits (flags)
        RegValueColor R_DS
        RegValueColor R_ESI
        RegValueColor R_ECX
        call    Printf
        db      d_lf
        db      'ECX=',d_skpz,a_b,d_r32,R_ECX,a_n,'  '
        db      'ESI=',d_skpz,a_b,d_r32,R_ESI,a_n,'  '
        db       'DS=',d_skpz,a_b,d_r16,R_DS ,a_n,'  '
               ;10fedcba9876543210
               ;VR.N..ODITSZ.A.P.C
        _bits   000000111011010101b,2,'o O d D i I + - z Z a A p P c C '
        db      a_f,'³',a_n,' ',d_sub,d_el

        push    Code_Data_Ptrs[PNTR_WATCH][0]
        push    Code_Data_Ptrs[PNTR_WATCH][4]
        mov     esi, OFFSET32 PrevRegs
        RegValueColor R_GS
        RegValueColor R_FS
        RegValueColor R_ES
        RegValueColor R_EDI
        RegValueColor R_EDX
        call    Printf
        db      d_lf
        db      'EDX=',d_skpz,a_b,d_r32,R_EDX,a_n,'  '
        db      'EDI=',d_skpz,a_b,d_r32,R_EDI,a_n,'  '
        db       'ES=',d_skpz,a_b,d_r16,R_ES ,a_n,'  '
        db       'FS=',d_skpz,a_b,d_r16,R_FS ,a_n,' '
        db       'GS=',d_skpz,a_b,d_r16,R_GS ,a_n,' '
        db      a_f,'³',a_n,' ',d_sub
        db      d_row, POS_WINDOW + _DATAWIN_
        db      d_col,55,a_b,d_h48,a_f,d_dup,12,'Í'
        db      d_el
        ret

selector_Types label byte   ; 8 bytes/case
        db  '<Type-0>'      ; xxx00000 reserved
        db  '286TSS'   ,0,0 ; PLL00001 available 286 TSS segment
        db  'LDT';0,0,0,0,0 ; PLL00010 LDT segment
PUBBYTE Zeros   <0,0,0,0,0>
        db  '286TSS'   ,0,0 ; PLL00011 busy 286 TSS segment
        db  '286CallG'      ; PLL00100 286 call gate
        db  '286TaskG'      ; PLL00101 286 task gate
        db  '286TrapG'      ; PLL00110 386 trap gate
        db  '286IntG'    ,0 ; PLL00111 286 interrupt gate
        db  '<Type-8>'      ; xxx01000 reserved
        db  '386TSS'   ,0,0 ; PLL01001 available 386 TSS segment
        db  '<Type-A>'      ; xxx01010 reserved
        db  '386TSS'   ,0,0 ; PLL01011 busy 386 TSS segment
        db  '386CallG'      ; PLL01100 386 call gate
        db  '<Type-D>'      ; xxx01101 reserved
        db  '386TrapG'      ; PLL01110 386 trap gate
        db  '386IntG'    ,0 ; PLL01111 386 interrupt gate
                            ; PLL10EWA data segment
                            ; PLL11CRA code segment
        db  'Data,RO'    ,0 ; PLL10e0a data, Read-Only
        db  'Code,XO'    ,0 ; PLL11c0a code, Exec-Only
        db  'Data,RW'    ,0 ; PLL10e1a data, R/W
        db  'Code,XR'    ,0 ; PLL11c1a code, X/R

        db  'Invalid'    ,0 ; 14h - Invalid
        db  '<NP>' ,0;0,0,0 ; 15h - Not present selector

datadisp_v86:
        push    ebx
        push    edi
        ;ax:bx=seg+off
        call    V86_Owner
        pop     edi
        pop     ebx
        push    esi
        call    PrintfAt
        db      d_fname,d_col,37,'<V86>',d_el

;       mov     ebx, Code_Data_Ptrs[PNTR_DATA]
        mov     eax, Code_Data_Ptrs[PNTR_DATA][4]
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jmp     short datadisp_lines

PUBPROC Display_DataWindow
        DBGBRK  3
        mov     edx, Code_Data_Ptrs[PNTR_DATA][4]
        push    edx                     ;for d_h16
        call    Printf
        db      d_row, POS_WINDOW + _DATAWIN_
        db      a_f,d_dup,53,'ÍÏÍ',d_col,0,a_b,d_h16,':',d_ret

        mov     ebx, Code_Data_Ptrs[PNTR_DATA]
        mov     datawin_ptr, ebx
        test    edx, edx
        js      short datadisp_v86

        ; edx:ebx=address
        call    SectionNameFromAddress

        mov     ebx, Code_Data_Ptrs[PNTR_DATA]
        mov     eax, Code_Data_Ptrs[PNTR_DATA][4]
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      short datadisp_2

        ; esi = access rights
        xchg    eax, esi
        test    al, 80h                 ;present?
        jz      short datadisp_3        ;nope
        test    al, 10h                 ;DATA/CODE
        jz      short datadisp_1
        and     al, 1ah
        btr     eax, 3                  ;C=1 if CODE
        adc     al, 0                   ;12/13
datadisp_1:
        push    ebx
        and     eax, 1fh
        lea     ebx, selector_Types[eax*8]
        call    PrintfAt
        db      d_col,37,d_text,8,d_el
        pop     ebx
datadisp_lines:
        movzx   ecx, datawin_height     ;No. of lines
datadisp_loop:
        push    ecx
        mov     edx, datawin_format
        push    datawin_ptr
        mov     cl, [edx]               ; line size
        inc     edx
        add     datawin_ptr, ecx
        call    Printf
        db      d_lf,d_h32,'  ',d_sub,d_el
        pop     ecx
        loop    datadisp_loop
        ret

datadisp_2:
        lar     eax, Code_Data_Ptrs[PNTR_DATA][4]
        mov     al, 14h                 ; <Invalid>
        jnz     short datadisp_1
        test    ah, ah
        js      short datadisp_1
datadisp_3:
        mov     al, 15h                 ; <NP>
        jmp     short datadisp_1

PUBPROC Display_CodeWindow
        DBGBRK  3
        mov     ebx, Code_Data_Ptrs[PNTR_CODE]
        mov     edx, Code_Data_Ptrs[PNTR_CODE][4]
        mov     actual_IP, ebx          ; used by dispins
        test    edx, edx
        js      short codedisp_v86

        push    edx
        call    Printf
        db      d_row, POS_WINDOW + _CODEWIN_
        db      a_f,d_dup,80,'Í'
        db      a_b,d_col,75,'P16',d_col,0,d_h16,':',d_ret

        xchg    eax, edx
        call    Get_Def_SelSize
        and     al, 2
        jz      short @f
        mov     word ptr [edi-9], '23'  ; P16 => P32
@@:     mov     edx, Code_Data_Ptrs[PNTR_CODE][4]
        ; edx:ebx=address
        call    SectionNameFromAddress
        call    PrintfAt
        db      d_el
        jmp     short codedisp_1

codedisp_v86:
        mov     def_segsize, DEFSEG_V86
        xchg    eax, edx
        ;ax:bx=seg+off
        call    V86_Owner
        push    esi
        push    Code_Data_Ptrs[PNTR_CODE][4]
        call    Printf
        db      d_row, POS_WINDOW + _CODEWIN_
        db      a_f,d_dup,80,'Í',a_b,d_col,75,'V86'
        db      d_col,0,d_h16,':',d_fname,d_el
codedisp_1:
        DBGBRK  3
        mov     ebx, currentInst
        mov     eax, [ebp].R_CS         ;to get the oprand size
        call    effAddr
        jc      short codedisp_2
        ; eax:esi = effective address
        mov     Code_Data_Ptrs[PNTR_EFADR], esi
        mov     Code_Data_Ptrs[PNTR_EFADR][4], eax
        push    esi
        push    eax
        mov     ebx, esi
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        call    Printf
        db      a_b,d_col,34,d_h48
        db      d_col,49,d_mem,DM_DWRD+1,d_el
codedisp_2:
        mov     al, Window_Rows[_CODEWIN_]
        mov     LineCount, al
        mov     EIP_In_Middle, 0        ; start with eip displayed
        mov     ebx, Code_Data_Ptrs[PNTR_CODE]
        mov     eax, Code_Data_Ptrs[PNTR_CODE][4]
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
codedisp_3:
        DBGBRK  3

        shr     EIP_In_Middle, 1        ; last time eip displayed?
        jnc     short @f
        mov     eax, currentInst        ; current EIP
        xchg    ebx, eax                ; forced eip
        sub     eax, ebx                ; difference
        sub     actual_IP, eax          ; update the actual offset
@@:     push    ebx
        call    dispins
        mov     edx, ebx                ; save ebx
        pop     ebx
        push    edx                     ; save (next line ebx)

        xor     ecx, ecx
        mov     eax, currentInst
        cmp     eax, ebx
        sete    cl                      ; 1 if same as EIP
        jbe     short @f
        cmp     eax, edx
        rcl     EIP_In_Middle, 1
@@:     push    ecx                     ; for d_skpz (EIP reverse)
        mov     ch, BRKTYPE_I3 OR BRKTYPE_DRX ; OR BRKTYPE_MOD
        call    FindCodeBreak
        mov     ebx, OFFSET32 dissBuffOff
        jnc     short codedisp_5      ; found a break?

        call    Printf
        db      d_lf,d_skpz,a_r,d_text,t_fill+80
        _jsr    Skip_If_Line2
        db      d_lf,d_text,t_fill+80,d_el
codedisp_4:
        pop     ebx                     ; restore ebx
        sub     LineCount, 1
        ja      codedisp_3
        mov     eax, actual_IP          ; used by dispins
        mov     code_win_end, eax
Return3:ret

codedisp_5:
        DBGBRK  5
        pop     eax
        mov     ch, 0
        push    ecx                     ; break# (1..)
        push    eax                     ; for d_skpz (EIP a_r)
        mov     cl, BRK_ACTIVE
        and     cl, [edi].brk_Flags
        push    ecx                     ; for d_skpz (active a_b)
        call    Printf
        db      d_lf,d_skpz,a_b,d_skpz,a_r,d_text,t_fill+80
        _jsr    Skip_If_Line2
        db      d_lf,d_text,t_fill+80
        db      d_col,75,'<',d_deci,'>',d_el
        jmp     codedisp_4

PUBPROC Refresh_Screen
        or      al, ScreenFlags
        test    al, SF_OUTP+SF_CODE+SF_DATA+SF_REGS
        jz      short Return3
        test    al, SF_VWIN + SF_VLOG
        jz      short @f
        mov     al, SF_OUTP+SF_CODE+SF_DATA+SF_REGS
@@:     mov     ScreenFlags, al
        test    al, SF_DATA
        jz      short @f
        call    Display_DataWindow
@@:     test    ScreenFlags, SF_CODE
        jz      short @f
        call    Display_CodeWindow
@@:     test    ScreenFlags, SF_REGS
        jz      short @f
        call    Display_RegWindow
@@:     mov     al, 0
        xchg    al, ScreenFlags
        test    al, SF_OUTP
        jz      short Return4
;       jmp     Display_Output

PUBPROC Display_Output
        DBGBRK  3
        call    Printf
        db      d_row, POS_WINDOW + _VIEWWIN_
        db      a_f,d_dup,80,'Í',d_wtop,d_el
        movzx   ecx, Window_Rows[_VIEWWIN_]
display_outpt1:
        push    ecx
        imul    ebx, ecx, -input_line_size
        add     ebx, OFFSET32 input_buff_beg + input_buff_size
        call    Printf
        db      d_lf,d_text,t_fill+input_line_size,d_el
        pop     ecx
        loop    display_outpt1

        xchg    ecx, errMessage
        jecxz   short @f
        mov     ebx, ecx
        call    Printf
        db      d_lf,a_b,d_text,t_fill+80,d_el
@@:     xor     ecx, ecx
        xchg    ecx, [ebp].R_BrkMsg
        jecxz   short Return4
        cmp     byte ptr [ecx], d_sub
        je      short Return4
        mov     edx, ecx
        mov     ebx, esp
        push    [ebp].R_Fault
        call    Printf
        db      d_lf,'Break Due To ',d_sub,d_el
        mov     esp, ebx
Return4:ret

LCODE_ENDS
END

