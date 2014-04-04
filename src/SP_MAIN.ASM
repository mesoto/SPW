title.  SoftProbe - SP_Main

SP_MAIN EQU 1
include SP_DEFS.inc
EXTPROC SP_FLTS Read_dwIndex_EDX

LDATA_SEG
; ---------------------------------------------------------------------------
; ** PGROUP starts here -----------------------------------------------------
; ---------------------------------------------------------------------------

PUBDWRD         PrevRegs <19 dup( 0 )>
PUBDWRD         errMessage 0

w_bytes         equ 0
w_words         equ 1
w_dwords        equ 2
w_ascii         equ 3

PUBBYTE watch_expressions here
                             ;---------25-bytes---------
watchwin1       db  w_dwords,'SS:ESP                   ',0
watchwin2       db  w_bytes ,'DS:ESI                   ',0
watchwin3       db  w_bytes ,'ES:EDI                   ',0
watchwin4       db  w_ascii ,'DS:EDX                   ',0
watchwin5       db  w_words ,'ES:EBX                   ',0
watchwin6       db  w_dwords,'SS:EBP                   ',0
watchwin7       db  w_bytes ,'CS:EIP                   ',0
watchwin8       db  w_bytes ,'DS:0                     ',0

watchwinsize    equ (watchwin2 - watchwin1)

                align 4
PUBDWRD         Code_Data_Ptrs here
                dd 11 dup(0,VXD_DATASELECTOR) ; data_ptr + 10 markers
                dd 11 dup(0,VXD_CODESELECTOR) ; code_ptr + 10 markers
                dd 0,0                  ; watch
                dd 0,0                  ; effadr
                dd 0,VXD_DATASELECTOR   ; Working memory

PUBDWRD         actual_IP 0
PUBDWRD         currentInst 0           ; linear address of CS:EIP
block1          dd 0,0
block2          dd 0,0
searchAddress   dd 0,0
searchLength    dd 0

searchBufLen    db 0
searchBuffer    db 64 dup (0)

PUBBYTE         def_segsize, 0  ;bit0=32 bit operand size
                                ;bit1=32 bit address size
                                ;bit6=zero base
                                ;bit7=V86 address type

While_Expr      db input_buff_size dup (0) ;WHILE <exp> <cmd>

LDATA_ENDS

; ---------------------------------------------------------------------------
; ** pmCode starts here -----------------------------------------------------
; ---------------------------------------------------------------------------
LCODE_SEG

PUBBYTE disp_as_byte 16
        db 4 dup(d_mem,DM_BYTE+4,'  '),' '
        _jsr Sub_Ebx_16
        db d_mem,DM_ASCI+16,d_sub

PUBBYTE disp_as_word 16
        db d_mem,DM_WORD+4,d_spc,3,d_mem,DM_WORD+4
        _jsr Sub_Ebx_16
        db d_spc,6,d_mem,DM_ASCI+16,d_sub

PUBBYTE disp_as_dword 20
        db d_mem,DM_DWRD+5,'  '
        _jsr Sub_Ebx_20
        db d_mem,DM_ASCI+20,d_sub

PUBBYTE disp_as_ascii 64
        db d_mem,DM_ASCI+64,d_sub

PUBBYTE disp_as_byte2 16
        db d_mem,DM_BYTE+16,'  '
        _jsr Sub_Ebx_16
        db d_mem,DM_ASCI+16,d_sub

PUBBYTE disp_as_word2 16
        db d_mem,DM_WORD+8
        _jsr Sub_Ebx_16
        db d_spc,3,d_mem,DM_ASCI+16,d_sub

PUBBYTE disp_as_dword2 24
        db d_mem,DM_DWRD+6,d_sub

Sub_Ebx_16:
        sub     ebx, 16
        ret

Sub_Ebx_20:
        sub     ebx, 20
        ret

set_registr3:   
        call    flag_registers
        jnc     short set_flags
        reportError 'Unknown Register.'

set_flags:      
        push    eax             ;bit number
        call    Scan_Dword      ;0/1
        shr     ebx, 1
        jnz     valueError
        pop     eax             ;bit number
        jc      short set_bitval
        btr     [ebp].R_EFLAGS, eax
        jmp     short registers_then_menu

set_bitval:     
        bts     [ebp].R_EFLAGS, eax
registers_then_menu:
        mov     al, SF_REGS
        jmp     short Update_Screen

Cmd_R:  call    register_value
        jc      short set_registr3
        push    eax             ; ptr savedReg
        push    ecx             ; 1=8, 2=16, 3=32 bit long
        call    Scan_Dword
        pop     ecx
        pop     edi
        loop    short set_registr1
        mov     [edi], bl
        jmp     short Init_AllWindows
set_registr1:   
        loop    short set_registr2
        mov     [edi], bx
        jmp     short Init_AllWindows
set_registr2:   
        mov     [edi], ebx

; ---------------------------------------------------------------------------
PUBPROC Init_AllWindows
        mov     ebx, [ebp].R_EIP
        mov     eax, dword ptr [ebp].R_CS
        cmp     eax, Code_Data_Ptrs[PNTR_CODE][4]
        jne     short set_codeOff
        cmp     ebx, Code_Data_Ptrs[PNTR_CODE][0]
        jb      short set_codeOff
        cmp     ebx, code_win_end
        jb      short use_codeOff
set_codeOff:
        mov     Code_Data_Ptrs[PNTR_CODE], ebx
        mov     Code_Data_Ptrs[PNTR_CODE][4], eax
use_codeOff:
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        mov     currentInst, ebx
PUBPROC Display_AllWindows
        mov     al, SF_OUTP+SF_CODE+SF_DATA+SF_REGS
PUBPROC Update_Screen
        DBGBRK  5
        or      ScreenFlags, al
PUBPROC Main_Menu
IF      DBG
        ; Check IntFlag and Trace flags are 0
        pushfd
        pop     eax
        test    ah, 3
        jz      short @f
        cli
        push    eax
        call    PrintfMainScr
        db      d_lf,a_r,'INVALID FLAGS:',d_h32,d_el
@@:
ENDIF
        mov     esp, ebp
        call    read_line
        and     Log_Falgs, not (LF_LOGCMD OR LF_PRINT)
        call    Command_Dispatch
        jmp     Main_Menu

PUBPROC error_report
        pop     errMessage
        or      ScreenFlags, SF_OUTP
        mov     ax, K_ESC
        call    Force_Key               ; Stop macros
        jmp     Main_Menu

Cmd_While:
        DBGBRK  3
        jz      short While_End
        mov     edi, OFFSET32 While_Expr
setWhile1:
        lodsb
        cmp     al, ';'
        jne     short setWhile2
        mov     al, K_CR
setWhile2:
        stosb
        cmp     al, 0
        jne     short setWhile1
        dec     edi
        cmp     byte ptr [edi-1], K_CR
        jne     short @f
        dec     edi
@@:     mov     dword ptr [edi+0], 49485700h+K_CR ; K_CR, WHILE, K_CR, 0
        mov     dword ptr [edi+4], 0000454ch+(K_CR SHL 16) ; LE, K_CR, 0

While_End:
        DBGBRK  3
        mov     esi, OFFSET32 While_Expr
        call    Scan_Dword
        test    ebx, ebx
        jz      short @f
        mov     key_macro_ptr, esi
@@:     ret

Cmd_IF: call    Scan_Dword
        test    ebx, ebx
        jnz     short Command_Dispatch
        ret

Cmd_Log:jz      Cmd_VuLog
        call    Parse_Line
        FullCmd 'ON'    ENDOF_LINE <OFFSET32 Cmd_LogOn>
        FullCmd 'OFF'   ENDOF_LINE <OFFSET32 Cmd_LogOff>
        FullCmd 'CLEAR' ENDOF_LINE <OFFSET32 Cmd_LogClear>
        PartCmd ':'     JUMP_ADDRS <OFFSET32 Log_Notes>
        db 0
        ; It should be LOG cmd
        or      Log_Falgs, LF_LOGCMD    ; Log this command
        jmp     short Command_Dispatch
Cmd_Print:
        call    Parse_Line
        FullCmd 'LF'    ENDOF_LINE <OFFSET32 Cmd_PrintLF>
        FullCmd 'FF'    ENDOF_LINE <OFFSET32 Cmd_PrintFF>
        db 0
        or      Log_Falgs, LF_PRINT     ; Print this command
PUBPROC Command_Dispatch
        DBGBRK  3
        call    Parse_Line
        FullCmd 'T'     SCAN_VAL32 <OFFSET32 Cmd_Trace>
        FullCmd 'P'     ENDOF_LINE <OFFSET32 Cmd_Step>
        FullCmd 'TASK'  SKIP_BLANK <OFFSET32 Cmd_Task>
        FullCmd 'TSS'   SCAN_VAL32 <OFFSET32 Cmd_Tss>
IFDEF   _W95_
        PartCmd 'TH'    SCAN_VAL32 <OFFSET32 Cmd_Thread>
ENDIF
        FullCmd 'PDE'   SCAN_VAL32 <OFFSET32 Cmd_Pde>
        FullCmd 'PAGE'  SCAN_VAL32 <OFFSET32 Cmd_Page>
IFDEF   _W95_
        FullCmd 'PS'    SCAN_VAL32 <OFFSET32 Cmd_Process>
ENDIF
        FullCmd 'PC'    CODE_BLOCK <OFFSET32 Cmd_PrintCode>
        FullCmd 'PB'    GOTO_REL16 Cmd_PrntFmt <disp_as_byte2 - disp_as_byte>
        FullCmd 'PW'    GOTO_REL16 Cmd_PrntFmt <disp_as_word2 - disp_as_byte>
        FullCmd 'PD'    GOTO_REL16 Cmd_PrntFmt <disp_as_dword2- disp_as_byte>
        FullCmd 'PA'    GOTO_REL16 Cmd_PrntFmt <disp_as_ascii - disp_as_byte>
        FullCmd 'DB'    GOTO_REL16 Cmd_DataFmt <disp_as_byte - disp_as_byte>
        FullCmd 'DW'    GOTO_REL16 Cmd_DataFmt <disp_as_word - disp_as_byte>
        FullCmd 'DD'    GOTO_REL16 Cmd_DataFmt <disp_as_dword- disp_as_byte>
        FullCmd 'DA'    GOTO_REL16 Cmd_DataFmt <disp_as_ascii- disp_as_byte>
        FullCmd 'DP'    SCAN_VAL32 <OFFSET32 Cmd_DispPhys>
        FullCmd 'DL'    SKIP_BLANK <OFFSET32 Cmd_DispLinear>
        FullCmd 'DI'    SKIP_BLANK <OFFSET32 Cmd_DosInts>
        FullCmd 'DEV'   SKIP_BLANK <OFFSET32 Cmd_DosDevices>
        PartCmd 'DM'    GOTO_REL16 Cmd_GoMarker <PNTR_DATA>
        FullCmd 'D'     SKIP_BLANK <OFFSET32 Cmd_D>
IFDEF   _W95_
        FullCmd 'AC'    SCAN_VAL32 <OFFSET32 Cmd_AddrCntx>
ENDIF
        FullCmd 'ASC'   SCAN_VAL32 <OFFSET32 Cmd_ASC>
        FullCmd 'A'     SKIP_BLANK <OFFSET32 Cmd_A>
        FullCmd 'U'     SKIP_BLANK <OFFSET32 Cmd_U>
        FullCmd 'WHILE' SKIP_BLANK <OFFSET32 Cmd_While>
        FullCmd 'WB'    GOTO_REL16 Cmd_WatchFmt w_bytes
        FullCmd 'WW'    GOTO_REL16 Cmd_WatchFmt w_words
        FullCmd 'WD'    GOTO_REL16 Cmd_WatchFmt w_dwords
        FullCmd 'WA'    GOTO_REL16 Cmd_WatchFmt w_ascii
        FullCmd 'W'     SKIP_BLANK <OFFSET32 Cmd_W>
IFDEF   _W95_
        FullCmd 'MOD32' SKIP_BLANK <OFFSET32 Cmd_Mod32>
ENDIF
        FullCmd 'MOD'   SKIP_BLANK <OFFSET32 Cmd_Mod>
        FullCmd 'MC'    SCAN_VAL32 <OFFSET32 move_codewin>
        FullCmd 'MD'    SCAN_VAL32 <OFFSET32 move_datawin>
        FullCmd 'MAP'   SKIP_BLANK <OFFSET32 Cmd_MapV86Mem>
        FullCmd 'M'     DATA_BLOCK <OFFSET32 Cmd_Move>
        FullCmd 'BIO'   SCAN_VAL32 <OFFSET32 Cmd_IoBreak>
        PartCmd 'BI'    SCAN_VAL32 <OFFSET32 Cmd_IntBreak>
        FullCmd 'NMI'   SKIP_BLANK <OFFSET32 Cmd_NMIBreak>
IFDEF   _W95_
        FullCmd 'BDO'   SKIP_BLANK <OFFSET32 Cmd_DbgOutBreak>
ENDIF
        FullCmd 'BPX'   GOTO_REL16 Cmd_mBreak <000h+256*BRK_ON_EXEC> ;execution
        FullCmd 'BPIO'  GOTO_REL16 Cmd_pBreak <020h+256*BRK_ON_PIO > ;I/O, r/w
        FullCmd 'BPBW'  GOTO_REL16 Cmd_mBreak <010h+256*BRK_ON_BW  > ;byte, write
        FullCmd 'BPB'   GOTO_REL16 Cmd_mBreak <030h+256*BRK_ON_BRW > ;byte, r/w
        FullCmd 'BPWW'  GOTO_REL16 Cmd_mBreak <050h+256*BRK_ON_WW  > ;word, write
        FullCmd 'BPW'   GOTO_REL16 Cmd_mBreak <070h+256*BRK_ON_WRW > ;word, r/w
        FullCmd 'BPDW'  GOTO_REL16 Cmd_mBreak <0d0h+256*BRK_ON_DW  > ;dword, write
        FullCmd 'BPD'   GOTO_REL16 Cmd_mBreak <0f0h+256*BRK_ON_DRW > ;dword, r/w
        FullCmd 'BP'    SKIP_BLANK <OFFSET32 Cmd_CodeBreak>
        FullCmd 'BM'    SKIP_BLANK <OFFSET32 Cmd_ModBreak>
        FullCmd 'BC'    SKIP_BLANK <OFFSET32 Cmd_BreakClear>
        FullCmd 'BE'    SKIP_BLANK <OFFSET32 Cmd_BreakEnable>
        FullCmd 'BD'    SKIP_BLANK <OFFSET32 Cmd_BreakDisable>
        FullCmd 'BL'    ENDOF_LINE <OFFSET32 Cmd_BreakList>
        FullCmd 'BF'    SKIP_BLANK <OFFSET32 Cmd_BF>
        FullCmd 'RESET' ENDOF_LINE <OFFSET32 Cmd_Reset>
        FullCmd 'R'     SKIP_BLANK <OFFSET32 Cmd_R>
        PartCmd 'CM'    GOTO_REL16 Cmd_GoMarker <PNTR_CODE>
        FullCmd 'CAP'   SKIP_BLANK <OFFSET32 Cmd_Capture>
        FullCmd 'C'     DATA_BLOCK <OFFSET32 Cmd_Compare>
        FullCmd 'SET'   SKIP_BLANK <OFFSET32 Cmd_Set>
        FullCmd 'IDT'   SCAN_VAL32 <OFFSET32 Cmd_IDT>
        FullCmd 'LDT'   SCAN_VAL32 <OFFSET32 Cmd_LDT>
        FullCmd 'SYS'   ENDOF_LINE <OFFSET32 Cmd_Sys>
        FullCmd 'END'   SKIP_BLANK <OFFSET32 Cmd_End>
        FullCmd 'E'     SKIP_BLANK <OFFSET32 Cmd_Edit>
        FullCmd 'F'     DATA_BLOCK <OFFSET32 Cmd_Fill>
        FullCmd 'ST'    SKIP_BLANK <OFFSET32 Cmd_Stack>
        FullCmd 'S'     SKIP_BLANK <OFFSET32 Cmd_Search>
        FullCmd 'GC'    ENDOF_LINE <OFFSET32 Cmd_GoClient>
        FullCmd 'GDT'   SCAN_VAL32 <OFFSET32 Cmd_GDT>
        FullCmd 'GF'    ENDOF_LINE <OFFSET32 Cmd_GoFault>
        FullCmd 'G'     SKIP_BLANK <OFFSET32 Cmd_Go>
        FullCmd 'Q'     ENDOF_LINE <OFFSET32 SPWIN_Return>
        FullCmd 'VS'    ENDOF_LINE <OFFSET32 Cmd_VS>
        FullCmd 'IF'    SKIP_BLANK <OFFSET32 Cmd_IF>
        FullCmd 'IW'    SCAN_VAL32 <OFFSET32 Cmd_InWord>
        FullCmd 'ID'    SCAN_VAL32 <OFFSET32 Cmd_InDword>
        FullCmd 'I'     SCAN_VAL32 <OFFSET32 Cmd_InByte>
        FullCmd 'OW'    SCAN_VAL32 <OFFSET32 Cmd_OutWord>
        FullCmd 'OD'    SCAN_VAL32 <OFFSET32 Cmd_OutDword>
        FullCmd 'O'     SCAN_VAL32 <OFFSET32 Cmd_OutByte>
        FullCmd 'VXD'   SKIP_BLANK <OFFSET32 Cmd_VxD>
        FullCmd 'VM'    ENDOF_LINE <OFFSET32 Cmd_VM>
        FullCmd 'HEAP'  SKIP_BLANK <OFFSET32 Cmd_Heap>
        FullCmd 'MSR'   SCAN_VAL32 <OFFSET32 Cmd_MSR>
        FullCmd 'ZAP'   ENDOF_LINE <OFFSET32 Cmd_Zap>
        FullCmd 'H'     SKIP_BLANK <OFFSET32 Cmd_Hex>
        FullCmd '?'     ENDOF_LINE <OFFSET32 Cmd_Help>
IFDEF   _W95_
        FullCmd 'QD'    SKIP_BLANK <OFFSET32 Cmd_QueryVxd>
ENDIF
        FullCmd 'LOG'   SKIP_BLANK <OFFSET32 Cmd_Log>
        FullCmd 'PRINT' SKIP_BLANK <OFFSET32 Cmd_Print>
        db      0
commandError:
        reportError 'Invalid Command.'

Cmd_End:call    Parse_Line
        FullCmd 'TASK' SCAN_VAL32 <OFFSET32 Terminate_Current_Task>
        PartCmd 'VM'   ENDOF_LINE <OFFSET32 Terminate_Current_VM>
        db      0
        jmp     commandError

PUBPROC valueError
        reportError 'Value Error.'
PUBPROC addressError
        reportError 'Address Error.', err_address
PUBPROC syntaxError
        reportError 'Syntax Error.', err_syntax

Cmd_pBreak:
        xchg    eax, ecx                ; save eax
        call    Skip_Blanks
        jz      syntaxError
        xchg    eax, ecx                ; restore eax
Cmd_mBreak:     jmp Cmd_HwBreak

PUBPROC CheckLineEnd
        lodsb
        cmp     al, ' '
        je      CheckLineEnd
        cmp     al, 0
        jne     syntaxError
        ret

Cmd_WatchFmt:
        push    eax
        call    Skip_Blanks
        movzx   ecx, al
        jecxz   short @f
        push    esi
        call    Scan_AddressData
        jc      syntaxError
        pop     esi
        mov     ecx, watchwinsize-2
@@:     pop     eax
        mov     edi, watchwin_ptr
        mov     [edi-1], al                     ;.watchwinType
        rep     movsb
        jmp     registers_then_menu

Cmd_W:  jz      short Next_Watch
        call    Scan_Dword
        cmp     ebx, 8
        jae     short bad_watch_num
        dec     ebx
        mov     watchwin_num, bl
Next_Watch:
        inc     watchwin_num
        and     watchwin_num, 7
        mov     eax, watchwinsize
        mul     watchwin_num
        add     eax, OFFSET32 watchwin1+1
        mov     watchwin_ptr, eax
        jmp     registers_then_menu

bad_watch_num:  
        reportError 'Invalid Watch Number.'

Cmd_PrntFmt:
        add     eax, OFFSET32 disp_as_byte
        jmp     Cmd_PrintData

Cmd_DataFmt:
        add     eax, OFFSET32 disp_as_byte
        mov     datawin_format, eax
        cmp     byte ptr [esi], 0
        je      short datawin_then_menu
set_data_ptr:
        call    Scan_AddressData
        jc      addressError
        cmp     al, 0
        jne     addressError
        mov     Code_Data_Ptrs[PNTR_DATA][4], edx
        mov     Code_Data_Ptrs[PNTR_DATA], ebx
datawin_then_menu:
        mov     al, SF_DATA
        jmp     Update_Screen

Cmd_D:  jnz     short set_data_ptr
scroll_data_page:
        mov     ebx, 4
move_datawin:   
        test    ebx, ebx
        jnz     short move_data1
        inc     ebx
move_data1:     
        mov     eax, datawin_format
        movzx   eax, byte ptr [eax]     ;bytes per line
        imul    ebx
        add     Code_Data_Ptrs[PNTR_DATA], eax
        jmp     datawin_then_menu

Cmd_U:  mov     ebx, code_win_end
        jz      short @f
        call    Scan_AddressCode
        jc      addressError
        cmp     al, 0
        jne     addressError
        mov     Code_Data_Ptrs[PNTR_CODE][4], edx
@@:     mov     Code_Data_Ptrs[PNTR_CODE], ebx
        jmp     codewin_then_menu

move_codewin:
        mov     ecx, ebx
        jecxz   short move_dn_code2
        test    ecx, ecx
        js      short move_up_code1
        push    ecx
        call    CodeWinDown
        mov     Code_Data_Ptrs[PNTR_CODE], ebx
move_dn_code2:
        jmp     codewin_then_menu

move_up_code1:
        neg     ebx
        mov     ecx, ebx
move_up_code2:
        push    ecx
        call    CodeWinUp
        pop     ecx
        loop    short move_up_code2
        jmp     codewin_then_menu

; In:   [esp+4] = number of lines
PUBPROC CodeWinDown
        mov     ebx, Code_Data_Ptrs[PNTR_CODE][0]
CodeWinDownEbx:
        mov     eax, Code_Data_Ptrs[PNTR_CODE][4]
        mov     actual_IP, ebx          ; used by dispins
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
code_dn1:
        call    dispins
        dec     dword ptr [esp+4]       ; number of lines
        jnz     short code_dn1
        mov     ebx, actual_IP
        ret     4

PUBPROC CodeWinUp
        mov     eax, Code_Data_Ptrs[PNTR_CODE][4]
        mov     ebx, Code_Data_Ptrs[PNTR_CODE]
        mov     actual_IP, ebx          ; used by dispins
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        push    ebx
        sub     ebx, 30h
        sub     actual_IP, 30h
        jae     short CodeWinUp1
        sub     ebx, actual_IP
        mov     actual_IP, 0
CodeWinUp1:
        push    ebx
        call    dispins
        pop     eax
        cmp     ebx, [esp]
        jb      short CodeWinUp1
        pop     ebx
        sub     ebx, eax
        sub     Code_Data_Ptrs[PNTR_CODE], ebx
        ret

Cmd_Edit:
        DBGBRK  3
        mov     ebx, Code_Data_Ptrs[PNTR_DATA][0]
        mov     edx, Code_Data_Ptrs[PNTR_DATA][4]
        jz      short @f
        call    Scan_AddressDef
        jc      addressError
@@:     push    edx
        push    ebx

        mov     eax, edx
        push    esi
        call    Get_FlatAddress   ;edx=limit, eax=base, ebx=linear address
        pop     esi
        jc      addressError
        pop     Code_Data_Ptrs[PNTR_DATA][0]
        pop     Code_Data_Ptrs[PNTR_DATA][4]

        call    Scan_String
        jmp     Display_AllWindows

Cmd_Search:
        DBGBRK  3
        jz      short search_memry1     ; next
        call    Scan_BlockData
        ; edx:ebx = address, ecx=size
        mov     searchAddress[0], ebx
        mov     searchAddress[4], edx
        mov     searchLength, ecx
        mov     ebx, OFFSET32 searchBuffer
        call    Scan_String
        sub     ebx, OFFSET32 searchBuffer+1
        jc      syntaxError
        mov     searchBufLen, bl
        call    CheckLineEnd

search_memry1:  
        mov     ebx, searchAddress[0]
        mov     eax, searchAddress[4]
        call    Get_FlatAddress   ;edx=limit, eax=base, ebx=linear address
        jc      addressError

        ; ebx=address of memory to seach
        mov     edx, searchLength       ;length
search_memry2:
        test    edx, edx
        jz      short search_failed
        mov     esi, OFFSET32 searchBuffer ;string to find
        mov     ah, searchBufLen
        call    find_string
        DBGBRK  3
        jc      short search_memry3     ;if not present page
        jne     short search_memry2

        mov     esi, OFFSET32 searchAddress
        mov     [esi], ebx              ;new offset
        mov     [OFFSET searchLength - OFFSET searchAddress][esi], edx
        mov     edi, OFFSET32 Code_Data_Ptrs[PNTR_DATA]
        lodsd
        dec     eax                     ;back to first byte
        stosd
        movsd
        jmp     datawin_then_menu

search_memry3:
        lea     eax, [ebx+1000h]        ;skip the NP page
        and     eax, not 0fffh
        sub     eax, ebx                ;bytes to skip
        add     ebx, eax
        sub     edx, eax
        ja      search_memry2

search_failed:  
        reportError 'No Match Found.'

Cmd_Move:       ; edx:ebx = address, ecx=size
        DBGBRK  3
        call    Get_2Blocks
        cmp     esi, edi
        jae     short move_mem1
        add     esi, ecx
        add     edi, ecx
        dec     esi
        dec     edi
        std
move_mem1:      
        call    rep_movsb
        cld
        jnc     Display_AllWindows
PUBPROC write_Error
        reportError 'Write Error.'

Cmd_Fill:       ; edx:ebx = address, ecx=size
        DBGBRK  3
        xchg    eax, edx
        push    esi
        call    Get_FlatAddress   ;edx=limit, eax=base, ebx=linear address
        pop     esi
        jc      addressError

        push    ebx
        push    ecx
        call    Scan_String
        call    CheckLineEnd
        pop     ecx
        pop     esi
        mov     edi, ebx
        add     ecx, esi                ;end of block
        sub     ecx, edi                ;length of block to dup
        ja      move_mem1
        jmp     Display_AllWindows

Walk_Compare:
        lodsd
        xchg    ecx, eax
        lodsd
        xchg    edi, eax
        lodsd
        xchg    esi, eax
wlk_mem1:
        jecxz   short wlk_mem3
        call    repe_cmpsb
        jbe     short wlk_mem3
wlk_mem2:
        dec     edx
        jnz     short wlk_mem1
wlk_mem3:
        ret

Cmd_Compare:    ; edx:ebx = address, ecx=size
        DBGBRK  3
        call    Get_2Blocks

        push    esi
        push    edi
        push    ecx
        mov     esi, esp                ;esp -> len, dest, src
        mov     ebx, esi
        xor     edx, edx
        call    Walk_Compare
        neg     edx
        jz      Main_Menu
        push    ebx                     ;sl_context
        push    edx                     ;sl_limit
        push    0                       ;sl_index

        mov     eax, [ebx]              ;asked len
        sub     eax, ecx                ;actual length
        push    eax                     ;len
        push    block2[0]
        push    block2[4]
        push    block1[0]
        push    block1[4]
        call    scrollLines
        db      ' Comparing: ',d_h48,'  with: ',d_h48,'  Len: ',d_h32
        db      d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        inc     edx
        mov     ebx, esi                ;points to: len, dest, src
        call    Walk_Compare

        dec     edi
        mov     dl, [edi]
        sub     edi, [ebx+4]            ;
        add     edi, block2[0]

        push    edx                     ;d_chr
        push    edx                     ;d_h08
        push    edi                     ;offset
        push    block2[4]               ;segment

        dec     esi
        mov     al, [esi]
        sub     esi, [ebx+8]            ;
        add     esi, block1[0]

        push    eax                     ;d_chr
        push    eax                     ;d_h08
        push    esi                     ;offset
        push    block1[4]               ;segment
        call    Printf
        db      ' '
        db      d_h48,'  ',d_h08,'  [',d_chr,']',d_spc,4
        db      d_h48,'  ',d_h08,'  [',d_chr,']'
        db      d_ret
        ret

Get_2Blocks:
        DBGBRK  3
        ; edx:ebx = address, ecx=size, esi=cmd line
        mov     eax, edx        ;keep edx as default dest selector
        push    ecx             ;block size
        push    esi
        mov     block1[0], ebx
        mov     block1[4], eax
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      addressError

        pop     esi
        push    ebx             ;source flat address
        call    Scan_AddressData
        jc      addressError
        call    CheckLineEnd
        xchg    eax, edx
        mov     block2[0], ebx
        mov     block2[4], eax
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      addressError
        mov     edi, ebx
        pop     esi             ;block address
        pop     ecx
        ret

selectorTypes   db  11
        db  '           ' ; xxx00000 reserved
        db  '286TSS     ' ; PLL00001 available 286 TSS segment
        db  'LDT        ' ; PLL00010 LDT segment
        db  '286TSS,B   ' ; PLL00011 busy 286 TSS segment
        db  '286CallGate' ; PLL00100 286 call gate
        db  '286TaskGate' ; PLL00101 286 task gate
        db  '286TarpGate' ; PLL00110 286 trap gate
        db  '286IntrGate' ; PLL00111 286 interrupt gate
        db  '           ' ; xxx01000 reserved
        db  '386TSS     ' ; PLL01001 available 386 TSS segment
        db  '           ' ; xxx01010 reserved
        db  '386TSS,B   ' ; PLL01011 busy 386 TSS segment
        db  '386CallGate' ; PLL01100 386 call gate
        db  '           ' ; xxx01101 reserved
        db  '386TrapGate' ; PLL01110 386 task gate
        db  '386IntrGate' ; PLL01111 386 interrupt gate
                          ; PLL10EWA data segment
        db  'Data RO    ' ; PLL10000 data, Read-Only
        db  'DATA RO    ' ; PLL10001 data, Read-Only, Accessed
        db  'Data RW    ' ; PLL10010 data, R/W
        db  'DATA RW    ' ; PLL10011 data, R/W, Accessed
        db  'Data RO,XD ' ; PLL10100 data, Read-Only, Expand Down
        db  'DATA RO,XD ' ; PLL10101 data, Read-Only, Expand Down, Accessed
        db  'Data RW,XD ' ; PLL10110 data, R/W, Expand Down
        db  'DATA RW,XD ' ; PLL10111 data, R/W, Expand Down, Accessed
                          ; PLL11CRA code segment
        db  'Code XO    ' ; PLL10000 code, Exec-Only
        db  'CODE XO    ' ; PLL10001 code, Exec-Only, Accessed
        db  'Code XR    ' ; PLL10010 code, X/R
        db  'CODE XR    ' ; PLL10011 code, X/R, Accessed
        db  'Code XO,C  ' ; PLL10100 code, Exec-Only, Conforming
        db  'CODE XO,C  ' ; PLL10101 code, Exec-Only, Conforming, Accessed
        db  'Code XR,C  ' ; PLL10110 code, X/R, Conforming
        db  'CODE XR,C  ' ; PLL10111 code, X/R, Conforming, Accessed

no_ldt: reportError 'No LDT.'

Cmd_LDT:sldt    ax
        mov     ecx, eax
        call    Get_Selector
        jc      no_ldt
        ; eax=base, edx=limit, esi=&descriptor

        lea     esi, 1[edx]
        shr     esi, 3                  ;LDT end
        shr     ebx, 3                  ;index
        cmp     ebx, esi
        jb      short @f
        xor     ebx, ebx
@@:     push    eax                     ;base     (sl_context)
        push    esi                     ;total    (sl_limit)
        push    ebx                     ;index    (sl_Index)

        push    edx                     ;limit
        push    eax                     ;base
        push    ecx                     ;LDT selector
        call    scrollLines
        db      'LDT: SELECTOR=',d_h16
        db      '  BASE=', d_h32,'  LIMIT=', d_h32
        db      d_lf,'SELECTOR  BASE      LIMIT    DPL SIZE'
        db      d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        lea     esi, [esi+edx*8]
        mov     al, ds:[esi].AccessRights
        mov     ah, ds:[esi].Granularity
        mov     cl, ah
        and     ecx, 0fh        ; Limit_16_19
        shl     ecx, 16
        mov     cx, ds:[esi].Limit_0_15
        test    ah, 80h
        jz      short disp_ldt1
        shl     ecx, 12
        or      cx, 0fffh
disp_ldt1:      
        mov     bl, ds:[esi].Base_16_23
        mov     bh, ds:[esi].Base_24_31
        shl     ebx, 16
        mov     bx, ds:[esi].Base_0_15
        test    ax, ax
        jnz     short disp_ldt3
        push    ecx             ; limits
        push    ebx             ; base
        lea     eax, 4[edx*8]
        push    eax             ; selector
        call    Printf
        db      '  ',d_h16,d_spc,4,d_h32,'  ',d_h32
        db      d_spc,11,'NOT IN USE',d_ret
        ret
disp_ldt3:      
        mov     esi, eax        ; rights
        and     eax, 1fh
        push    eax             ;_table selectorTypes
        push    esi             ; rights
        push    0               ; a_b masks
        shr     esi, 5
        and     esi, 3          ; DPL
        push    esi             ; DPL
        push    ecx             ; limits
        push    ebx             ; base
        lea     edx, 4[esi+edx*8]
        push    edx             ; selector
        call    Printf
        db      '  ',d_h16,d_spc,4,d_h32,'  ',d_h32
        db      '  ',d_h04,'  '
               ;fedcba9876543210
               ;G10ullllPLLTxxxx
        _bits   1000000010000000b,3,'16 32 NP P  '
        _table  selectorTypes
        db      '  ',d_ret
        xor     ebx, ebx        ; edx:ebx=address
        jmp     SectionNameFromAddress

Cmd_GDT:shr     ebx, 3
        push    edx
        push    edi
        sgdt    fword ptr [esp+2]
        pop     edi
        pop     edx                     ;edx=base for GDT
        shr     edi, 16                 ;edi=gdtLimit

        lea     esi, 1[edi]
        shr     esi, 3                  ;GDT end
        cmp     ebx, esi
        jb      short @f
        xor     ebx, ebx
@@:     push    edx                     ;base     (sl_context)
        push    esi                     ;total    (sl_limit)
        push    ebx                     ;index    (sl_Index)

        push    edi                     ;limit
        push    edx                     ;base
        call    scrollLines
        db      'GDT:',d_spc,6,'BASE=', d_h32,'  LIMIT=', d_h16
        db      d_lf,'SELECTOR  BASE',d_spc,6,'LIMIT',d_spc,4,'DPL SIZE',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        lea     esi, [esi+edx*8]
        mov     bl, ds:[esi].Base_16_23
        mov     bh, ds:[esi].Base_24_31
        shl     ebx, 16
        mov     bx, ds:[esi].Base_0_15
        mov     al, ds:[esi].AccessRights
        mov     ah, ds:[esi].Granularity
        mov     cl, ah
        and     ecx, 0fh        ; Limit_16_19
        shl     ecx, 16
        mov     cx, ds:[esi].Limit_0_15
        test    ah, 80h
        jz      short disp_gdt2
        shl     ecx, 12
        or      cx, 0fffh
disp_gdt2:      
        test    ax, ax
        jnz     short disp_gdt3
        lea     eax, [edx*8]
        push    ecx             ; limits
        push    ebx             ; base
        push    eax             ; selector
        call    Printf
        db      '  ',d_h16,'    ',d_h32,'  ',d_h32
        db      '           NOT IN USE',d_ret
        ret
disp_gdt3:      
        mov     esi, eax        ; rights
        and     eax, 1fh
        push    eax             ;_table selectorTypes
        push    esi             ; rights
        push    0               ; a_b masks
        shr     esi, 5
        and     esi, 3          ; DPL
        push    esi             ; DPL
        push    ecx             ; limits
        push    ebx             ; base
        lea     esi, [esi+edx*8]
        push    esi             ; selector
        call    Printf
        db      '  ',d_h16,'    ',d_h32,'  ',d_h32
        db      '  ',d_h04,'  '
               ;fedcba9876543210
               ;G10ullllPLLTxxxx
        _bits   1000000010000000b,3,'16 32 NP P  '
        _table  selectorTypes
        db      d_ret
        ret

Cmd_IDT:
        DBGBRK  5
        push    edx
        push    edi
        sidt    fword ptr [esp+2]
        pop     edi
        pop     edx             ; idtBase
        shr     edi, 16         ; idtLimit
        lea     esi, 1[edi]
        shr     esi, 3          ; top of IDT
        cmp     ebx, esi
        jb      short @f
        xor     ebx, ebx
@@:     push    edx             ; IDTBase        (sl_context)
        push    esi             ; last int#      (sl_limit)
        push    ebx             ; int#           (sl_Index)

        push    edi
        push    edx
        call    scrollLines
        db      'IDT:BASE=', d_h32,'  LIMIT=', d_h16
        db      d_lf,'INT#',d_spc,4,'DPL  TYPE',d_spc,9,'ADDRESS',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        lea     esi, [esi+edx*8]
        mov     cx, ds:[esi].IV_Offset_16_31
        shl     ecx, 16
        mov     cx, ds:[esi].IV_Offset_0_15
        mov     bh, ds:[esi].IV_Access
        movzx   esi, ds:[esi].IV_Selector

        mov     al, bh
        mov     bl, 01100000b   ; pLLxxxxx
        and     bl, bh          ; DPL
        shr     bl, 5
        and     al, 1fh         ; type
        cmp     al, 05h
        je      short disp_taskGate
        cmp     al, 06h         ; 286IntGate
        je      short disp_intrGate
        cmp     al, 0eh         ; 386IntGate
        je      short disp_intrGate
        cmp     al, 07h         ; 286TrapGate
        je      disp_trapGate
        cmp     al, 0fh         ; 386TrapGate
        je      disp_trapGate
        push    ecx             ; offset
        push    esi             ; selector
        push    eax             ; type
        push    ebx             ; DPL
        push    ebx             ; type (for P-bit)
        push    0               ; a_b masks
        push    edx             ; int#
        call    Printf
        db      ' ',d_h08,'  '
               ;PLLxxxxxxxxxxxxx
        _bits   8000h,1,'N P'
        db      '  ',d_h04,d_spc,3,d_h08,d_spc,11,d_h48,d_ret
        ret

disp_taskGate:  
        push    esi             ; selector
        push    ebx             ; DPL
        push    ebx             ; type (for P-bit)
        push    0               ; a_b masks
        push    edx             ; int#
        call    Printf
        db      ' ',d_h08,'  '
               ;PLLxxxxx
        _bits   8000h,1,'N P'
        db      '  ',d_h04,'   386TaskGate  TSS=',d_h16,d_ret
        ret

disp_intrGate:  
        push    ecx             ; offset
        push    esi             ; selector
        cmp     al, 8           ; 6=286/E=386
        mov     al, '3'
        sbb     al, 0
        push    eax
        push    ebx             ; DPL
        push    ebx             ; type (for P-bit)
        push    0               ; a_b masks
        push    edx             ; int#
        call    Printf
        db      ' ',d_h08,'  '
               ;PLLxxxxx
        _bits   8000h,1,'N P'
        db      '  ',d_h04,'   ',d_h04,'86IntGate   ',d_h48,d_ret
        ret

disp_trapGate:  
        push    ecx             ; offset
        push    esi             ; selector
        cmp     al, 8           ; 7=286/F=386
        mov     al, '3'
        sbb     al, 0
        push    eax
        push    ebx             ; DPL
        push    ebx             ; type (for P-bit)
        push    0               ; a_b masks
        push    edx             ; int#
        call    Printf
        db      ' ',d_h08,'  '
               ;PLLxxxxx
        _bits   8000h,1,'N P'
        db      '  ',d_h04,'   ',d_h04,'86TrapGate  ',d_h48,d_ret
        ret

Walk_VMs:
        VMMcall Get_Sys_VM_Handle
        push    ebx
walk_vm1:
        dec     ecx
        jz      short walk_vm2
        VMMcall Get_Next_VM_Handle
        VMMcall Test_Sys_VM_handle
        jne     short walk_vm1
walk_vm2:
        pop     eax
        ret

Cmd_VM:
        DBGBRK  3
        xor     ecx, ecx
        call    Walk_VMs
        neg     ecx
        push    ecx                     ;sl_limit
        push    0                       ;sl_index

        push    eax                     ;SYS VM
        VMMcall Get_Cur_VM_Handle
        push    ebx
        call    scrollLines
        db      ' Current VM=',d_h32,'  SYS VM=',d_h32,d_lf
        db      ' VM Handle  VM ID     Status   High Lin  Client',d_sub
                ; --------  --------  --------  --------  -------------
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        DBGBRK  3
        inc     ecx
        call    Walk_VMs
        ; ebx=VM handle
        mov     eax, CB_Client_Pointer[ebx]
        bt      [eax].Client_EFlags[2], 1
        sbb     ecx, ecx
        mov     cx, [eax].Client_CS
        push    [eax].Client_EIP
        push    ecx
        push    CB_High_Linear[ebx]
        push    CB_VM_Status[ebx]
        push    CB_VMID[ebx]
        push    ebx
        call    Printf
        db      ' ',d_h32,'  ',d_h32,'  ',d_h32,'  ',d_h32,'  ',d_h48,d_ret
        ret

Cmd_Pde:
        jnc     short @f
        xor     ebx, ebx
@@:     mov     eax, CR3
        add     eax, Physical_Bias
        ; eax = linear address
        shr     ebx, 22         ;directory part
        push    eax             ;PDE    -> esi  (sl_context)
        push    400h            ;max dirs       (sl_limit)
        push    ebx             ;index  -> edx  (sl_Index)

        push    eax             ; CR3
        call    scrollLines
        db      '  Linear Address  PageTable  Attributes'
        db      '   Directory Base=',d_h32,d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
PUBPROC Display_PDE
        call    Read_dwIndex_EDX
        shl     edx, 22                 ; linear address base
        lea     ecx, [edx+3fffffh]      ; linear address end
        test    al, 1                   ; present?
        jnz     short disp_dirs
        push    eax
        push    ecx
        push    edx
        call    Printf
        db      d_h32,'-',d_h32,'  ',d_h32,'  Not present',d_ret
        ret

disp_dirs:
        push    eax                     ; attributes
        push    0                       ; a_b masks
        and     eax, not 0fffh          ; page frame address
        push    eax
        push    ecx
        push    edx
        call    Printf
        db      d_h32,'-',d_h32,'  ',d_h32,'  '
               ;6543210
               ;DA..SWP     --==--==--==--==
        _bits   1100110b,2,'  D   A U S R W '
        db      'P',d_ret
        ret

Cmd_Page:
        jnc     short @f
        xor     ebx, ebx
@@:     mov     eax, CR3
        add     eax, Physical_Bias
        ; eax = linear address
        shr     ebx, 12                 ; dir|index
        push    eax                     ; start  -> esi
        push    100000h                 ; max 20-bits
        push    ebx                     ; index  -> edx

        push    eax                     ; CR3
        call    scrollLines
        db      ' Directory Base=',d_h32,d_lf
        db      ' Linear Address      PDE       PTE     Physical  Attributes'
        ;        00000000-00000000  00000000  00000000  00000000
        db      d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        push    edx                     ; save
        mov     ebx, edx
        shr     edx, 10                 ; index to PDE
        lea     esi, [esi+edx*4]        ; directory entry
        call    dword_read_@esi
        xchg    edx, eax
        shl     ebx, 12                 ; linear address
        lea     ecx, [ebx+0fffh]        ; end of page

        push    edx                     ; PDE
        push    ecx
        push    ebx
        call    Printf
        db      d_h32,'-',d_h32,'  ',d_h32,'  ',d_ret

        pop     esi
        test    dl, 1
        jnz     short disp_pag2

disp_pag1:
        call    PrintfAt
        db      'NOT PRESENT',d_ret
        ret

disp_pag2:
        and     edx, not 0fffh          ; page table address
        add     edx, Physical_Bias
        ; edx = linear address of the PTE
        and     esi, 03ffh              ; index to PTE
        lea     esi, [edx+esi*4]
        call    dword_read_@esi
        xchg    edx, eax

        push    edx                     ; PTE
        call    PrintfAt
        db      d_h32,'  ',d_ret

        test    dl, 1
        jz      short disp_pag1

        push    edx                     ; attributes
        push    0                       ; a_b masks
        and     edx, not 0fffh          ; page frame address
        push    edx                     ; physical address
        call    PrintfAt
        db      d_h32,'  '
               ;6543210
               ;DACTSWP     --==--==--==--==--==--==
        _bits   1111110b,2,'  D   A C     T U S R W '
        db      'P',d_ret
        ret

Cmd_DispPhys:
        jnc     short @f
        xor     ebx, ebx
@@:     and     ebx, 00fffff0h
        mov     eax, DosInfo.PhyMemSize
        shr     eax, 4
        push    eax                     ;sl_limit
;;      push    01000000h SHR 4         ;sl_limit (16M)
        shr     ebx, 4
        push    ebx                     ;sl_Index
        call    scrollLines
        db      'Physical Memory',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        imul    ebx, ecx, 16
        push    ebx
        add     ebx, Physical_Bias      ;linear address
        call    Printf
        db      d_h32,4 dup('  ',d_mem,DM_BYTE+4),'   '
        _jsr    Sub_Ebx_16
        db      d_mem,DM_ASCI+16,d_ret
        ret

Cmd_DispLinear:
        mov     ebx, Code_Data_Ptrs[PNTR_DATA][0]
        mov     edx, Code_Data_Ptrs[PNTR_DATA][4]
        jz      short @f
        call    Scan_AddressDef
        jc      addressError
@@:     push    edx
        push    ebx

        xchg    eax, edx
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      addressError
        pop     edi                     ;offset
        pop     esi                     ;segment

        mov     edx, ebx
        and     edx, 0fh
        push    edx                     ;sl_context
        push    10000000h               ;sl_limit
        mov     eax, ebx
        shr     eax, 4
        push    eax                     ;sl_Index

        push    ebx
        push    edi
        push    esi
        call    scrollLines
        db      'Address: ',d_h48,'  Linear=',d_h32,d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        shl     ecx, 4
        lea     ebx, [ecx+esi]
        push    ebx
        mov     Address_Limit, -1
        call    Printf
        db      d_h32,4 dup('  ',d_mem,DM_BYTE+4),'   '
        _jsr    Sub_Ebx_16
        db      d_mem,DM_ASCI+16,d_ret
        ret

Cmd_VS:
        call    Usr_Screen
        call    key_read
        call    SPW_Screen
        jmp     Display_AllWindows

Cmd_InByte:
        jc      syntaxError
        mov     edx, ebx
        in      al, dx
        push    eax
        push    edx
        call    PrintfMainScr
        db      d_lf,'IN(',d_h16,') => ',d_h08,d_el
        ret

Cmd_InWord:
        jc      syntaxError
        mov     edx, ebx
        in      ax, dx
        push    eax
        push    edx
        call    PrintfMainScr
        db      d_lf,'IN(',d_h16,') => ',d_h16,d_el
        ret

Cmd_InDword:
        jc      syntaxError
        mov     edx, ebx
        in      eax, dx
        push    eax
        push    edx
        call    PrintfMainScr
        db      d_lf,'IN(',d_h16,') => ',d_h32,d_el
        ret

Cmd_OutByte:
        jc      syntaxError
        mov     edx, ebx
        call    Scan_Dword
        xchg    eax, ebx
        out     dx, al
        ret

Cmd_OutWord:
        jc      syntaxError
        mov     edx, ebx
        call    Scan_Dword
        xchg    eax, ebx
        out     dx, ax
        ret

Cmd_OutDword:
        jc      syntaxError
        mov     edx, ebx
        call    Scan_Dword
        xchg    eax, ebx
        out     dx, eax
        ret

Cmd_A:  mov     ebx, Code_Data_Ptrs[PNTR_CODE][0]
        jz      short asm_l1
        call    Scan_AddressCode
        jc      addressError
        cmp     al, 0
        jne     addressError
        mov     Code_Data_Ptrs[PNTR_CODE][4], edx
        mov     Code_Data_Ptrs[PNTR_CODE][0], ebx
asm_l1: push    ebx
        call    Display_Output
        call    Display_RegWindow
        jmp     short asm_l3

asm_l2: push    1                       ; 1 line
        call    CodeWinDown
        ; ebx=offset next inst
        mov     Code_Data_Ptrs[PNTR_CODE][0], ebx
asm_l3: call    Display_DataWindow
        call    Display_CodeWindow
;       mov     eax, code_win_end
        cmp     [esp], eax
        jae     asm_l2

        DBGBRK  4
        mov     byte ptr cmd_buffer[0], 0
asm_l4: mov     ebx, [esp]
        mov     eax, Code_Data_Ptrs[PNTR_CODE][4]
        push    ebx             ;for Printf
        push    eax             ;for Printf
        call    Get_FlatAddress ;edx=limit, eax=base, ebx=linear address
        jc      addressError

        call    Printf
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,' ',d_h48,' [',d_el

        DBGBRK  4
        push    ebx                     ; save linear address for rep_movsb
        push    OFFSET32 key_read       ; key input proc/filter
        push    OFFSET32 cmd_buffer     ; buffer for data
        push    63                      ; max number of chars
        push    16                      ; string col number
        call    Edit_Text
        db      d_row, POS_WINDOW + _CMDLINE_
        db      a_r,d_col,16,d_text,t_fill+63,']',d_sub
        pop     ebx                     ; linear address

        DBGBRK  4
        cmp     byte ptr [esi], 0
        je      short asm_l5
        push    ebx
        push    ebp
        mov     ebp, [esp+8]            ; esp+0 = saved ebp
                                        ; esp+4 = linear address
                                        ; esp+8 = inst offset
        call    Assemble

        DBGBRK  4
        pop     ebp
        pop     ecx                     ; linear address
        jc      short asm_error
        xchg    ecx, edi
        sub     ecx, esi
        call    rep_movsb
        jc      short writeError

asm_l5: pop     ebx                     ; offset
        push    1                       ; 1 line
        call    CodeWinDownEbx          ; ebx=offset
                                        ; ebx=offset next inst
        push    ebx
        jmp     asm_l3

asm_error:
        mov     ebx, OFFSET32 cmd_buffer ; buffer for data
        call    Printf
        db      d_lf,'Syntax error "',d_text,63,'".',d_el
        jmp     asm_l4

writeError:
        reportError 'Cannot Write Here.'

Cmd_GoMarker:
        DBGBRK  3
        push    eax
        call    Scan_Decimal
        jc      commandError
        cmp     ebx, 10
        jae     commandError
        call    CheckLineEnd
        pop     eax
        lea     edi, Code_Data_Ptrs[eax]
        lea     esi, [edi+ebx*8+8]
        movsd
        movsd
        jmp     Display_AllWindows

PUBBYTE ON_OFF_Table <3,'OFFON '>

Log_Notes:
        DBGBRK  3
        dec     esi
        mov     byte ptr [esi], s_lf    ; force a new line
        call    Log_AppendToLog
        jmp     Main_Menu

IFDEF   _W95_
Cmd_DbgOutBreak:
        xor     ecx, ecx
        call    Parse_Line
        FullCmd 'ON'   JUMP_ADDRS  <OFFSET32 Enable_DOB>
        FullCmd 'OFF'  JUMP_ADDRS  <OFFSET32 Disable_DOB>
        db 0
        btc     dword ptr DebugOutFlags, ecx
        bt      dword ptr DebugOutFlags, ecx
        setc    al
        push    eax
        call    PrintfMainScr
        db      d_lf,'Debug Out Break Is Now '
        _table  ON_OFF_Table
        db      d_el
        ret
Enable_DOB:
        bts     dword ptr DebugOutFlags, ecx
        ret
Disable_DOB:
        btr     dword ptr DebugOutFlags, ecx
        ret
ENDIF

LCODE_ENDS
END

