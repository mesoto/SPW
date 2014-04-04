; ---------------------------------------------------------------------------
; ** Supported consoles -----------------------------------------------------
; ---------------------------------------------------------------------------
EXTPROC SP_SVGA SVGA_Init
EXTPROC SP_SVGA Mono_Cursor
EXTPROC SP_MONO Mono_Init
EXTPROC SP_PARA Para_Init
EXTPROC SP_SERI Serial_Init
EXTPROC SP_MONO Local_Display
EXTPROC SP_DISP Select_Screen
EXTPROC SP_DISP Select_ScreenMem

EXTDWRD SP_DISP ScreenBase
EXTDWRD SP_DISP win_1stLine
EXTDWRD SP_DISP win_lastLine
EXTBYTE SP_DISP ScreenColors
EXTWORD SP_DISP SavedSCREEN     ; SCREENSIZE byte buffer.

SCREENSIZE EQU 8000

CRTC_Struc      STRUC
C_HTotal        DB ?    ; 00 Horizontal total
C_HDisp         DB ?    ; 01 Horizontal Displacement
C_HBlnkStrt     DB ?    ; 02 Horizontal Blank start
C_HBlnkEnd      DB ?    ; 03 Horizontal Blank end
C_HRTCStrt      DB ?    ; 04 Horizontal retrace start
C_HRTCEnd       DB ?    ; 05 Horizontal retrace end
C_VTotal        DB ?    ; 06 Vertical total
C_Ovflw         DB ?    ; 07 8th bit for following
C_RowScn        DB ?    ; 08 First row after VRTC
C_CharHgt       DB ?    ; 09 Character Cell Height
C_CStart        DB ?    ; 0A Cursor start scan line
C_CEnd          DB ?    ; 0B Cursor end scan line
C_AddrH         DB ?    ; 0C VRAM address high byte
C_AddrL         DB ?    ; 0D VRAM address low byte
C_CursHi        DB ?    ; 0E Cursor address high byte
C_CursLo        DB ?    ; 0F Cursor address low byte
C_VRTCStrt      DB ?    ; 10 Vertical retrace start (write only)
                        ;    Light pen address high byte(read only)
C_VRTCEnd       DB ?    ; 11 Vertical retrace end(write only)
                        ;    Light pen address low byte(read only)
C_VDspEnd       DB ?    ; 12 Vertical display end line
C_LnOff         DB ?    ; 13 Offset to next line
C_UndrLn        DB ?    ; 14 Underline
C_VBlnkStrt     DB ?    ; 15 Vertical blanking start
C_VBlnkEnd      DB ?    ; 16 Vertical blanking end
C_Mode          DB ?    ; 17 Mode
C_LnCmp         DB ?    ; 18 Line compare for MA clearing
CRTC_Struc      ENDS

; ===========================================================================
VGA_SCREEN_STATE struc
 CRT_Registers  db SIZE CRTC_Struc dup(0) ; crt controller (3d4/3b4)
 ATT_Registers  db 21 dup(0)              ; attribute controller  (3c0)
 SEQ_Registers  db 5  dup(0)              ; sequencer registers   (3c4)
 GRF_Registers  db 9  dup(0)              ; graphics controller   (3ce)
 MSC_Register   db 0                      ; miscellaneous         (3cc)
 FEA_Control    db 0                      ;
 ATT_IndexReg   db 0                      ;
 SEQ_IndexReg   db 0                      ;
 CRT_IndexReg   db 0                      ;
 GRF_IndexReg   db 0                      ;
 DAC_Registers  db 256*3 dup(0)           ; dac registers         (3c9)
VGA_SCREEN_STATE ends

; ===========================================================================

DLY0    equ     0
DLY1    equ     1
DLY2    equ     2

IO_Delay macro  N
        ifb     <N>
        jmp     short $+2
        else
        rept    N
        jmp     short $+2
        endm
        endif
        endm

inByte  macro   r, N
        in      al, dx
        ifdif   <r>, <al>
        mov     r, al
        endif
        IO_Delay N
        endm

outByte macro   r, N
        ifdif   <r>, <al>
        mov     al, r
        endif
        out     dx, al
        IO_Delay N
        endm

