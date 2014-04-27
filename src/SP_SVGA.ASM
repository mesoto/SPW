title.  SoftProbe - SP_SVGA

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

SP_SVGA EQU 1
include SP_DEFS.inc
include SP_SCRN.inc

; ---------------------------------------------------------------------------
LDATA_SEG

Font_SaveBuffer db 2000h dup( 0 )

; ===========================================================================
; Screen state variables.
; ===========================================================================
User_State      VGA_SCREEN_STATE <>
Probe_State     VGA_SCREEN_STATE <>

LDATA_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG

; ***************************************************************************
;
;
;
;
;
; ===========================================================================
PUBPROC SVGA_Init
        DBGBRK  3

        mov     eax, 0b8000h
        call    Select_ScreenMem
        db      SCR_SVGA
        dd      OFFSET32 Local_Keyboard
        dd      OFFSET32 Local_Display
        dd      OFFSET32 SVGA_Cursor
        dd      OFFSET32 SVGA_ProbeScreen
        dd      OFFSET32 SVGA_UserScreen
        dd      13741f17h               ; a_f a_r a_b a_n

init_Patch:
        ; !!!!!!  VGA state should be read in TEXT MODE  !!!!!!
        ; We are going to run this part only once (during Sys_Critical_Init)
        ; Text mode is forced by the real mode proc.

        push    ebp
        call    Get_CRTC_Address
        ; edx=3cc
        ; ebp=3d4/3b4

        mov     ebx, OFFSET32 Probe_State
        call    Read_VgaRegisters
        call    Release_Vga
        pop     ebp

        ; Make sure it is done only once
        mov     byte ptr init_Patch, 0c3h ; RET

        stc                             ; Success
        ret

; ---------------------------------------------------------------------------
; In:   AL = col
;       AH = row
;
PUBPROC SVGA_Cursor
        DBGBRK  3
        push    edx

        xor     ecx, ecx
        xchg    cl, ah
        imul    ecx, 80
        add     cx, ax

        mov     dx, 3cch
        in      al, dx
        mov     dl, 0d4h
        test    al, 1
        jnz     short SetCursorPosition
SetMonoCursor:
        mov     dl, 0b4h
SetCursorPosition:
        mov     al, 0fh
        mov     ah, cl
        call    Word_Out
        mov     al, 0eh
        mov     ah, ch
        call    Word_Out

;       ; Now set the cursor shape (insert/overwrite)
;       test    KeyShift, K_INS
;       mov     ah, 0eh
;       jz      short @f
;       mov     ah, 01h
;@@:    mov     al, 0ah                 ; cursor start scan line
;       call    Word_Out
;       mov     ah, 0fh
;       mov     al, 0bh                 ; cursor end scan line
;       call    Word_Out
        pop     edx
        ret

; ---------------------------------------------------------------------------
; In:   AL = col
;       AH = row
PUBPROC Mono_Cursor
        DBGBRK  3
        push    edx
        xor     ecx, ecx
        xchg    cl, ah
        imul    ecx, 80
        add     cx, ax
        mov     dh, 3
        jmp     short SetMonoCursor

; ===========================================================================
; In:   DX = port address
;       AX = data to write
Word_Out:
        out     dx, al
        IO_Delay 1
        inc     edx
        xchg    al, ah
        out     dx, al
        dec     edx
        ret

; ===========================================================================
;
; - Save the current video state for later restoring (The current video
;   state can be either graphics or text (DOS BOX))
; - Save the 8K of video memory that SoftProbe will use in text mode
; - Switch the video board into text mode (25, 44, or 50 line mode)
;
;   In:  AL = Text Mode (25, 44, or 50)
;   Out: Nothing.
;
; ===========================================================================
PUBPROC SVGA_ProbeScreen
        DBGBRK  3

        push    ebp
        call    Get_CRTC_Address
        ; edx=3cc
        ; ebp=3d4/3b4
        mov     ebx, OFFSET32 User_State
        call    Read_VgaRegisters

        mov     ebx, OFFSET32 Probe_State
        call    Write_VgaRegisters
        call    Download_ProbeFont
        mov     eax, ScreenBase
        mov     esi, eax
        mov     edi, OFFSET32 SavedSCREEN ; point to save buffer area
        mov     ecx, SCREENSIZE/2       ; size of screen area to be saved
        rep     movsw                   ; save it
        xchg    edi, eax
        mov     cx, SCREENSIZE/2
        xor     eax, eax
        rep     stosw
        call    Release_Vga
        pop     ebp
        ret

; ===========================================================================
;
; This routine must restore the video to the state saved by SaveScreen.
;   In:  Nothing.
;   Out: Nothing.
; ===========================================================================

PUBPROC SVGA_UserScreen
        DBGBRK  3

        push    ebp
        call    Get_CRTC_Address

        ; Save Probe State
        mov     ebx, OFFSET32 Probe_State

        ; Get_CursorPos
        mov     edx, ebp                ; 3d4/3b4
        outByte 0eh, DLY1
        inc     edx
        inByte  [ebx].CRT_Registers.C_CursHi, DLY1
        dec     edx
        outByte 0fh, DLY1
        inc     edx
        inByte  [ebx].CRT_Registers.C_CursLo, DLY1

        mov     ebx, OFFSET32 User_State
        call    Init_AttrFlipFlop

        ; Restore text screen
        mov     esi, OFFSET32 SavedSCREEN ; from user buffer
        mov     edi, ScreenBase         ; to video memory
        mov     ecx, SCREENSIZE/2       ; load the save/restore length
        rep     movsw                   ; move one row to buffer

        call    Download_UserFont
        call    Write_VgaRegisters
        pop     ebp
        ret

Release_Vga:
        lea     edx, [ebp+6]            ; 3da/3ba
        inByte  al, DLY1
        mov     dl,0C0h
        inByte  al, DLY1
        or      al,020h                 ; PAS ON: allow display to access
        outByte al, DLY0                ;         palette RAM.
        ret

Read_VgaRegisters proc
        ; get the current index value
        mov     edx, ebp                ; 3d4/3b4
        inByte  [ebx].CRT_IndexReg, DLY1
        lea     edx, [ebp+6]            ; 3da/3ba
        inByte  al, DLY1
        mov     dl, 0C0h
        inByte  [ebx].ATT_IndexReg, DLY1
        mov     dl, 0CEh
        inByte  [ebx].GRF_IndexReg, DLY1
        mov     dl, 0C4h
        inByte  [ebx].SEQ_IndexReg, DLY1

        call    Init_AttrFlipFlop

        xor     ecx, ecx
        mov     dl, 0CCh
        inByte  [ebx].MSC_Register, DLY1
        mov     dl, 0CAh
        inByte  [ebx].FEA_Control, DLY1

        mov     edx, ebp                ; 3d4/3b4

        ; Turn PR (Protect Register) OFF before accessing these registers

        outByte 11h, DLY1
        inc     edx
        inByte  al, DLY1
        and     al, 7Fh                 ; Protect (reg 0-7) off
        outByte al, DLY1
        dec     edx

        ; Enable CR bit (Compatible Read)

        outByte 3, DLY1
        inc     edx
        inByte  al, DLY1
        or      al, 80h
        outByte al, DLY0
        dec     edx

        ; Now read all registers

        mov     cl, 25
        lea     edi, [ebx].CRT_Registers
        call    Get_GroupRegisters

        mov     dl, 0CEh
        mov     cl, 9
        lea     edi, [ebx].GRF_Registers
        call    Get_GroupRegisters

        mov     dl, 0C4h
        mov     cl, 5
        lea     edi, [ebx].SEQ_Registers
        call    Get_GroupRegisters

        mov     cl, 21
        xor     ah, ah
        lea     edi, [ebx].ATT_Registers
        ; Wait for a vertical sync

        push    ecx
        mov     ch, 0ffh
        lea     edx, [ebp+6]            ; 3da/3ba
@@:     inByte  al, DLY1
        test    al, 08h                 ; VR?
        loopz   @b
        pop     ecx

@@:     lea     edx, [ebp+6]            ; 3da/3ba
        inByte  al, DLY1                ; reset attribute flip/flop
        mov     dl, 0C0h
        outByte ah, DLY1
        inc     edx
        insb
        inc     ah
        loop    @b

        ; Load_DACRegs
        lea     edi, [ebx].DAC_Registers
        xor     eax, eax
@@:     mov     dl, 0C7h
        outByte al, DLY1
        mov     dl, 0C9h
        insb
        IO_Delay DLY1
        insb
        IO_Delay DLY1
        insb
        inc     al
        jne     short @b
        ret

Read_VgaRegisters endp

Write_VgaRegisters proc

        mov     dl, 0C2h
        outByte [ebx].MSC_Register, DLY1

        mov     dl, 0c4h
        mov     ax, 100h                        ; Reset Register
        call    Out_DataReg

        outByte 1, DLY1                         ; Clocking Mode Register
        inc     edx
        mov     al, [ebx].SEQ_Registers[1]
        and     al, not 20h                     ; Turn Screen ON (SO)
        outByte al, DLY1
        dec     edx

        outByte 3, DLY1                         ; Char Map Select Register
        inc     edx
        outByte [ebx].SEQ_Registers[3], DLY1

        mov     dl, 0CEh
        outByte 6, DLY1                         ; Memory Map Register
        inc     edx
        outByte [ebx].GRF_Registers[6], DLY1

        mov     dl, 0C4h
        outByte 0, DLY1                         ; Reset Register
        inc     edx
        outByte [ebx].SEQ_Registers[0], DLY1    ; restore original value

        mov     edx, ebp                        ; CRTC: 3D4/3B4
        outByte 11h, DLY1
        inc     edx
        inByte  al, DLY1
        and     al, 7Fh                 ; Protect (reg 0-7) off
        outByte al, DLY0
        dec     edx

        xor     ecx, ecx
        lea     esi, [ebx].CRT_Registers
        mov     cl, 25
        call    Set_GroupRegisters

        mov     cl, 10h
        call    Set_AttrRegister
        mov     cl, 12h
        call    Set_AttrRegister
        mov     cl, 13h
        call    Set_AttrRegister
        mov     cl, 14h
        call    Set_AttrRegister

        mov     dl, 0C4h
        outByte 1, DLY1
        inc     edx
        mov     al, [ebx].SEQ_Registers[1]
        or      al, 20h                         ; Turn Screen OFF
        out     dx, al

        xor     ecx, ecx
L000005C2:
        call    Set_AttrRegister
        inc     ecx
        cmp     ecx, 17
        jb      L000005C2

        ; Restore DAC
        lea     esi, [ebx].DAC_Registers
        xor     eax, eax
@@:     mov     dl, 0C8h
        outByte al, DLY1
        inc     edx
        outsb
        IO_Delay DLY1
        outsb
        IO_Delay DLY1
        outsb
        inc     al
        jnz     @b

        mov     al, 11h
        call    Set_AttrRegister

        mov     dl, 0C4h
        outByte 1, DLY1
        inc     edx
        mov     al, [ebx].SEQ_Registers[1]
        and     al, not 20h                     ; Screen ON
        outByte al, DLY1
        dec     edx

        outByte 2, DLY1
        inc     edx
        outByte [ebx].SEQ_Registers[2], DLY1
        dec     edx

        outByte 4, DLY1
        inc     edx
        outByte [ebx].SEQ_Registers[4], DLY1

        mov     dl, 0CEh
        lea     esi, [ebx].GRF_Registers
        mov     cl, 9
        call    Set_GroupRegisters

        mov     dl, 0C2h
        outByte [ebx].MSC_Register, DLY1

        mov     dl, 0CEh
        mov     al, [ebx].GRF_IndexReg
        and     al, 1Fh
        outByte al, DLY1

        mov     dl, 0C4h
        outByte [ebx].SEQ_IndexReg, DLY1

        mov     edx, ebp                ;3d4/3b4
        mov     al, [ebx].CRT_IndexReg
        and     al, 7Fh
        outByte al, DLY1

        add     edx, 6
        inByte  al, DLY1
        mov     al, [ebx].ATT_IndexReg
        and     al, 3Fh
        mov     dl, 0C0h
        outByte al, DLY0
        ret

Write_VgaRegisters endp

Init_AttrFlipFlop proc

        lea     edx, [ebp+6]            ; 3da/3ba
        inByte  al, DLY1                ; reset attribute flip/flop
        mov     dl, 0C0h
        outByte 0, DLY0
        ret

Init_AttrFlipFlop endp

Set_GroupRegisters proc
        mov     al, 0
@@:     outByte al, DLY1
        inc     edx
        outsb
        dec     edx
        inc     eax
        loop    @b
        ret
Set_GroupRegisters endp

Get_GroupRegisters proc
        mov     al, 0
@@:     outByte al, DLY1
        inc     edx
        insb
        dec     edx
        inc     eax
        loop    @b
        ret
Get_GroupRegisters endp

Set_AttrRegister proc

        lea     edx, [ebp+6]
        inByte  al, DLY1
        mov     dl, 0C0h
        outByte cl, DLY1
        outByte [ebx].ATT_Registers[ecx], DLY0
        ret

Set_AttrRegister endp

Get_CRTC_Address proc

        mov     edx, 3CCh
        in      al, dx
        lea     ebp, [edx+3D4h-3CCh]
        test    al, 01h                 ; IOA: Color (3Dx) or Mono (3Bx)
        jne     short @f
        lea     ebp, [edx+3B4h-3CCh]
@@:     ret

Get_CRTC_Address endp

Out_DataReg proc

        outByte al, DLY1
        inc     edx
        outByte ah, DLY0
        dec     edx
        ret

Out_DataReg endp

Download_ProbeFont  proc
        call    Begin_FontLoad
        mov     edx, ebp                ; 3d4/3b4
        mov     ax, 4F09h               ; 4F=25, 47=50, 48=44 lines
        call    Out_DataReg

        mov     esi, ScreenBase         ; B8000
        mov     edi, OFFSET32 Font_SaveBuffer
        mov     ecx, 2000h/2            ; 1st 4K
        rep     movsw

        mov     esi, DosInfo.VgaFont8x16
        mov     edi, ScreenBase         ; B8000

        xor     eax, eax
        mov     dl, 0
@@:     mov     cl, 8                   ; height of font/2
        rep     movsw
        mov     cl, 8                   ; fill reminder (32 total)
        rep     stosw
        dec     dl
        jnz     @b

End_FontLoad    proc
        mov     dl, 0C4h
        call    Set_VgaRegisters
        db      4
        dw      0100h                   ;  synchronous reset
        dw      0302h                   ;  CPU writes to maps 0 and 1
        dw      0304h                   ;  odd-even addressing
        dw      0300h                   ;  clear synchronous reset

        mov     dl, 0CEh                ; graphics controller
        call    Set_VgaRegisters
        db      3
        dw      0004h                   ; select map 0 for CPU reads
        dw      1005h                   ; enable odd-even addressing
        dw      0E06h                   ; map starts at B800:0000

        lea     edx, [ebp+6]            ; 3da/3ba
        inByte  al, DLY1
        mov     dl, 0C0h
        outByte 10h, DLY1
        outByte 0Ch, DLY0
        ret

End_FontLoad    endp
Download_ProbeFont  endp

Download_UserFont   proc
        call    Begin_FontLoad
        mov     esi, OFFSET32 Font_SaveBuffer
        mov     edi, ScreenBase         ; B8000
        mov     ecx, 2000h/2            ; 1st 4K
        rep     movsw
        jmp     End_FontLoad

Download_UserFont   endp

Set_VgaRegisters:
        pop     esi
        lodsb
        movzx   ecx, al
@@:     lodsw
        call    Out_DataReg
        loop    @b
        jmp     esi

Begin_FontLoad  proc
        mov     dl, 0C4h
        call    Set_VgaRegisters
        db      4
        dw      0100h                   ; synchronous reset
        dw      0402h                   ; CPU writes only to map 2
        dw      0604h                   ; sequential addressing
        dw      0300h                   ; clear synchronous reset

        mov     dl, 0CEh                ; graphics controller
        call    Set_VgaRegisters
        db      3
        dw      0204h                   ; select map 2 for CPU reads
        dw      0005h                   ; disable odd-even addressing
        dw      0d06h                   ; map starts at B8000-BFFFF

        lea     edx, [ebp+6]            ; 3da/3ba
        inByte  al, DLY1                ; reset attribute flip/flop
        mov     dl, 0C0h
        outByte 10h, DLY2
        outByte 1, DLY0
        ret
Begin_FontLoad  endp

LCODE_ENDS
END

