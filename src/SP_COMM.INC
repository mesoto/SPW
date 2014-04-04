;  Some ASCII symbols
NUL     equ     0
SOH     equ     1
STX     equ     2
ETX     equ     3
EOT     equ     4
ACK     equ     6
DLE     equ     10h
NAK     equ     15h

;  The 8250 port offsets, relative to base (com1, com2, etc.)

TXBUF   equ     0               ; Tx Buffer
RXBUF   equ     0               ; Rx Buffer
BRLSB   equ     0               ; baud rate LSB divisor latch
BRMSB   equ     1               ; baud rate MSB
INTER   equ     1               ; interrupt enable register
INTID   equ     2               ; interrupt ID register
LCREG   equ     3               ; line control register
MCREG   equ     4               ; modem control reg
LSREG   equ     5               ; line status reg
MSREG   equ     6               ; modem status reg

; Equates for bits in the line control register

WLS0    equ     00000001b       ; word length select bit 0
WLS1    equ     00000010b       ; word length select bit 1
NSB     equ     00000100b       ; number stop bits
PAREN   equ     00001000b       ; parity enable
PAREVN  equ     00010000b       ; parity even
PARSTK  equ     00100000b       ; stick parity
SBREAK  equ     01000000b       ; send break
DLAB    equ     10000000b       ; set DLAB

; Equates for bits in Line Status register

DATARDY equ     00000001b       ; data ready
OVERRN  equ     00000010b       ; overrun error
PARERR  equ     00000100b       ; parity error
FRAMERR equ     00001000b       ; framing error
RBREAK  equ     00010000b       ; break interrupt (received break)
THRE    equ     00100000b       ; transmitter holding reg empty
TSRE    equ     01000000b       ; tx shift register empty

;  Equates for bits in Modem Control register

DTR     equ     00000001b       ; DTR
RTS     equ     00000010b       ; RTS
OUT1    equ     00000100b       ; aux signal "out1" (not used)
OUT2    equ     00001000b       ; ditto "out2"
LOOPIT  equ     00010000b       ; loop mode latch

;  Equates for bits in Modem Status register

DCTS    equ     00000001b       ; delta CTS
DDSR    equ     00000010b       ; delta DSR
TERI    equ     00000100b       ; trailing edge RI
DRLSD   equ     00001000b       ; delta Rx Line Signal Detect
CTS     equ     00010000b       ; CTS
DSR     equ     00100000b       ; DRS
RINGIN  equ     01000000b       ; RI
RLSD    equ     10000000b       ; Rx Line Signal Detect

;  Equates for bits in Interrupt Enable register

ENRX    equ     00000001b       ; enable Data Available int
ENTX    equ     00000010b       ; enable Tx Holding Reg Empty int
ENRXS   equ     00000100b       ; enable Rx Special Conditions int
ENMS    equ     00001000b       ; enable Modem Status Interrupt

; 115200/baud
DIVISOR_300     equ 384
DIVISOR_600     equ 192
DIVISOR_1200    equ 96
DIVISOR_2400    equ 48
DIVISOR_4800    equ 24
DIVISOR_9600    equ 12                  ;default baud rate
DIVISOR_14400   equ 8
DIVISOR_19200   equ 6
DIVISOR_28800   equ 4
DIVISOR_38400   equ 3
DIVISOR_57600   equ 2
DIVISOR_115200  equ 1

; ---------------------------------------------------------------------------
KILL_TIME MACRO
        JMP     short $+2
        ENDM

; ---------------------------------------------------------------------------
; In:   BX = port base address
;       CX = divisor for the baud rate to use
; Kills DX, AL

COM_Init MACRO  Rbx, Rcx, Rdx, ParStpLen
        local   w4bufempty
        lea     Rdx, INTER[Rbx]         ;shut down 8250 interrupts
;;      in      al, dx                  ;read how interrupts are set
;;      KILL_TIME
;;      push    ax                      ;save 'em away
        xor     al, al                  ;disable 8250 interrupts
        out     dx, al                  ;
        KILL_TIME
        lea     Rdx, LSREG[Rbx]         ;dx=line status register

        ;now wait for current character to be
        ;be shifted out (if there is one)

w4bufempty:
        in      al, dx
        test    al, THRE
        jz      w4bufempty
        KILL_TIME

        mov     al, DLAB                ;set dlab for baud rate
        lea     Rdx, LCREG[Rbx]         ;dx=line control register for port
        out     dx, al                  ;assert Divisor Latch Access Bit (DLAB)
        KILL_TIME
        mov     Rdx, Rbx                ;dx=base 8250
        mov     al, cl                  ;least significant divisor byte to al
        out     dx, al
        KILL_TIME
        inc     Rdx                     ;dx=base 8250 + 1
        mov     al, ch                  ;most significant divisor byte to al
        out     dx, al
        KILL_TIME
        mov     al, ParStpLen           ;get parity,stop etc.
;;      and     al, not DLAB            ;make dlab=0
        lea     Rdx, LCREG[Rbx]         ;dx=line control register for port
        out     dx, al
;;      KILL_TIME
;;      pop     ax                      ;get interrupt setting back
;;      lea     Rdx, INTER[Rbx]         ;shut down 8250 interrupts
;;      cli
;;      out     dx, al                  ;do it twice (per National)
;;      KILL_TIME
;;      out     dx, al
;;      sti
        ENDM

; ---------------------------------------------------------------------------
;
;       Read a character from 8250 if one is available and return
;       ZF=1 indicats no character is available
;
; In:   BX = port base address
; Out:  AL = byte received or 0
; Kills DX
;
COM_Receive     MACRO Rbx, Rcx, Rdx, idle_proc
        local   recvLoop
        lea     Rdx, LSREG[Rbx]         ;dx=line status register
recvLoop:
    ifnb <idle_proc>
        call    idle_proc
    endif
        in      al, dx
        and     al, DATARDY             ;see if data ready
        jz      short recvLoop
        KILL_TIME

        mov     Rdx, Rbx                ;dx= rx buffer
        in      al, dx
        ENDM

; ---------------------------------------------------------------------------
;
;       Output character to port if possible return
;       indicating that 8250 is still busy, or ASSUCCESS indicating
;       operation was completed.
;
; In:   BX = port base address
;       AH = char to send
; OUT:  ZF = 1 if char sent
; Kills DX, AL
;
COM_Send MACRO  Rbx, Rcx, Rdx, idle_proc
        local   wait4TxEmpty
        lea     Rdx, LSREG[Rbx]         ;dx=line status register
wait4TxEmpty:
    ifnb <idle_proc>
        call    idle_proc
    endif
        in      al, dx
        test    al, THRE                ;check transmit holding
        jz      wait4TxEmpty
        KILL_TIME
        mov     Rdx, Rbx                ;and output to 8250/16450
        mov     al, ah
        out     dx, al

        ENDM

; ---------------------------------------------------------------------------
SERIAL_HostSync MACRO Rbx, Rcx, Rdx, idle_proc

        mov     ah, al                  ;char to send
        COM_Send Rbx, Rcx, Rdx, idle_proc

        ; Now receive ACK or Data

        COM_Receive Rbx, Rcx, Rdx, idle_proc
        ; AL received char

        ENDM

SERIAL_Host MACRO Rbx, Rcx, Rdx

        mov     ah, al                  ;char to send
        COM_Send Rbx, Rcx, Rdx

        ; Now receive ACK or Data

        COM_Receive Rbx, Rcx, Rdx
        ; AL received char

        ENDM

SERIAL_Slave MACRO idle_Proc

        mov     ah, al                  ;AH=char to send
        COM_Receive bx, cx, dx, idle_Proc
        ; AH preserved
        ; AL received char
        push    ax
        COM_Send bx, cx, dx, idle_Proc
        pop     ax

        ENDM

; ---------------------------------------------------------------------------
;
; The InterLink cable used the following connections:
;
;       D0 ----> S3
;       D1 ----> S4
;       D2 ----> S5
;       D3 ----> S6
;       D4 ----> S7 (inverted) (our clock)
;
; ---------------------------------------------------------------------------
;
;       Output character to port and get the response back
;
; In:   DX = port base address
;       AL = char to send
; OUT:  ZF = 1 if char sent
;       AH = line status register contents
; Kills DX, AH
;

; ---------------------------------------------------------------------------
; In:   dx = base port address
;       al = data to send (low 4 bits only)
; Out:  al = data returned (hi 4 bits)
; Kills bx
; ---------------------------------------------------------------------------
PARA_HostIO     MACRO

PARA_Host_IO:                           ; entry point
        out     dx, al

        inc     edx
        mov     bh, 80h                 ; times to loop (8000h)
ParaHostIo1:
        in      al, dx
        and     al, 0f8h                ; ignore unused bits
        cmp     al, Saved_iPort         ; any change?
        jne     short ParaHostIo2
        dec     bx
        jnz     short ParaHostIo1

        DBGBRK  3
        ; Remote not responding, RE-SYNC

        dec     edx
;       clc                             ; indicate error
        ret

ParaHostIo2:
        mov     ah, al
        in      al, dx                  ; re-read filters noise
        and     al, 0f8h                ; ignore unused bits
        cmp     al, ah
        jnz     short ParaHostIo1       ; should be noise
        dec     edx
        xchg    ah, Saved_iPort
        xor     ah, al
        shl     ah, 1                   ; bit7 should be 1 else its SYNC
        ; CF=1 if ok
        ret

        ENDM

; ---------------------------------------------------------------------------
; In:   dx = base port address
;       ch = data to send (low 4 bits only)
; Out:  ah = data returned (5 bits)
;       cf = success (1=ok)
; Kills bx
; ---------------------------------------------------------------------------
PARA_SlaveIO    MACRO idle_proc

PARA_Slave_IO:                          ; entry point
        xchg    bx, ax                  ; save char
        inc     dx
ParaSlaveIo1:
        call    idle_proc               ; all regs except AL should be saved
        in      al, dx
        and     al, 0f8h                ; ignore unused bits
        cmp     al, Saved_iPort         ; any change?
        jz      ParaSlaveIo1

        mov     ah, al
        in      al, dx                  ; re-read filters noise
        and     al, 0f8h                ; ignore unused bits
        cmp     al, ah                  ; noise?
        jnz     ParaSlaveIo1
        dec     dx
        xchg    al, Saved_iPort
        xor     al, ah
        shl     al, 1                   ; CF=1 if acceptable data, else SYNC

        mov     al, bl
        out     dx, al

        ret

        ENDM

; ---------------------------------------------------------------------------
; In:   DX = Port address
;       AL = Byte to send
; Out:  AL = Byte received
;       CF = 1: Normal, 0: Control
; ---------------------------------------------------------------------------
PARA_HostXchg   MACRO abort_proc
        push    ecx
        push    ebx

        DBGBRK  3
        xchg    ecx, eax                ; save char to send in CL
sendLoop1:
        mov     al, cl
        or      al, 10h                 ; indicate lo-nibble (b4=1)
        call    PARA_Host_IO
        jnc     short sendLoop2
        shl     al, 1
        jc      short sendLoop2
        mov     ch, al

        mov     al, cl
        shr     al, 4                   ; send hi-nibble now (b4=0)
        call    PARA_Host_IO
        jnc     short sendLoop2
        shl     al, 1
        jc      short sendLoop3

sendLoop2:
        ; Send the SYNC sequence
        mov     al, 1fh                 ;
        call    PARA_Host_IO
        mov     al, 1ah                 ;
        call    PARA_Host_IO
        mov     al, 15h
        call    PARA_Host_IO
        mov     al, 00h
        call    PARA_Host_IO

        ; Check for abort command
        call    abort_proc              ; all regs except EAX should be saved

        jmp     short sendLoop1

sendLoop3:
        DBGBRK  3
        shr     ch, 4
        or      al, ch

        pop     ebx
        pop     ecx

        ENDM

; ---------------------------------------------------------------------------
; Waits for host to send a byte and exchanges that with AH.
; In:   DX = Port address
;       AL = Byte to send
; Out:  AL = Byte received
;       CF = 1: Normal, 0: Control
; ---------------------------------------------------------------------------
PARA_SlaveXchg  MACRO
        push    cx
        push    bx

;;      int     60h
        mov     ch, al                  ; save char to send

ParaSlaveRecv1:
        mov     al, ch
        or      al, 10h                 ; lo-nibble
        call    PARA_Slave_IO
        jnc     short ParaSlaveRecv2
        shl     ah, 1
        jc      short ParaSlaveRecv2

        mov     cl, 4
        mov     al, ch
        shr     ax, cl                  ; send hi-nibble now
        mov     cl, ah                  ; lo nibble in b7..4

        call    PARA_Slave_IO
        jnc     short ParaSlaveRecv2
        shl     ah, 1
        jc      short ParaSlaveRecv3

ParaSlaveRecv2:
;;      int     60h
        mov     al, 1fh
        call    PARA_Slave_IO
        cmp     ah, 28h                 ; 15h sent?
        jne     short ParaSlaveRecv2
        mov     al, 0
        call    PARA_Slave_IO
        cmp     ah, 80h
        je      short ParaSlaveRecv1
        jmp     short ParaSlaveRecv2


ParaSlaveRecv3:
        xchg    ax, cx
        or      al, ch

        pop     bx
        pop     cx

        ENDM

