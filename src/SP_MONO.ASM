title.  SoftProbe - SP_Mono

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

SP_MONO EQU 1
include SP_DEFS.inc
include SP_SCRN.inc

; ---------------------------------------------------------------------------
LDATA_SEG
; ---------------------------------------------------------------------------
line_start      dd 0
PrevPos         dd 0

LDATA_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------
dsp_cmdTable    dd OFFSET32 @@s_el     ;00
                dd OFFSET32 @@s_norm   ;01 a_n
                dd OFFSET32 @@s_bold   ;02 a_b
                dd OFFSET32 @@s_rvrs   ;03 a_r
                dd OFFSET32 @@s_fram   ;04 a_f
                dd OFFSET32 @@s_wtop   ;05 1st scrollable line
                dd OFFSET32 @@s_col    ;06 go column x (change it to mv2)
                dd OFFSET32 @@s_row    ;07 go row x, col 0
                dd OFFSET32 @@s_dup    ;08
                dd OFFSET32 @@s_tab    ;09
                dd OFFSET32 @@s_lf     ;0a scroll output window
                dd OFFSET32 @@s_spc    ;0b
                dd OFFSET32 @@s_window ;0c open full sized window
                dd OFFSET32 @@s_clreol ;0d
                dd OFFSET32 @@s_chr    ;0e
                dd OFFSET32 @@s_el     ;0f
                dd OFFSET32 @@s_el     ;10
                dd OFFSET32 @@s_el     ;11
                dd OFFSET32 @@s_el     ;12
                dd OFFSET32 @@s_el     ;13
                dd OFFSET32 @@s_el     ;14
                dd OFFSET32 @@s_el     ;15
                dd OFFSET32 @@s_el     ;16
                dd OFFSET32 @@s_el     ;17
                dd OFFSET32 @@s_el     ;18
                dd OFFSET32 @@s_el     ;19
                dd OFFSET32 @@s_el     ;1a
                dd OFFSET32 @@s_el     ;1b s_reconnect
                dd OFFSET32 @@s_el     ;1c
                dd OFFSET32 @@s_el     ;1d
                dd OFFSET32 @@s_el     ;1e s_retkey
                dd OFFSET32 @@s_el     ;1f s_cursor

@@s_row:mov     cl, ds:[esi]
        inc     esi
        mov     edi, ScreenBase
        shl     cl, 1
        jnc     short @f
        mov     edi, line_start
@@:     imul    ecx, 80
        add     edi, ecx
        mov     line_start, edi
        jmp     short @@s_norm

PUBPROC Local_Display
        DBGBRK  5
        xchg    edi, PrevPos
@@s_norm:
        mov     ah, ScreenColors[a_n-a_n]
        jmp     short message

@@s_bold:
@@s_rvrs:
@@s_fram:
        mov     ah, ScreenColors[ecx-a_n]
        jmp     short message

@@s_chr:lodsb
dsp_put:stosw
message:lodsb
        test    al, not 1fh
        jnz     dsp_put
        ; cf=0
        movzx   ecx, al
        jmp     dsp_cmdTable[ecx*4]

@@s_el: xchg    PrevPos, edi            ; save for next call
        ret

@@s_col:mov     edi, line_start
        mov     cl, ds:[esi]
        inc     esi
        lea     edi, [edi+2*ecx]
        jmp     message

@@s_tab:mov     ecx, edi
        shr     ecx, 1
        or      ecx, not 7
        neg     ecx
        mov     al, ' '
        rep     stosw
        jmp     message

@@s_clreol:
        push    eax                     ;save ah
        mov     eax, edi
        sub     eax, ScreenBase
        shr     ax, 1
        mov     cl, 80
IF DBG
        cmp     ah, cl
        jb      short @f
        int     3
        int     3
@@:
ENDIF
        div     cl
        sub     cl, ah
        pop     eax                     ;restore ah
        mov     al, ' '
        rep     stosw
        jmp     message

@@s_window:
        mov     cl, ds:[esi]            ;window height
        inc     esi
        imul    ecx, 80
        mov     edi, ScreenBase
        push    edi
        mov     ah, ScreenColors[a_n-a_n]
        mov     al, ' '
        rep     stosw
        mov     win_lastLine, edi
        pop     edi
@@s_wtop:
        mov     win_1stLine, edi
        mov     line_start, edi
        jmp     message

@@s_lf: mov     edi, line_start
        mov     ecx, win_lastLine
        add     edi, 160
        cmp     edi, ecx
        jb      short clrNewLine
        mov     edi, win_1stLine
        push    esi
        lea     esi, 160[edi]
        sub     ecx, esi
        shr     ecx, 1
        rep     movsw
        pop     esi
clrNewLine:
        mov     ecx, 80
;;      mov     ah, ScreenColors[a_n-a_n]
        mov     al, ' '
        push    edi
        rep     stosw
        pop     edi
        mov     line_start, edi
        jmp     message

@@s_dup:mov     cl, ds:[esi]
        inc     esi
        lods    byte ptr ds:[esi]
        rep     stosw
        jmp     message

@@s_spc:mov     cl, ds:[esi]
        inc     esi
        mov     al, ' '
        rep     stosw
        jmp     message

PUBPROC Mono_Init
        mov     eax, 0b0000h
        call    Select_ScreenMem
        db      SCR_MONO
        dd      OFFSET32 Local_Keyboard
        dd      OFFSET32 Local_Display
        dd      OFFSET32 Mono_Cursor
        dd      OFFSET32 Mono_ProbeScreen
        dd      OFFSET32 Mono_UserScreen
        dd      07700f07h               ; a_f a_r a_b a_n
PUBPROC Mono_ProbeScreen
PUBPROC Mono_UserScreen
        ret

LCODE_ENDS
END

