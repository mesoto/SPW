page    60,132  

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

VER_STR equ <"1.00">
VER_MAJ equ 1
VER_MIN equ 0

DBGBRK  MACRO   level, bnum
  IF DBG GE level
    IFB <bnum>
        int 1
    ELSE
        int bnum
    ENDIF
  ENDIF
        ENDM

IFNDEF  _16BIT_
.386p
.XLIST
INCLUDE VMM.Inc
INCLUDE Debug.Inc
.LIST

CHKPNT  macro   x, p
  IF    DBG
        @@chr1 = x AND 0ffh
        @@chr2 = (x SHR 8) AND 0ffh
        @@chr  = @@chr1*10000h + @@chr2
    IFB <p>
        @@pos  = 0b009ch
    ELSE
        @@pos  = 0b0000h + p
    ENDIF
        mov     dword ptr ss:[@@pos], 8f008f00h+@@chr
  ENDIF
        endm

; Define safe code segment
IFDEF   _W95_
_SAFECODE SEGMENT DWORD USE32 PUBLIC 'LCODE'
_SAFECODE ENDS
  IFNDEF  BLD_COFF
_LGROUP   GROUP _SAFECODE, _LTEXT, _TEXT, _LDATA, _DATA, _BSS, CONST, _TLS
  ENDIF
ELSE
_SAFECODE SEGMENT DWORD USE32 PUBLIC 'CODE'
_SAFECODE ENDS
_LGROUP   GROUP _SAFECODE, _LTEXT, _LDATA
ENDIF

REAL_INIT_SEG   macro
                VxD_REAL_INIT_SEG
                endm

REAL_INIT_ENDS  macro
                VxD_REAL_INIT_ENDS
                endm

ICODE_SEG       macro
                VxD_ICODE_SEG
                endm

ICODE_ENDS      macro
                VxD_ICODE_ENDS
                endm

IDATA_SEG       macro
                VxD_IDATA_SEG
                endm

IDATA_ENDS      macro
                VxD_IDATA_ENDS
                endm

;   Protected mode initialization code
SCODE_SEG       macro
_SAFECODE       SEGMENT
                ASSUME  cs:FLAT, ds:FLAT, es:FLAT, ss:FLAT
                ENDM

SCODE_ENDS      macro
_SAFECODE       ENDS
                ENDM

LCODE_SEG       macro
                VxD_LOCKED_CODE_SEG
                endm

LCODE_ENDS      macro
                VxD_LOCKED_CODE_ENDS
                endm

LDATA_SEG       macro   ALIGNMENT
                VxD_LOCKED_DATA_SEG
                endm

LDATA_ENDS      macro
                VxD_LOCKED_DATA_ENDS
                endm

; ---------------------------------------------------------------------------

PUBBYTE         macro   pname, val
                public  pname
        ifb     <val>
                pname   db  ?
        else
          ifidn <val>, <here>
                pname   label byte
          else
                pname   db  val
          endif
        endif
                endm

PUBWORD         macro   pname, val
                public  pname
        ifb     <val>
                pname   dw  ?
        else
          ifidn <val>, <here>
                pname   label word
          else
                pname   dw  val
          endif
        endif
                endm

PUBDWRD         macro   pname, val
                public  pname
        ifb     <val>
                pname   dd  ?
        else
          ifidn <val>, <here>
                pname   label dword
          else
                pname   dd  val
          endif
        endif
                endm

PUBPROC         macro   pname
                public  pname
                pname   label near
                endm

MIN_STK_SIZE    equ 100h        ; local stack size

userStateStruc  struc
R_ESP    dd ? ;
R_SS     dd ? ;
R_ES     dd ? ;
R_DS     dd ? ;
R_FS     dd ? ;
R_GS     dd ? ;
R_EDI    dd ? ;0
R_ESI    dd ? ;4
R_EBP    dd ? ;8
R_CR2    dd ? ;12 DummyESP
R_EBX    dd ? ;16
R_EDX    dd ? ;20
R_ECX    dd ? ;24
R_EAX    dd ? ;28
R_BrkMsg dd ? ;ptr break message
R_Fault  dd ? ;
R_EIP    dd ? ;
R_CS     dd ? ;
R_EFLAGS dd ? ;
;   Ring transition info
RingESP  dd ? ;
RingSS   dd ? ;
userStateStruc  ends

EXTBYTE MACRO   module, name
        IFNDEF  module
        extrn   name:byte
        ENDIF
        endm

EXTWORD MACRO   module, name
        IFNDEF  module
        extrn   name:word
        ENDIF
        endm

EXTDWRD MACRO   module, name
        IFNDEF  module
        extrn   name:dword
        ENDIF
        endm

EXTPROC MACRO   module, name
        IFNDEF  module
        extrn   name:near
        ENDIF
        endm

BreakInfoStru   struc ; INT3      BIO         BInt        DRx/CAP
 brk_Flags      db 0  ; flags     flags       flags       flags
 brk_TypeInfo   db 0  ; _INT3     _IO/_CAP    _INT        _DR|reg no.
 brk_StateInfo  db 0  ; org inst  tss.io      int#        dr7value
 brk_LinAddress dd 0  ; linear    port#       vector      port/addr
IFDEF   _W95_
 brk_MemContext dd 0  ; context
ENDIF
 brk_Address    dd 0  ; offset    port no.    V86 vector  offset
                dd 0  ; segment   cap index   V86 vector  segment
 brk_MaxCount   dw 1  ; count     count       count       count
 brk_Counter    dw 1  ; counter   counter     counter     counter
 brk_Condition  db 31 dup(0)
                db 0  ;
BreakInfoStru   ends

brk_I3OrgInst   equ brk_StateInfo
brk_TssIoState  equ brk_StateInfo
brk_DR7Value    equ brk_StateInfo
brk_IntNumber   equ brk_StateInfo
brk_IntVector   equ brk_Address
brk_ModuleName  equ brk_Condition[1]    ; lstring

BreakInfoSize   = SIZE BreakInfoStru+5
TOTAL_BREAKS    = 200

; Bit fields of brk_Flags
BRK_INUSE       equ 80h
BRK_ACTIVE      equ 40h
BRK_TEMP        equ 20h
BRK_HIT1        equ 10h
BRK_APPLY       equ 08h

BRK_INUSE_BIT   equ 7
BRK_ACTIVE_BIT  equ 6
BRK_TEMP_BIT    equ 5
BRK_HIT1_BIT    equ 4
BRK_APPLY_BIT   equ 3

; brk_TypeInfo identify break type
BRKTYPE_DRX     equ 08h
BRKTYPE_I3      equ 10h
BRKTYPE_INT     equ 20h
BRKTYPE_IO      equ 40h
BRKTYPE_MOD     equ 80h

BRK_INT3        equ 10h
BRK_ON_INT      equ 20h
BRK_ON_IO       equ 40h
BRK_ON_MOD      equ 80h
BRK_ON_EXEC     equ 08h
BRK_CAP_IO      equ 49h
BRK_ON_PIO      equ 09h
BRK_ON_BW       equ 0Ah
BRK_ON_BRW      equ 0Bh
BRK_ON_WW       equ 0Ch
BRK_ON_WRW      equ 0Dh
BRK_ON_DW       equ 0Eh
BRK_ON_DRW      equ 0Fh

Hook_Service macro svc
IFDEF   _W95_
        mov     eax, @@&svc
ELSE
        mov     eax, svc
ENDIF
        mov     esi, OFFSET32 SPWIN_&svc
        VMMCall Hook_Device_Service
        mov     Prev_&svc, esi
        endm

; ---------------------------------------------------------------------------
; ** SP_ASMB publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTBYTE SP_ASMB dissBuffSeg
EXTBYTE SP_ASMB dissBuffOff

EXTPROC SP_ASMB dispins
EXTPROC SP_ASMB stepIns
EXTPROC SP_ASMB TraceInstType
EXTPROC SP_ASMB effAddr
EXTPROC SP_ASMB Assemble
EXTPROC SP_ASMB hex_04
EXTPROC SP_ASMB hex_08
EXTPROC SP_ASMB hex_16
EXTPROC SP_ASMB hex_32

; ---------------------------------------------------------------------------
; ** SP_BRKS publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTDWRD SP_BRKS int_flags
EXTBYTE SP_BRKS breakTable
EXTDWRD SP_BRKS cap_Length
EXTBYTE SP_BRKS cap_PortVal
IFDEF   _W95_
EXTDWRD SP_BRKS Kernel32_LoaderHookAddr
ENDIF

EXTPROC SP_BRKS Cmd_NMIBreak
EXTPROC SP_BRKS Cmd_IntBreak
EXTPROC SP_BRKS Cmd_HwBreak
EXTPROC SP_BRKS Cmd_ModBreak
EXTPROC SP_BRKS Cmd_BreakList
EXTPROC SP_BRKS Cmd_BreakClear
EXTPROC SP_BRKS Cmd_BreakEnable
EXTPROC SP_BRKS Cmd_BreakDisable
EXTPROC SP_BRKS Cmd_Zap
EXTPROC SP_BRKS Cmd_CodeBreak
EXTPROC SP_BRKS Cmd_Go
EXTPROC SP_BRKS Cmd_GoFault
EXTPROC SP_BRKS Cmd_GoClient
EXTPROC SP_BRKS Cmd_Step
EXTPROC SP_BRKS Cmd_Trace
EXTPROC SP_BRKS Cmd_IoBreak
EXTPROC SP_BRKS Cmd_Tss
EXTPROC SP_BRKS Cmd_Capture
EXTPROC SP_BRKS codewin_then_menu
EXTPROC SP_BRKS FindCodeBreak
EXTPROC SP_BRKS FindIoBreak
EXTPROC SP_BRKS FindUnusedBreak
EXTPROC SP_BRKS SetupBreak
EXTPROC SP_BRKS applyBreaks
EXTPROC SP_BRKS Apply_Break
EXTPROC SP_BRKS removeBreaks
EXTPROC SP_BRKS Remove_Break
EXTPROC SP_BRKS Evaluate_BreakCondition
EXTPROC SP_BRKS NMI_Handler
EXTPROC SP_BRKS Int03_Handler
EXTPROC SP_BRKS Int01_Handler
EXTPROC SP_BRKS Single_Step_Once
EXTPROC SP_BRKS SPWIN_Return
EXTPROC SP_BRKS SPWIN_MouseTrap
EXTPROC SP_BRKS getIntVector
EXTPROC SP_BRKS setIntVectorCS
EXTPROC SP_BRKS setIntVector
EXTPROC SP_BRKS Setup_Intr1
EXTPROC SP_BRKS Setup_Intr1_Here
EXTPROC SP_BRKS Restore_Int_Controller
EXTPROC SP_BRKS Return_After_Restore
; ICODE
EXTPROC SP_BRKS Breaks_Critical_Init
EXTPROC SP_BRKS Breaks_Device_Init

; ---------------------------------------------------------------------------
; ** SP_DBUG publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTDWRD SP_DBUG SPWIN_P16Int21Ptr
EXTDWRD SP_DBUG SPWIN_P16Selector

IFDEF   _W95_
EXTPROC SP_DBUG Cmd_QueryVxd
EXTPROC SP_DBUG Log_Exec32
ENDIF
; ICODE
EXTPROC SP_DBUG Debug_Device_Init
EXTPROC SP_DBUG Debug_Critical_Init
EXTPROC SP_DBUG Debug_Service_Init

; ---------------------------------------------------------------------------
; ** SP_DISP publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTBYTE SP_DISP Display_Buffer
EXTBYTE SP_DISP CurrentRow
EXTBYTE SP_DISP Window_Rows
EXTBYTE SP_DISP Window_Line
EXTBYTE SP_DISP ScreenFlags
; Flags used in ScreenFlags
SF_NOSWAP_BIT   equ 7

SF_VLOG_BIT     equ 5
SF_VWIN_BIT     equ 4
SF_OUTP_BIT     equ 3
SF_CODE_BIT     equ 2
SF_DATA_BIT     equ 1
SF_REGS_BIT     equ 0

SF_NOSWAP       equ 80h
SF_VLOG         equ 20h
SF_VWIN         equ 10h
SF_OUTP         equ 8
SF_CODE         equ 4
SF_DATA         equ 2
SF_REGS         equ 1

; Pointers to procedures
EXTDWRD SP_DISP Input_Proc
EXTDWRD SP_DISP Output_Proc
EXTDWRD SP_DISP Cursor_Proc
EXTPROC SP_DISP SPW_Screen
EXTPROC SP_DISP Usr_Screen
EXTPROC SP_DISP Usr_Screen_NP
EXTBYTE SP_DISP datawin_height
EXTDWRD SP_DISP datawin_format
EXTBYTE SP_DISP watchwin_num
EXTDWRD SP_DISP watchwin_ptr
EXTDWRD SP_DISP code_win_end
EXTBYTE SP_DISP Zeros

EXTPROC SP_DISP set_Screen
EXTPROC SP_DISP InitScreen
EXTPROC SP_DISP CheckAbortConnection
EXTPROC SP_DISP Printf
EXTPROC SP_DISP PrintfAt
EXTPROC SP_DISP PrintfMainScr
EXTPROC SP_DISP Win_Printf
EXTPROC SP_DISP Display_Text
EXTPROC SP_DISP Display_Line
EXTPROC SP_DISP Display_ModName
EXTPROC SP_DISP scrollLines
EXTPROC SP_DISP scrollLinesNoLog
EXTPROC SP_DISP ConvertUserString
EXTPROC SP_DISP Refresh_Screen
EXTPROC SP_DISP Display_RegWindow
EXTPROC SP_DISP Display_DataWindow
EXTPROC SP_DISP Display_CodeWindow
EXTPROC SP_DISP Display_Output

; ---------------------------------------------------------------------------
; ** SP_FLTS publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTDWRD SP_FLTS Address_Base
EXTDWRD SP_FLTS Address_Limit
EXTBYTE SP_FLTS SP_flags
EXTBYTE SP_FLTS Address_Valid
EXTBYTE SP_FLTS handle_fault
EXTBYTE SP_FLTS DebugOutFlags
; SP_flags bit definitions
SP_I1ON         equ 1
SP_SS1BREAK     equ 2
SP_PIC_OFF      equ 4
SP_EXEC_FLT     equ 8
SP_PROBESCR     equ 10h
SP_CLIENT       equ 40h
SP_ACTIVE       equ 80h

SP_I1ON_BIT     equ 0
SP_SS1BREAK_BIT equ 1
SP_PIC_OFF_BIT  equ 2
SP_EXEC_FLT_BIT equ 3
SP_PROBESCR_BIT equ 4
SP_CLIENT_BIT   equ 6
SP_ACTIVE_BIT   equ 7

EXTPROC SP_FLTS read_byte_ltd
EXTPROC SP_FLTS read_word_ltd
EXTPROC SP_FLTS read_dword_ltd
EXTPROC SP_FLTS word_read_@esi
EXTPROC SP_FLTS dword_read_@esi
EXTPROC SP_FLTS qword_read_@esi
EXTPROC SP_FLTS SPWIN_Beg_Of_LCode
EXTPROC SP_FLTS SPWIN_Beg_Of_SCode
EXTPROC SP_FLTS read_byte_cl
EXTPROC SP_FLTS xchg_byte_al
EXTPROC SP_FLTS read_byte_al
EXTPROC SP_FLTS read_byte_al_p1
EXTPROC SP_FLTS read_byte_al_m1
EXTPROC SP_FLTS read_word_ax
EXTPROC SP_FLTS read_dword_eax
EXTPROC SP_FLTS write_byte_al
EXTPROC SP_FLTS find_string
EXTPROC SP_FLTS repe_cmpsb
EXTPROC SP_FLTS rep_movsb
EXTPROC SP_FLTS Cmd_BF
EXTPROC SP_FLTS Map_Faults
EXTPROC SP_FLTS Save_CPU_Registers
EXTPROC SP_FLTS Restore_CPU_Registers
; ICODE:
EXTPROC SP_FLTS Setup_PM_Int
EXTPROC SP_FLTS Faults_Init
EXTPROC SP_FLTS Faults_Critical_Init

; ---------------------------------------------------------------------------
; ** SP_HELP publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTPROC SP_HELP Cmd_Help

; ---------------------------------------------------------------------------
; ** SP_INIT publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTWORD SP_INIT SPWIN_V86_Int21Off
EXTWORD SP_INIT SPWIN_V86_Segment
EXTDWRD SP_INIT Physical_Bias
EXTDWRD SP_INIT xms_memory_blk1
EXTDWRD SP_INIT xms_memory_blk2
EXTDWRD SP_INIT xms_memory_blk3
EXTDWRD SP_INIT xms_memory_end
LogBuffer_Beg   equ xms_memory_blk1
LogBuffer_End   equ xms_memory_blk2
CapBuffer_Beg   equ xms_memory_blk2
SymBuffer_Beg   equ xms_memory_blk3
SymBuffer_End   equ xms_memory_end

EXTPROC SP_INIT SPWIN_End_Of_SCode
EXTPROC SP_INIT Log_Event_Vxd
EXTPROC SP_INIT SPWIN_PMINIT_Callback

; ---------------------------------------------------------------------------
; ** SP_KEYB publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTBYTE SP_KEYB KeyShift
EXTBYTE SP_KEYB HotKey
EXTBYTE SP_KEYB input_buff_beg
EXTDWRD SP_KEYB key_macro_ptr
EXTBYTE SP_KEYB cmd_buffer

EXTPROC SP_KEYB Local_Beep
EXTPROC SP_KEYB Local_Keyboard
EXTPROC SP_KEYB key_check
EXTPROC SP_KEYB key_decode
EXTPROC SP_KEYB Cmd_Reset
EXTPROC SP_KEYB Force_Key
EXTPROC SP_KEYB key_read
EXTPROC SP_KEYB read_line
EXTPROC SP_KEYB Edit_Text
EXTPROC SP_KEYB Cmd_Set
EXTPROC SP_KEYB find_key
; ICODE
EXTPROC SP_KEYB Kybrd_Device_Init

; ---------------------------------------------------------------------------
; ** SP_KRNL publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTDWRD SP_KRNL VMM_DDB_BASE
EXTDWRD SP_KRNL THHOOK_PTR
EXTDWRD SP_KRNL THHOOK_LinAddr
IFDEF   _W95_
EXTDWRD SP_KRNL CurMemoryContext
ENDIF

EXTPROC SP_KRNL CollectKernelInfo
EXTPROC SP_KRNL Terminate_Current_VM
EXTPROC SP_KRNL Terminate_Current_Task
EXTPROC SP_KRNL GetCurrentTask
EXTPROC SP_KRNL GetHeadExe
EXTPROC SP_KRNL GetHeadTDB
EXTPROC SP_KRNL GetP16ModuleFromName
EXTPROC SP_KRNL ModuleNameFromHandle
EXTPROC SP_KRNL ModuleNameFromSelector
EXTPROC SP_KRNL Mod16_EntryPoint
EXTPROC SP_KRNL Cmd_Heap
EXTPROC SP_KRNL Cmd_VxD
EXTPROC SP_KRNL Cmd_Task
EXTPROC SP_KRNL Cmd_Mod
EXTPROC SP_KRNL LogEventVxd

; ---------------------------------------------------------------------------
; ** SP_MAIN publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTDWRD SP_MAIN PrevRegs
EXTDWRD SP_MAIN errMessage
EXTDWRD SP_MAIN actual_IP
EXTDWRD SP_MAIN currentInst
EXTBYTE SP_MAIN def_segsize
EXTBYTE SP_MAIN disp_as_byte
EXTBYTE SP_MAIN disp_as_word
EXTBYTE SP_MAIN disp_as_dword
EXTBYTE SP_MAIN disp_as_ascii
EXTBYTE SP_MAIN watch_expressions
EXTBYTE SP_MAIN ON_OFF_Table
EXTDWRD SP_MAIN Code_Data_Ptrs
PNTR_DATA       = 8*0                   ; 11*8 bytes
PNTR_CODE       = 8*11                  ; 11*8 bytes
PNTR_WATCH      = 8*22                  ;  1*8 bytes
PNTR_EFADR      = 8*23                  ;  1*8 bytes
PNTR_WORK       = 8*24                  ;  1*8 bytes

EXTPROC SP_MAIN Init_AllWindows
EXTPROC SP_MAIN Display_AllWindows
EXTPROC SP_MAIN Update_Screen
EXTPROC SP_MAIN CheckLineEnd
EXTPROC SP_MAIN CodeWinUp
EXTPROC SP_MAIN CodeWinDown
EXTPROC SP_MAIN Main_Menu
EXTPROC SP_MAIN valueError
EXTPROC SP_MAIN addressError
EXTPROC SP_MAIN write_Error
EXTPROC SP_MAIN syntaxError
EXTPROC SP_MAIN error_report
EXTBYTE SP_MAIN err_address
EXTBYTE SP_MAIN err_syntax

; ---------------------------------------------------------------------------
; ** SP_MDOS publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTBYTE SP_MDOS DosInfo

EXTPROC SP_MDOS Cmd_MapV86Mem
EXTPROC SP_MDOS Cmd_DosDevices
EXTPROC SP_MDOS Cmd_DosInts
EXTPROC SP_MDOS saveIntrs
EXTPROC SP_MDOS V86_Owner

; ---------------------------------------------------------------------------
; ** SP_PARA publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTPROC SP_PARA PrintChar
EXTPROC SP_PARA PrintLine
EXTPROC SP_PARA Cmd_PrintLF
EXTPROC SP_PARA Cmd_PrintFF
EXTPROC SP_PARA Cmd_PrintCode
EXTPROC SP_PARA Cmd_PrintData

; ---------------------------------------------------------------------------
; ** SP_PE32 publics --------------------------------------------------------
; ---------------------------------------------------------------------------
IFDEF   _W95_
EXTDWRD SP_PE32 Module32_List
EXTDWRD SP_PE32 Module32_List_Ptr
EXTDWRD SP_PE32 Kernel32_CodeSelector
EXTDWRD SP_PE32 Kernel32_DataSelector
EXTDWRD SP_PE32 VWIN32_State_Info_Ptr

EXTPROC SP_PE32 FirstModule32
EXTPROC SP_PE32 NextModule32
EXTPROC SP_PE32 GetP32ModuleFromName
EXTPROC SP_PE32 GetPESectionFromAddress
EXTPROC SP_PE32 GetPENameFromAddress
EXTPROC SP_PE32 CheckP32ModuleFromEntryPoint
EXTPROC SP_PE32 P32AddressFromName
EXTPROC SP_PE32 GetP32NameFromOrd
EXTPROC SP_PE32 SPWIN_Kernel32_Initialized
EXTPROC SP_PE32 Cmd_Process
EXTPROC SP_PE32 Cmd_Thread
EXTPROC SP_PE32 Cmd_AddrCntx
EXTPROC SP_PE32 Cmd_Mod32
ENDIF ; _W95_
EXTPROC SP_PE32 strncpy

; ---------------------------------------------------------------------------
; ** SP_SYMB publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTDWRD SP_SYMB VxD_Info_Ptr
EXTDWRD SP_SYMB Symbol_Character

EXTPROC SP_SYMB SPAPI_SYMINFO
EXTPROC SP_SYMB SPAPI_SYMLOAD
EXTPROC SP_SYMB SPAPI_SYMREMV
EXTPROC SP_SYMB SectionNameFromAddress
EXTPROC SP_SYMB GetSymNameForAddress
EXTPROC SP_SYMB V86P16NameFromAddress
EXTPROC SP_SYMB VxdNameFromId
EXTPROC SP_SYMB FindVxdByName
EXTPROC SP_SYMB GetVxdService
EXTPROC SP_SYMB GetVxdServiceName
EXTPROC SP_SYMB GetP16NameFromAddress
EXTPROC SP_SYMB GetP32NameFromAddress
EXTPROC SP_SYMB GetAddressFromName
EXTPROC SP_SYMB P16AddressFromName
EXTPROC SP_SYMB FindP16Segment
EXTPROC SP_SYMB VxdServiceFromAddress
EXTPROC SP_SYMB GetSymbolLen
EXTPROC SP_SYMB Copy_LString
EXTPROC SP_SYMB Cmd_Stack

; ---------------------------------------------------------------------------
; ** SP_UTIL publics --------------------------------------------------------
; ---------------------------------------------------------------------------
EXTDWRD SP_UTIL LogBuffer_Ptr
EXTBYTE SP_UTIL Log_Falgs
; Flags used in Log_Falgs
LF_LOGCMD       equ 1
LF_LOGON        equ 2
LF_PRINT        equ 80h

EXTPROC SP_UTIL Display_Log
EXTPROC SP_UTIL Parse_Line
EXTPROC SP_UTIL Parse_LineNoSkip
EXTPROC SP_UTIL Skip_Blanks
EXTPROC SP_UTIL Skip_Equal
EXTPROC SP_UTIL Scan_String
EXTPROC SP_UTIL Scan_Expression
EXTPROC SP_UTIL Scan_BlockCode
EXTPROC SP_UTIL Scan_BlockData
EXTPROC SP_UTIL Scan_Dword
EXTPROC SP_UTIL Scan_Hex
EXTPROC SP_UTIL Scan_Decimal
EXTPROC SP_UTIL Get_Decimal
EXTPROC SP_UTIL ReadTimeStamp
EXTPROC SP_UTIL register_value
EXTPROC SP_UTIL Get_FlatAddress
EXTPROC SP_UTIL Get_Selector
EXTPROC SP_UTIL Get_SelectorBase
EXTPROC SP_UTIL str_len
EXTPROC SP_UTIL strncmp
EXTPROC SP_UTIL lstrncmp
EXTPROC SP_UTIL Scan_AddressCode
EXTPROC SP_UTIL Scan_AddressData
EXTPROC SP_UTIL Scan_AddressDef
EXTPROC SP_UTIL Scan_AddressDS
EXTPROC SP_UTIL flag_registers
EXTPROC SP_UTIL Convert_Decimal
EXTPROC SP_UTIL Log_Event
EXTPROC SP_UTIL Log_AppendToLog
EXTPROC SP_UTIL Cmd_VuLog
EXTPROC SP_UTIL Cmd_LogOn
EXTPROC SP_UTIL Cmd_LogOff
EXTPROC SP_UTIL Cmd_LogClear
EXTPROC SP_UTIL Cmd_Sys
EXTPROC SP_UTIL Cmd_Hex
EXTPROC SP_UTIL Cmd_ASC
EXTPROC SP_UTIL Cmd_MSR
EXTPROC SP_UTIL Log_DisplayBuffer
EXTPROC SP_UTIL Get_Def_SegSize
EXTPROC SP_UTIL Get_Def_SelSize
DEFSEG_OPR32    equ 01h                 ; bit0=32 bit operand size
DEFSEG_ADR32    equ 02h                 ; bit1=32 bit address size
DEFSEG_ZBASE    equ 40h                 ; bit6=zero base
DEFSEG_V86      equ 80h                 ; bit7=V86 address type

; ---------------------------------------------------------------------------
; Parameters pushed before the call
; Caller is responsible for cleanups.
PARAM1  equ     4
PARAM2  equ     8
PARAM3  equ     12
PARAM4  equ     16

ENDIF ; _16BIT_

; ScreenType:
SCR_ALWAYS      equ 80h                 ; always visible
SCR_MONO        equ 01h + SCR_ALWAYS
SCR_PARA        equ 02h + SCR_ALWAYS
SCR_SERIAL      equ 03h + SCR_ALWAYS
SCR_SVGA        equ 04h

; SetupFlags:
SET_NOFPU       equ 01h         ;No FPU support
SET_TIMER       equ 02h         ;supports RDTSC
SET_BRKEARLY    equ 04h         ;Break Early

DosInfoStru     struc
 NullDevicePtr  dd  ?
 FirstMemBlock  dw  ?
 DosVersion     dw  ?
 capBufSize     dd  8           ;capture buffer size (in KBytes)
 symBufSize     dd  32          ;symbolic information (in KBytes)
 wrkBufSize     dd  0           ;working memory size (in KBytes)
 PrinterPort    dw  3bch
 ParaPort       dw  378h
 SerialPort     dw  3f8h
 SerialDivisor  dw  12          ;DIVISOR_9600
 PhyMemSize     dd  16          ;Physical memory size (in MBytes)
 ScreenType     db  SCR_SVGA
 SetupFlags     db  0
 VgaFont8x16    dd  ?           ;linear address of 8x16 ROM font
DosInfoStru     ends

LString         macro txt
                local t1, t2
                db    t2
t1              db    txt
t2              equ   $-t1
                endm

VXD_CODESELECTOR equ 28h
VXD_DATASELECTOR equ 30h

VxdSymDef       macro vname, nsrv, srvName
&vname&_Srv_&nsrv equ ($ - &vname&_Srv_Beg)
                db srvName
                endm

MakeSrvEntry    macro name1, name2
                dw name1&name2
                endm

VxdSymHeader    macro vname, vId, nsrv, modName
                dd OFFSET32 End_Of_&vname
                dw vId
                LString <modName>
                dw nsrv
&vname&_Srv_Beg label word
                s = 0
                REPT nsrv
                MakeSrvEntry &vname&_Srv_, %s
                s = s + 1
                ENDM
                dw End_Of_&vname - &vname&_Srv_Beg
                endm

ModInfoStru     struc
  mod_Next      dd ?
  mod_Id        dw ?
  mod_Name      db ?
ModInfoStru     ends

d_el            = 00h  ; print it
a_n             = 01h  ; d_norm
a_b             = 02h  ; d_bold
a_r             = 03h  ; d_rvrs
a_f             = 04h  ; d_frame
d_wtop          = 05h  ; 1st scrollable line
d_col           = 06h  ; go column x
d_row           = 07h  ; go row x, col 0
d_dup           = 08h  ;
d_tab           = 09h  ;
d_lf            = 0ah  ; scroll viewwin
d_spc           = 0bh  ;
d_sub           = 0ch  ;
d_clreol        = 0dh  ;
d_chr           = 0eh  ; char on the stack
d_bits          = 0fh  ;
d_table         = 10h  ;
d_jsr           = 11h  ; call a function
d_skpz          = 12h  ; skip next if *sp++ == 0
d_text          = 13h  ; display string ds:ebx (text only)
d_fname         = 14h  ; offset on the stack, max 8 bytes ('.' ends)
;               = 15h  ;
d_r16           = 16h  ; word at [ebp+xx]
d_r32           = 17h  ; dword at [ebp+xx]
d_h04           = 18h  ; dword on stack top
d_h08           = 19h  ; dword on stack top
d_h16           = 1ah  ; dword on stack top
d_h32           = 1bh  ; dword on stack top
d_h48           = 1ch  ; 2 dwords on stack top
d_deci          = 1dh  ; dword on stack top
d_mem           = 1eh  ; from ds:ebx, check limit (edx)
d_ret           = 1fh  ; return without display

; control codes used by screen output device
s_el            = d_el      ; 00h
s_wtop          = d_wtop    ; 05h
s_col           = d_col     ; 06h
s_row           = d_row     ; 07h
s_dup           = d_dup     ; 08h
s_tab           = d_tab     ; 09h
s_lf            = d_lf      ; 0ah
s_spc           = d_spc     ; 0bh
s_window        = d_sub     ; 0ch
s_clreol        = d_clreol  ; 0dh
s_chr           = d_chr     ; 0eh
s_reconnect     = 1bh       ;
s_retkey        = 1eh       ;
s_cursor        = 1fh       ;

t_fill          = 80h           ; Space fill for d_text fields

;d_mem control byte [ttllllll]
DM_ASCI         equ 000h-1
DM_BYTE         equ 040h-1
DM_WORD         equ 080h-1
DM_DWRD         equ 0C0h-1

; d_row parameter range definitions
POS_TOPSCR      equ 000h        ; 00-3f physical row#
POS_CURLIN_BASE equ 040h        ; 40-5f relative to current line
POS_CURLINE     equ 040h+10h    ; 40-5f relative to current line +(-16..+15)
POS_WINDOW      equ 060h        ; 60-7f one of windows start

d_numb          equ d_row
NM_LJUST        equ 080h-1      ; left-justified, variable length
NM_LJFIX        equ 090h-1      ; left-justified, fixed length
NM_RJSPC        equ 0A0h-1      ; right-justified, blank fill
NM_RJZRO        equ 0B0h-1      ; right-justified, 0 fill
NM_LJUST_S      equ 0C0h-1      ; left-justified, variable length (Signed)
NM_LJFIX_S      equ 0D0h-1      ; left-justified, fixed length    (Signed)
NM_RJSPC_S      equ 0E0h-1      ; right-justified, blank fill     (Signed)
NM_RJZRO_S      equ 0F0h-1      ; right-justified, 0 fill         (Signed)

_table          macro a
                db    d_table
                dd    OFFSET32 &a
                endm

_bits           macro b, n, s
                db    d_bits
                dd    b
                db    n, s
                endm

_jsr            macro a
                db    d_jsr
                dw    a - $ - 2
                endm

_RGSTWIN_       = 0
_DATAWIN_       = 1
_CODEWIN_       = 2
_VIEWWIN_       = 3
_CMDLINE_       = 4
_TOPLINE_       = 5
_CURLINE_       = 6

reportError     macro   msg, lbl
                call    error_report
                ifnb    <lbl>
                public  lbl
lbl             label   byte
                endif
                db      msg
                db      0
                endm

;
; Type values used by FullCmd macros
;
GOTO_REL16 = 0
SKIP_BLANK = 1
JUMP_ADDRS = 2
SCAN_VAL32 = 3
DATA_BLOCK = 4
CODE_BLOCK = 5
ENDOF_LINE = 6

PCmnd   macro n, c, t, a, b
        local t1, t2
        db    t2
t1      db    c
t2      equ   ($-t1)+16*t+n
        ifidn <t>, <GOTO_REL16>
        dw    a-t1
        dw    b
        else
        dd    a
        endif
        endm

PartCmd macro c, t, a, b
        PCmnd 00h, <c>, t, <a>, <b>
        endm

FullCmd macro c, t, a, b
        PCmnd 80h, <c>, t, <a>, <b>
        endm

input_line_size equ 60
max_input_lines equ 100
input_buff_size equ max_input_lines*input_line_size ; room for input buffer

inb     macro   v, p
        in      al, p
        ifdif   <al>, <v>
        mov     v, al
        endif
        endm

outb    macro   p, v
        ifdif   <al>, <v>
        mov     al, v
        endif
        out     p, al
        endm

outbd   macro   p, v
        jmp     SHORT $+2
        outb    p, v
        endm

Descriptor_Stru struc
 Limit_0_15     dw 0
 Base_0_15      dw 0
 Base_16_23     db 0
 AccessRights   db 0
 Granularity    db 0
 Base_24_31     db 0
Descriptor_Stru ends

IntVector_Stru   struc
 IV_Offset_0_15  dw 0
 IV_Selector     dw VXD_CODESELECTOR
 IV_reserved     db 0
 IV_Access       db 0eeh
 IV_Offset_16_31 dw 0
IntVector_Stru   ends

; 286/386 access bytes
; PLL00001  available 286 TSS segment
; PLL00010  LDT segment
; PLL00011  busy 286 TSS segment
; PLL00100  286 call gate
; PLL00101  286 task gate
; PLL00110  286 trap gate
; PLL00111  286 interrupt gate
; PLL01001  available 386 TSS segment
; PLL01011  busy 386 TSS segment
; PLL01100  386 call gate
; PLL01110  386 trap gate
; PLL01111  386 interrupt gate

; PLL10EWA  data segment
; PLL11CRA  code segment

;
;type of AccessRights = p,dpl,1,typ,a   or p,dpl,0,type
ar_data         equ 10010011b           ; present, read/write
ar_code         equ 10011011b           ; present, execute/read
ar_stk          equ 10010011b           ; present, read/write, expand-down

a_conform       equ 00000100b           ; conforming code segment
;
DPL0            equ 00000000b
DPL1            equ 00100000b
DPL2            equ 01000000b
DPL3            equ 01100000b
;       
;type of Granularity  = g,d,x,u,limit19-16
;       
gr_16           equ 00000000b           ; G=0, default 16 bit
gr_32           equ 11000000b           ; G=1, default 32 bit

PAGESHIFT       equ 12

C_FLAG          equ 0001h
P_FLAG          equ 0004h
A_FLAG          equ 0010h
Z_FLAG          equ 0040h
S_FLAG          equ 0080h
T_FLAG          equ 0100h
I_FLAG          equ 0200h
D_FLAG          equ 0400h
O_FLAG          equ 0800h

IRC1            = 020h
IRC2            = 0a0h

K_SHIFT         equ 01h
K_CTL           equ 04h
K_ALT           equ 08h
K_SCRL          equ 10h
K_NUML          equ 20h
K_CAP           equ 40h
K_INS           equ 80h

K_UP            equ 01h
K_DOWN          equ 02h
K_RIGHT         equ 03h
K_LEFT          equ 04h
K_FIVE          equ 05h
K_HOME          equ 06h
K_END           equ 07h
K_BKSP          equ 08h
K_TAB           equ 09h
K_ESC           equ 1bh
K_CR            equ 0dh
K_PGUP          equ 0eh
K_PGDN          equ 0fh
K_sSPACE        equ 10h
K_sUP           equ 11h
K_sDOWN         equ 12h
K_sRIGHT        equ 13h
K_sLEFT         equ 14h
K_sFIVE         equ 15h
K_sHOME         equ 16h
K_sEND          equ 17h
K_sBKSP         equ 18h
K_sTAB          equ 19h
K_sCR           equ 1dh
K_sESC          equ 0bh
K_sPGUP         equ 1eh
K_sPGDN         equ 1fh

K_F1            equ 80h
K_F2            equ 81h
K_F3            equ 82h
K_F4            equ 83h
K_F5            equ 84h
K_F6            equ 85h
K_F7            equ 86h
K_F8            equ 87h
K_F9            equ 88h
K_F10           equ 89h
K_F11           equ 8ah
K_F12           equ 8bh
K_PLUS          equ 8ch
K_MINUS         equ 8dh
K_PRT           equ 8eh
K_DEL           equ 8fh

K_sF1           equ 90h
K_sF2           equ 91h
K_sF3           equ 92h
K_sF4           equ 93h
K_sF5           equ 94h
K_sF6           equ 95h
K_sF7           equ 96h
K_sF8           equ 97h
K_sF9           equ 98h
K_sF10          equ 99h
K_sF11          equ 9ah
K_sF12          equ 9bh
K_sPLUS         equ 9ch
K_sMINUS        equ 9dh
K_sPRT          equ 9eh
K_sDEL          equ 9fh

TSS_STRUC       struc
TSS_BackLink    dw ?,?
TSS_ESP0        dd ?
TSS_SS0         dw ?,?
TSS_ESP1        dd ?
TSS_SS1         dw ?,?
TSS_ESP2        dd ?
TSS_SS2         dw ?,?
TSS_CR3         dd ?
TSS_EIP         dd ?
TSS_EFLAGS      dd ?
TSS_EAX         dd ?
TSS_ECX         dd ?
TSS_EDX         dd ?
TSS_EBX         dd ?
TSS_ESP         dd ?
TSS_EBP         dd ?
TSS_ESI         dd ?
TSS_EDI         dd ?
TSS_ES          dw ?,?
TSS_CS          dw ?,?
TSS_SS          dw ?,?
TSS_DS          dw ?,?
TSS_FS          dw ?,?
TSS_GS          dw ?,?
TSS_LDT         dw ?,?
TSS_RESV        dw ?
TSS_IOPORTS     dw ?
TSS_STRUC       ends

; Information gathered by INT 68h.

VXD_INFO_STRU   struc
 vi_SegNumber   dw 0
 vi_Start       dd 0
 vi_End         dd 0
 vi_Name        db 8 dup( 0 )
VXD_INFO_STRU   ends

DumpRegs macro  xc
        call    dump_all
        db      xc
        endm

DumpRegsCalls   macro
reg_names       db ' SS DS ES FS GSEDIESIEBPESPEBXEDXECXEAXFLG'

dump_all:
        pushfd
        cli
        pushad
        mov     ax, gs
        push    eax
        mov     ax, fs
        push    eax
        mov     ax, es
        push    eax
        mov     ax, ds
        push    eax
        mov     ax, ss
        push    eax
        mov     ebp, esp
        mov     esi, [ebp+4*14]         ; return address
        cld
        lods    byte ptr cs:[esi]       ; marker
        mov     [ebp+4*14], esi         ; return address
        mov     ah, 70h
        push    VXD_DATASELECTOR
        pop     es
        mov     edi, 0b0000h
        mov     word ptr es:[edi+24*160], ax
        mov     ecx, 14
        mov     esi, OFFSET32 reg_names
ll1:    mov     ebx, [ebp]
        add     ebp, 4
        mov     ah, 7
        lods    byte ptr cs:[esi]
        stos    word ptr es:[edi]
        lods    byte ptr cs:[esi]
        stos    word ptr es:[edi]
        lods    byte ptr cs:[esi]
        stos    word ptr es:[edi]
        mov     al, '='
        stos    word ptr es:[edi]
        call    hx_32
        mov     al, ' '
        stos    word ptr es:[edi]
        mov     al, ' '
        stos    word ptr es:[edi]
        mov     al, ' '
        stos    word ptr es:[edi]
        mov     al, ' '
        stos    word ptr es:[edi]
        loop    ll1
@@:     call    Local_Keyboard
        cmp     al, 01dh ;Ctrl
        jne     short @b
        pop     eax
        pop     eax
        mov     ds, ax
        pop     eax
        mov     es, ax
        pop     eax
        mov     fs, ax
        pop     eax
        mov     gs, ax
        popad
        popfd
        ret

; BX/BL = hex value, ah = attribute
hx_32:  call    hx_hw
hx_hw:  ror     ebx, 16
hx_16:  call    hx_bh
hx_bh:  xchg    bl, bh
hx_08:  mov     al, bl
        shr     al, 4
        cmp     al, 10
        cmc
        adc     al, '0'
        daa
        stos    word ptr es:[edi]
        mov     al, bl
        and     al, 0fh
        cmp     al, 10
        cmc
        adc     al, '0'
        daa
        stos    word ptr es:[edi]
        ret
        endm
