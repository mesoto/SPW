title.  SoftProbe - SP_Keyb

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

SP_KEYB EQU 1
include SP_DEFS.inc
include VKD.Inc
IFNDEF  _W95_
include VPICD.inc
ENDIF

kbd_data        = 60h
kbd_ctl         = 61h
kbd_Cmd         = 64h
kbd_Status      = 64h                   ; Keyboard status

; Keyboard status
fKBS_PE         equ 10000000b           ; parity error
fKBS_RTO        equ 01000000b           ; timeout on reception from kybd
fKBS_AuxData    equ 00100000b           ; Aux data available (PS/2 mouse)
fKBS_UnLock     equ 00010000b           ; keyboard not locked
fKBS_Cmd        equ 00001000b           ; last output was to pcmd_Kybd
fKBS_Sys        equ 00000100b           ; system flag bit
fKBS_Bsy        equ 00000010b           ; data on command port not read
fKBS_DAV        equ 00000001b           ; data available on data port

MACRO_BUFF_SIZE equ 2048                ; room for key translation

LDATA_SEG
; ---------------------------------------------------------------------------
IFDEF   _W95_
Prev_Keyboard_Filter dd 0
ENDIF

PUBDWRD Cmd_Hint 0
PUBDWRD key_macro_ptr <OFFSET32 macro_buff_end - 1>
macro_buff_str  dd  OFFSET32 macro_buff_end

keyMacro        macro sh, key, a
                db  key, sh
                dw  &a - macro_buff_beg
                endm

macro_buff_beg  label byte
                dw  0
                dw  0
                db  (macro_buff_beg + MACRO_BUFF_SIZE - $) dup (0)
macro_buff_end  label byte
macro_buff_spc  dw  MACRO_BUFF_SIZE - 5 ;space in macro buffer

PUBBYTE input_buff_beg <input_buff_size dup (0)>
PUBBYTE input_buff_end here
PUBBYTE cmd_buffer  <input_line_size dup (0)> ;after input_buff_end
forced_key      dw  0
PUBBYTE KeyShift    0
xtn_scancode    db  0                   ;extended scancode (E0 ..)

IFDEF   _W95_
PUBBYTE HotKey      <20h, K_CTL> ;SPACE
ELSE
PUBBYTE HotKey      <39h, K_CTL> ;scan code for SPACE
ENDIF

LDATA_ENDS

LCODE_SEG
; ---------------------------------------------------------------------------

kbd_code equ this word          ;definition of keys
        db K_ESC,   K_sESC      ;01 ESC
        db '1',     '!'         ;02 1!
        db '2',     '@'         ;03 2@
        db '3',     '#'         ;04 3#
        db '4',     '$'         ;05 4$
        db '5',     '%'         ;06 5%
        db '6',     '^'         ;07 6^
        db '7',     '&'         ;08 7&
        db '8',     '*'         ;09 8*
        db '9',     '('         ;10 9(
        db '0',     ')'         ;11 0)
        db '-',     '_'         ;12 -_
        db '=',     '+'         ;13 =+
        db K_BKSP,  K_sBKSP     ;14 BackSpace
        db K_TAB,   K_sTAB      ;15 Tab
        db 'q',     'Q'         ;16 Q
        db 'w',     'W'         ;17 W
        db 'e',     'E'         ;18 E
        db 'r',     'R'         ;19 R
        db 't',     'T'         ;20 T
        db 'y',     'Y'         ;21 Y
        db 'u',     'U'         ;22 U
        db 'i',     'I'         ;23 I
        db 'o',     'O'         ;24 O
        db 'p',     'P'         ;25 P
        db '[',     '{'         ;26 [{
        db ']',     '}'         ;27 ]}
        db K_CR,    K_sCR       ;28 CR
        db K_CTL,   0           ;29 CTRL
        db 'a',     'A'         ;30 A
        db 's',     'S'         ;31 S
        db 'd',     'D'         ;32 D
        db 'f',     'F'         ;33 F
        db 'g',     'G'         ;34 G
        db 'h',     'H'         ;35 H
        db 'j',     'J'         ;36 J
        db 'k',     'K'         ;37 K
        db 'l',     'L'         ;38 L
        db ';',     ':'         ;39 ;:
        db "'",     '"'         ;40 '"
        db '`',     '~'         ;41 `~
        db K_SHIFT, 0           ;42 LSHIFT
        db '\',     '|'         ;43 \|
        db 'z',     'Z'         ;44 Z
        db 'x',     'X'         ;45 X
        db 'c',     'C'         ;46 C
        db 'v',     'V'         ;47 V
        db 'b',     'B'         ;48 B
        db 'n',     'N'         ;49 N
        db 'm',     'M'         ;50 M
        db ',',     '<'         ;51 ,<
        db '.',     '>'         ;52 .>
        db '/',     '?'         ;53 /?
        db K_SHIFT, 0           ;54 RSHIFT
        db K_PRT,   K_sPRT      ;55 PRINT SCREEN
        db K_ALT,   0           ;56 ALT
        db ' ',     K_sSPACE    ;57 SPACE
        db K_CAP,   0           ;58 CAPS LOCK
        db K_F1,    K_sF1       ;59 F1
        db K_F2,    K_sF2       ;60 F2
        db K_F3,    K_sF3       ;61 F3
        db K_F4,    K_sF4       ;62 F4
        db K_F5,    K_sF5       ;63 F5
        db K_F6,    K_sF6       ;64 F6
        db K_F7,    K_sF7       ;65 F7
        db K_F8,    K_sF8       ;66 F8
        db K_F9,    K_sF9       ;67 F9
        db K_F10,   K_sF10      ;68 F10
        db K_NUML,  0           ;69 NUM LOCK
        db K_SCRL,  0           ;70 SCROLL LOCK
        db K_HOME,  K_sHOME     ;71 HOME
        db K_UP,    K_sUP       ;72 UP
        db K_PGUP,  K_sPGUP     ;73 PGUP
        db K_MINUS, K_sMINUS    ;74 MINUS
        db K_LEFT,  K_sLEFT     ;75 LEFT
        db K_FIVE,  K_sFIVE     ;76 FIVE
        db K_RIGHT, K_sRIGHT    ;77 RIGHT
        db K_PLUS,  K_sPLUS     ;78 PLUS
        db K_END,   K_sEND      ;79 END
        db K_DOWN,  K_sDOWN     ;80 DOWN
        db K_PGDN,  K_sPGDN     ;81 PGDN
        db K_INS,   0           ;82 INS on/off
        db K_DEL,   K_sDEL      ;83 DEL
        db 0,       0           ;84 Sys-Req
        db 0,       0           ;85
        db 0,       0           ;86
        db K_F11,   K_sF11      ;87 F11
        db K_F12,   K_sF12      ;88 F12

max_keys equ ($ - kbd_code)/2

; ---------------------------------------------------------------------------

PUBPROC Local_Keyboard
        in      al, kbd_Status
        test    al, fKBS_DAV            ; Data aviable?
        jz      short ret_nodata

        ; Some data available on the port, acknowledge its receipt.
    ;   push    eax
    ;   in      al, kbd_ctl
    ;   jmp     SHORT $+2
    ;   or      al, 80h
    ;   out     kbd_ctl, al
    ;   jmp     SHORT $+2
    ;   xor     al, 80h
    ;   out     kbd_ctl, al
    ;   pop     eax
        ; Make sure the data is from the keyboard (not something like
        ; PS/2 mouse).
        test    al, fKBS_AuxData        ; Mouse input?
        jz      short ret_kbdata        ; No, ret kb data

        DBGBRK  3
   ;    mov     al, 20h
   ;    out     20h, al                 ; Clear the interrupt request flag
        jmp     SHORT $+2
        in      al, kbd_data            ; clear busy flag
ret_nodata:
        xor     al, al
        ret

ret_kbdata:
        ; Clear the interrupt request flag
        mov     al, 61h
        out     20h, al
        jmp     SHORT $+2

        in      al, kbd_data            ; also clear busy flag
        test    al, al
        ret

; ---------------------------------------------------------------------------
;        mov     ah, 0ADh               ; Disable keyboard command
;        call    KBD_SendCmd
;        mov     ch, 40h
;FlushKb1:
;        in      al, kbd_Status
;        test    al, fKBS_DAV           ; Data available?
;        jz      short FlushKb2
;        in      al, kbd_data
;FlushKb2:
;        loop    FlushKb1
;        ret
;
;        mov     ah, 0AEh               ; Enable keyboard command
;        jmp     short KBD_SendCmd
;
;PUBPROC Cmd_Reset
;        mov     ah, 0feh               ; reset_processor
;
;KBD_SendCmd:
;        xor     ecx, ecx
;        mov     ch, 10h
;@@:     in      al, kbd_Status
;        test    al, fKBS_Bsy           ; Busy?
;        loopnz  @b
;        xchg    al, ah
;        out     kbd_Cmd, al
;        ret

PUBPROC Cmd_Reset
        mov     al, 0feh                ; reset_processor
        out     kbd_Cmd, al
        ret

; ---------------------------------------------------------------------------
PUBPROC Force_Key
        mov     forced_key, ax
keycheck1:
        ret

PUBPROC key_check
        xor     eax, eax
        xchg    ax, forced_key
        test    al, al
        jnz     short keycheck1
        call    Input_Proc
        jz      short keycheck1

; In:   AL = Scan code
; Out:  AH = Shift Status
;       AL = Char code
;       KeyShift will be updated
PUBPROC key_decode
        ; translate scan code to key code

        cmp     al, 0e0h
        je      short KeyboardI3        ;jump if extended scancode
        dec     eax                     ;1..88 ==> 0..87
        movzx   eax, al
        shl     eax, 1
        cmp     al, 2*max_keys          ;last key in the table
        jae     short KeyboardI5        ;jump if out of range (including E0)
        shr     ah, 1
        mov     ax, kbd_code[eax]
        jc      short KeyboardI4        ;jump if release key

        ; key down.

        mov     xtn_scancode, 0         ;ignore for pushed keys

        test    ah, ah                  ;special key?
        jz      short KeyboardI2        ;jump if special key
        ; normal key, is it shifted?
        test    KeyShift, K_CAP         ;CAPSlock on?
        jz      short KeyboardI1
        cmp     al, 'a'
        jb      short KeyboardI1
        cmp     al, 'z'+1
        jae     short KeyboardI1
        xchg    al, ah                  ;use upper case
KeyboardI1:
        test    KeyShift, K_SHIFT
        jz      short KeyboardI6
        mov     al, ah                  ;use the shifted value
        jmp     short KeyboardI6

KeyboardI2:
        and     al, K_ALT + K_CTL + K_SHIFT ;ALT | CTL | LS | RS
        or      KeyShift, al
        jmp     short KeyboardI5

KeyboardI3:
        mov     xtn_scancode, 1         ;extended scan code
        jmp     short KeyboardI5

KeyboardI4:     ; key up.
        shl     xtn_scancode, 1         ;preceeded by E0?
        test    ah, ah
        jnz     short KeyboardI5        ;jump if normal key

        ; Its a shift key

        mov     ah, K_INS + K_CAP + K_NUML + K_SCRL
        and     ah, al                  ;non-zero if one of the toggle keys
        xor     KeyShift, ah

        ; Filter the extended shift keys
        ; ~UP=2a e0 aa e0 48 e0 c8 aa   ;ignore 'e0 aa'
        test    xtn_scancode, 2         ;preceeded by E0?
        jnz     short KeyboardI5        ;jump if L/R shift
        and     al, K_ALT + K_CTL + K_SHIFT ;ALT | CTL | LS | RS
        not     al
        and     KeyShift, al
KeyboardI5:
        xor     al, al
KeyboardI6:
        mov     ah, K_ALT + K_CTL
        and     ah, KeyShift
        test    al, al
        ret

PUBPROC key_read
        call    key_check
        jz      short key_read
        ret

; ---------------------------------------------------------------------------
; In:
PUBPROC read_line
        DBGBRK  5
        mov     Cmd_Hint, OFFSET32 f1_help
        mov     eax, OFFSET32 cmd_buffer
        mov     byte ptr [eax], 0
        push    OFFSET32 read_line_input ; key filter proc
        push    eax                     ; buffer for data
        push    input_line_size         ; max number of chars
        push    1                       ; string col number
        call    Edit_Text
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,'ð',d_text,t_fill+input_line_size,'³'
        _jsr    read_line_hint
        db      d_text,t_fill+78-input_line_size,d_sub

        DBGBRK  5
        call    str_len                 ;if empty line, repeat last one
        push    esi
        mov     edi, OFFSET32 input_buff_end-input_line_size
        jecxz   short rl_replast
        cmp     key_macro_ptr, OFFSET32 macro_buff_end - 1
        jne     short in_the_buffer     ;if macro, do not buffer it
        inc     ecx                     ;include '\0'
        repe    cmpsb
        je      short in_the_buffer
        mov     edi, OFFSET32 input_buff_beg
        lea     esi, [edi+input_line_size]
        mov     ecx, input_buff_size/4  ; include cmd_buffer
        rep     movsd
        or      ScreenFlags, SF_OUTP
        mov     ebx, edi
        call    Printf
        db      d_lf,d_text,t_fill+80,d_el
in_the_buffer:
        pop     esi
        ret

rl_replast:
        xchg    edi, esi
        mov     cl, input_line_size/4
        rep     movsd
        pop     esi
        ret

editTxtStruc    struc
et_message      dd  ?
et_1stCol       db  ?
et_relCol       db  ?
et_context      dw  ?
et_maxLen       db  ?,?,?,?
et_Buffer       dd  ?
et_keyProc      dd  ?
editTxtStruc    ends

PUBPROC Edit_Text
        DBGBRK  2
        mov     ebx, [esp].et_Buffer
        mov     edx, [esp].et_message
        call    Printf
        db      d_sub,d_el
        ; edx = return address
        mov     al, [esp].et_1stCol
        add     al, [esp].et_relCol
        mov     ah, CurrentRow
        call    Cursor_Proc
et_getKey:
        push    edx
        call    [esp+4].et_keyProc
        pop     edx
        mov     esi, [esp].et_Buffer
        movzx   ebx, [esp].et_relCol
        cmp     al, 20h
        jge     short et_addChar
        cmp     al, K_ESC
        je      Main_Menu
        cmp     al, K_HOME
        je      short et_HOME
        cmp     al, K_END
        je      short et_END
        cmp     al, K_BKSP
        je      short et_BKSP
        cmp     al, K_DEL
        je      short et_DEL
        cmp     al, K_LEFT
        je      short et_LEFT
        cmp     al, K_RIGHT
        je      short et_RIGHT
        cmp     al, K_CR
        jne     Edit_Text
et_CR:  add     esp, SIZE editTxtStruc
        jmp     edx
et_el1: inc     bh
et_END: lodsb
        cmp     al, 0
        jne     et_el1
et_HOME:mov     [esp].et_relCol, bh
        jmp     Edit_Text
et_LEFT:cmp     [esp].et_relCol, bh
        je      Edit_Text
        dec     [esp].et_relCol
        jmp     Edit_Text
et_addChar:
        cmp     bl, [esp].et_maxLen
        jae     Edit_Text
        test    KeyShift, K_INS
        jnz     short et_addIns
        xchg    [esi+ebx], al
        cmp     al, 0
        jne     short et_RIGHT
        mov     [esi+ebx+1], al
et_RIGHT:
        cmp     [esi+ebx], bh
        je      Edit_Text
        inc     [esp].et_relCol
        jmp     Edit_Text
et_BKSP:dec     ebx
        js      Edit_Text
        mov     [esp].et_relCol, bl
        cmp     byte ptr [esi+ebx+1], 0 ; Last col?
        je      short et_DEL
        mov     byte ptr [esi+ebx], ' '
        test    KeyShift, K_INS
        jz      Edit_Text
et_DEL: mov     al, [esi+ebx]
@@:     cmp     al, 0
        je      Edit_Text
        mov     al, [esi+ebx+1]
        mov     [esi+ebx], al
        inc     ebx
        jmp     short @b

et_addIns:
        xchg    [esi+ebx], al
        inc     ebx
        cmp     al, 0
        je      short et_addEol
        cmp     bl, [esp].et_maxLen
        jb      et_addIns
et_addEol:
        mov     [esi+ebx], bh
        mov     bl, [esp].et_relCol
        jmp     et_RIGHT

; ---------------------------------------------------------------------------
f1_help db      'F1=Help',0

read_line_hint:
        mov     ebx, Cmd_Hint
        ret

rl_DataDown:
        db      0a8h                    ; test al, ?? (CF=0)
rl_DataUp:
        stc
        DBGBRK  3
        mov     eax, datawin_format
        movzx   eax, byte ptr [eax]     ;bytes per line
        jnc     short @f
        neg     eax
@@:     add     Code_Data_Ptrs[PNTR_DATA], eax
        jmp     short rl_UpdateScreen

rl_CodeDown:
        push    1                       ; 1 line
        call    CodeWinDown
        mov     Code_Data_Ptrs[PNTR_CODE], ebx
        jmp     short rl_UpdateScreen

rl_startMacro:
        movzx   eax, word ptr [esi+2]
        add     eax, OFFSET32 macro_buff_beg
        mov     key_macro_ptr, eax
rl_playMacro:
        DBGBRK  3
        mov     eax, key_macro_ptr
        movzx   eax, byte ptr [eax]
        test    al, al
;       jz      short read_line_input
        jz      short rl_RefreshScreen
        inc     key_macro_ptr
rl_keyreturn:
        ret

rl_CodeUp:
        call    CodeWinUp
rl_UpdateScreen:
        mov     al, SF_DATA+SF_CODE
rl_RefreshScreen:
        call    Refresh_Screen
read_line_input:
        ; In:   esp+8 => editTxtStruc structure
        ; Out:  al = key
        ; ebp should be presereved
        DBGBRK  2
        call    key_check
        jz      short rl_playMacro
        DBGBRK  2
        mov     key_macro_ptr, OFFSET32 macro_buff_end - 1
        mov     esi, OFFSET32 macro_buff_beg - 4
rl_findMacro:
        add     esi, 4
        cmp     ax, [esi]
        jb      short rl_findMacro
        DBGBRK  2
        je      rl_startMacro
        movzx   ebx, [esp+8].et_context
        cmp     ax, K_UP
        je      rl_DataUp
        cmp     ax, K_DOWN
        je      rl_DataDown
        cmp     ax, K_PGUP
        je      rl_CodeUp
        cmp     ax, K_PGDN
        je      rl_CodeDown
rl_nxtl:cmp     ax, K_sUP
        je      short rl_up
        cmp     ax, K_sDOWN
        jne     short updn_done
        dec     ebx
        dec     ebx
rl_up:  inc     ebx
        cmp     ebx, max_input_lines
        jae     short updn_done
        imul    edi, ebx, -input_line_size
        add     edi, OFFSET32 input_buff_end
        mov     esi, [esp+8].et_Buffer
        movzx   ecx, [esp+8].et_relCol
        jecxz   short @f
        repe    cmpsb
        jne     short rl_nxtl
@@:     mov     [esp+8].et_context, bx
        movzx   ebx, [esp+8].et_relCol
        xchg    esi, edi
        add     ecx, input_line_size
        sub     ecx, ebx
        rep     movsb
updn_done:
        ret

; ---------------------------------------------------------------------------
buff_full:
        reportError 'Buffer Full.'

PUBPROC Cmd_Set
        call    Parse_Line
        PartCmd 'CM'     GOTO_REL16, set_Marker, <PNTR_CODE>
        PartCmd 'DM'     GOTO_REL16, set_Marker, <PNTR_DATA>
        FullCmd 'HOTKEY' SKIP_BLANK, <OFFSET32 set_HotKey>
        FullCmd 'SCR'    SKIP_BLANK, <OFFSET32 set_Screen>
        FullCmd 'PRN'    SKIP_BLANK, <OFFSET32 set_Printer>
;;      FullCmd 'LOG'    SKIP_BLANK, <OFFSET32 set_LogLevel>
        db 0
        call    find_key                ; returns edx=shift|key
        call    Skip_Equal
        push    esi
        call    remove_macro
        pop     esi
        call    str_len
        jecxz   short get_macro3
        lea     eax, 5[ecx]
        cmp     macro_buff_spc, ax
        jb      buff_full
        sub     macro_buff_spc, ax
        inc     ecx             ;plus terminator
        mov     edi, macro_buff_str
        sub     edi, ecx
        mov     macro_buff_str, edi
        mov     ebx, edi
        sub     ebx, OFFSET32 macro_buff_beg
        shl     ebx, 16
        mov     bx, dx
put_macro1:
        lodsb
        cmp     al, ';'
        jne     short put_macro2
        mov     al, K_CR
put_macro2:
        stosb
        loop    put_macro1
        mov     edi, OFFSET32 macro_buff_beg-4
get_macro1:
        add     edi, 4
        cmp     bx, [edi]
        jb      get_macro1
get_macro2:
        xchg    ebx, [edi]
        add     edi, 4
        test    bx, bx
        jnz     get_macro2
get_macro3:
        ret

set_Marker:
        DBGBRK  4
        mov     ecx, eax
        mov     al, [esi]
        sub     al, '0'
        cmp     al, 10
        jae     syntaxError
        inc     esi
        xchg    ebx, eax
        call    Skip_Equal
        lea     edi, Code_Data_Ptrs[ecx+ebx*8+8]
        mov     ebx, Code_Data_Ptrs[ecx+0]
        mov     edx, Code_Data_Ptrs[ecx+4]
        cmp     al, 0
        je      short set_curval
        push    edi
        call    Scan_AddressDef
        pop     edi
        jc      addressError
set_curval:
        mov     [edi+0], ebx
        mov     [edi+4], edx
        ret

set_HotKey:
        call    Skip_Equal
        DBGBRK  3
IFDEF   _W95_
        call    find_key                ; returns edx=shift|key
        mov     word ptr HotKey, dx     ; key code and shift state
        ret
ELSE
        call    Scan_Decimal
        jc      syntaxError
        mov     byte ptr HotKey, bl     ; scan code (39h=SPACE by default)
        ret
ENDIF

set_Printer:
        call    Skip_Equal
        DBGBRK  2
        call    Parse_Line
        FullCmd 'LPT1'   GOTO_REL16, get_LPT_Port, 408h
        FullCmd 'LPT2'   GOTO_REL16, get_LPT_Port, 40ah
        FullCmd 'LPT3'   GOTO_REL16, get_LPT_Port, 40ch
        db 0
        DBGBRK  2
        call    Scan_Dword
        mov     edx, ebx
        jmp     short chk_LptPort

get_LPT_Port:
        DBGBRK  2
        movzx   edx, word ptr [eax]
chk_LptPort:
        ; check to see if port exists.
        ; make sure PRN != SCR
        cmp     DosInfo.ScreenType, SCR_PARA
        jne     short set_PRN
        cmp     dx, DosInfo.ParaPort
        jne     short set_PRN
        reportError 'PRN and SCR Ports the same.'
set_PRN:mov     DosInfo.PrinterPort, dx
        ret

remove_macro:
        mov     edi, OFFSET32 macro_buff_beg-4
rem_macro1:
        add     edi, 4
        cmp     dx, [edi]
        jb      rem_macro1
        jne     short rem_macro5
        movzx   ebx, word ptr [edi+2]
        lea     esi, [edi+4]
rem_macro2:
        lodsd
        stosd
        test    ax, ax
        jnz     rem_macro2
        push    edi
        lea     esi, macro_buff_beg[ebx]
        call    str_len
        inc     ecx
        mov     edi, OFFSET32 macro_buff_beg-4
rem_macro3:
        add     edi, 4
        cmp     word ptr [edi], 0
        je      short rem_macro4
        cmp     [edi+2], bx
        jae     rem_macro3
        add     [edi+2], cx
        jmp     rem_macro3
rem_macro4:
        lea     edi, [esi+ecx-1]
        mov     ecx, esi
        sub     ecx, macro_buff_str
        dec     esi
        std
        rep     movsb
        cld
        inc     edi
        mov     macro_buff_str, edi
        pop     ebx
        sub     edi, ebx
        mov     macro_buff_spc, di
rem_macro5:
        ret

PUBPROC find_key
        xor     edx, edx
        xor     eax, eax
key_plus_shift:
        xor     edx, eax
        call    Parse_Line
        PartCmd '~',     GOTO_REL16, key_plus_shift, 0010h
        PartCmd '^',     GOTO_REL16, key_plus_shift, 100h*K_CTL
        PartCmd '@',     GOTO_REL16, key_plus_shift, 100h*K_ALT
        FullCmd 'UP',    GOTO_REL16, key_found, K_UP
        FullCmd 'DOWN',  GOTO_REL16, key_found, K_DOWN
        FullCmd 'RIGHT', GOTO_REL16, key_found, K_RIGHT
        FullCmd 'LEFT',  GOTO_REL16, key_found, K_LEFT
        FullCmd 'FIVE',  GOTO_REL16, key_found, K_FIVE
        FullCmd 'HOME',  GOTO_REL16, key_found, K_HOME
        FullCmd 'END',   GOTO_REL16, key_found, K_END
        FullCmd 'BKSP',  GOTO_REL16, key_found, K_BKSP
        FullCmd 'TAB',   GOTO_REL16, key_found, K_TAB
        FullCmd 'ESC',   GOTO_REL16, key_found, K_ESC
        FullCmd 'CR',    GOTO_REL16, key_found, K_CR
        FullCmd 'PGUP',  GOTO_REL16, key_found, K_PGUP
        FullCmd 'PGDN',  GOTO_REL16, key_found, K_PGDN
        FullCmd 'PLUS',  GOTO_REL16, key_found, K_PLUS
        FullCmd 'MINUS', GOTO_REL16, key_found, K_MINUS
        FullCmd 'INS',   GOTO_REL16, key_found, K_INS
        FullCmd 'DEL',   GOTO_REL16, key_found, K_DEL
        FullCmd 'PRT',   GOTO_REL16, key_found, K_PRT
        FullCmd 'F10',   GOTO_REL16, key_found, K_F10
        FullCmd 'F11',   GOTO_REL16, key_found, K_F11
        FullCmd 'F12',   GOTO_REL16, key_found, K_F12
        FullCmd 'F1',    GOTO_REL16, key_found, K_F1
        FullCmd 'F2',    GOTO_REL16, key_found, K_F2
        FullCmd 'F3',    GOTO_REL16, key_found, K_F3
        FullCmd 'F4',    GOTO_REL16, key_found, K_F4
        FullCmd 'F5',    GOTO_REL16, key_found, K_F5
        FullCmd 'F6',    GOTO_REL16, key_found, K_F6
        FullCmd 'F7',    GOTO_REL16, key_found, K_F7
        FullCmd 'F8',    GOTO_REL16, key_found, K_F8
        FullCmd 'F9',    GOTO_REL16, key_found, K_F9
        FullCmd 'SPACE'  GOTO_REL16, chk_Char,  20h
        db 0
invalid_key:
        reportError 'Invalid Key.'

chk_Char:
        test    edx, edx                ; Shifted?
        jz      short invalid_key       ; if non-shifted SPACE
        test    dl, dl
        jz      short key_found
        mov     al, K_sSPACE
        mov     dl, 0
key_found:
        xor     edx, eax
        ret

; --------------------------------------------------------------------------
; Hot key support
; --------------------------------------------------------------------------
IFDEF   _W95_

; Called by VKD
; In:   CL = Scan code
; Out:  CF = 0:proceed, 1:ignore
PUBPROC SPWIN_Keyboard_Filter
        DBGBRK  3
        pushad

        xchg    eax, ecx
        call    key_decode              ; Update shift status
        xor     ax, word ptr HotKey
        jz      short HotKey_Break

        ; This is a good oportunity to restore the screen if we didnot
        ; (This can happen when tracing over an instruction that generates
        ; a fault that we do not handle).
        call    Usr_Screen_NP
        popad
        jmp     Prev_Keyboard_Filter

ReleaseShiftKeys db 9dh, 0e0h, 9dh, 0b8h, 0e0h, 0b8h, 0aah, 0b6h ; ctrl, alt, lshift, rshift

HotKey_Break:

        mov     esi, OFFSET32 ReleaseShiftKeys
        mov     ecx, 8
        VxDCall VKD_Force_Keys

;       ; Make sure our shift matches the system shift
;       ; Reading [417h]=BIOS_Shift_Status can cause a page fault, therefore
;       ; be a nice guy and use the APIs
;       VxDcall VKD_Get_Kbd_Owner
;       VxDcall VKD_Get_Shift_State

;       and     ax, not (SS_Shift_mask)
;       VxDcall VKD_Set_Shift_State

        popad
        stc                             ; ignore the key

ELSE  ; !_W95_

SPWIN_HK_Handler:
        push    edx             ; release Ctrl (and Shift) scan codes
        VxDCall VKD_Cancel_Hot_Key_State ; turn off hotkey mode

        mov     esi, esp        ; ptr edx
        mov     ecx, 2
        VxDCall VKD_Force_Keys
        pop     edx
ENDIF
        ; simulate an INT
        push    cs                      ; same CS
        pushfd
        xchg    eax, [esp]
        xchg    eax, [esp+8]            ; flags <==> EIP
        xchg    eax, [esp]              ; EIP in place and restore EAX
        push    0                       ; fault code

        call    Save_CPU_Registers

        ; Start with all shifts off
        and     KeyShift, not (K_ALT + K_CTL + K_SHIFT)

        call    SPWIN_MouseTrap
        db      'Hot Key',d_sub

PUBPROC Local_Beep
        mov     al, 10110110b
        out     43h, al
        jmp     short $+2
        out     42h, al
        jmp     short $+2
        mov     al, 03h
        out     42h, al
        jmp     short $+2
        in      al, 61h
        jmp     short $+2
        push    eax
        or      al, 3
        out     61h, al
        mov     eax, 20000h
@@:     dec     eax
        jnz     short @b
        pop     eax
        out     61h, al
        ret

LCODE_ENDS

; ***************************************************************************
; ICODE section
; ***************************************************************************
ICODE_SEG

; ***************************************************************************
; Device_Init time

PUBPROC Kybrd_Device_Init

IFDEF   _W95_
        DBGBRK  3
        mov     eax, @@VKD_Filter_Keyboard_Input
        mov     esi, OFFSET32 SPWIN_Keyboard_Filter
        VMMCall Hook_Device_Service
        mov     Prev_Keyboard_Filter, esi

ELSE  ; !_W95_
        mov     esi, OFFSET32 SPWIN_HK_Handler
        xor     edi, edi                ; always call
        mov     cl, CallOnRelease
        movzx   eax, byte ptr HotKey    ; scan code (39h=SPACE by default)
        mov     ebx, ((SS_Shift + SS_Ctrl + SS_Alt) shl 16) + SS_Ctrl
        mov     edx, 00009d1dh          ; refernce data (Ctrl release)
        VxDCall VKD_Define_Hot_Key
ENDIF
        ret

ICODE_ENDS
END

