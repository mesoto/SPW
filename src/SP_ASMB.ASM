title.  SoftProbe - SP_Asmb

SP_ASMB EQU 1
INCLUDE SP_DEFS.INC

; to be added:
;       FCMOVcc ST,STi


LDATA_SEG       ; ===========================================================

asmBufPtr       dd 0
asmRmPtr        dd 0            ;points to the r/m byte
asmInputPtr     dd 0

a16mode         dd OFFSET32 rm__00
                dd OFFSET32 rm__01
                dd OFFSET32 rm__02
                dd OFFSET32 rm__03
                dd OFFSET32 rm__esi
                dd OFFSET32 rm__edi
                dd OFFSET32 rm__ebp
                dd OFFSET32 rm__ebx
a32mode         dd OFFSET32 rm__eax
                dd OFFSET32 rm__ecx
                dd OFFSET32 rm__edx
                dd OFFSET32 rm__ebx
                dd OFFSET32 rm__esp
                dd OFFSET32 rm__ebp
                dd OFFSET32 rm__esi
                dd OFFSET32 rm__edi

public  dissBuffSeg
public  dissBuffOff
OpcBufPtr       dd 0

ScrachBuffer    label byte
dissBuffSeg     db '0000:'
dissBuffOff     db '00000000 '          ;address
asmBuffer       equ this byte
dissBuffHex     db 17 dup(' ')          ;instruction hex value
dissBuffOpcode  db 8  dup(' ')          ;instruction opcode
dissBuffOprs    db 50 dup(' ')          ;instruction operand
dissBuffEnd     db 50 dup(0)            ;end of buffer (room for label name)
ScrachBufferLen equ (dissBuffEnd - ScrachBuffer)
saved_rmbyte    equ asmBuffer[20]

OPR32   equ     1
ADR32   equ     2
ZBASE   equ     40h

rm_type db      0               ;bit0=32 bit operand size override
                                ;bit1=32 bit address size override
                                ;bit7=16 bit operand size override
sg_name db      0               ;override seg name (keep it with rm_type)

LDATA_ENDS      ; ===========================================================

; ---------------------------------------------------------------------------
SCODE_SEG       ; Safe code area (No Pushes inside calls)
; ---------------------------------------------------------------------------
lodbyt: inc     actual_IP
        mov     al, 0f1h        ; invalid opcode
lodbyt1:inc     ebx
        cmp     Address_Valid, 1
        jb      short @f
        mov     al, [ebx-1]
        clc
@@:     ret

lodwrd: add     actual_IP, 2
        inc     ebx
        inc     ebx
        cmp     Address_Valid, 1
        jb      short @f
        xor     eax, eax
        movzx   eax, word ptr [ebx-2]
@@:     ret

loddwrd:add     actual_IP, 4
        add     ebx, 4
        cmp     Address_Valid, 1
        jb      short @f
        xor     eax, eax
        mov     eax, [ebx-4]
@@:     ret

; ---------------------------------------------------------------------------
;input: EBX     linear address of the first byte of instruction
;       EBP     points to saved CPU sate
;       DS=CS
;output C=1     use trace
;       C=0     Use temp break at EBX
;       Special cases: in/out 21/A1, int 3, int 1, pushf
;               Emulate the instruction and
;               return two levels back (caller of Single_Step_Once)
;       EDI is preserved.

PUBPROC TraceInstType
        DBGBRK  3
        mov     esi, ebx
        xor     eax, eax
_tr@prefix:
_tr@opr32:
_tr@adr32:
trcIns1:lodsb
        movzx   ecx, byte ptr opcode1[eax*4][3]
        jmp     dword ptr StepType[ecx*8][4]

_tr@step2:
        movzx   edx, byte ptr [esi]
        inc     esi
        jmp     short chk_in_out21

use_breakpoint:
        mov     ebx, esi
;       clc
        ret

_tr@step1:      ; includes: int 3, into, pushf
        cmp     al, 0cch                ;int 3?
        je      short set_new_eip
;;      cmp     al, 0ceh                ;into?
        cmp     al, 09ch                ;pushf?
        je      short use_breakpoint

        movzx   edx, word ptr [ebp].R_EDX
chk_in_out21:
        cmp     edx, 21h
        jne     short _tr@trace
        DBGBRK  3
        mov     ecx, 80000003h
        and     ecx, [ebp].R_CS         ;Ring3 code?
        jz      short chk_for_io
        js      short _tr@trace         ;V86, will be trapped (i/o map=1)
        ; Its protected mode, check IOPL
        mov     ch, 30h
        and     ch, byte ptr [ebp].R_EFLAGS[1]
        shr     ch, 4                   ;IOPL
        cmp     ch, cl                  ;IOPL < CPL?
        jb      short _tr@trace         ;will be trapped
chk_for_io:
        or      al, 08h                 ;e4/ec = in al,nn/dx
        cmp     al, 0ech
        je      short trace_in21
        cmp     al, 0eeh                ;e6/ee = out nn/dx,al
        je      short trace_out21
_tr@0f:
_tr@inst_2:
_tr@stepm1:
_tr@stepm2:
_tr@stepf:
_tr@step3a:
_tr@trace:
        stc                             ;use trace
        ret

_tr@stepx:
        lodsb
        cmp     al, 60h
        jae     short _tr@trace         ;GP fault will handle it
        cmp     al, 1
        je      short set_new_eip
        cmp     al, 3
        je      short set_new_eip
;;      cmp     al, 41h
;;      je      short set_new_eip

        xchg    ebx, eax
        call    getIntVector

        test    [ebp].R_CS, 80000003h   ; V86 or PM.CPL>0
        jz      short Ring0_client
        ; CPL>0
        test    eax, 60000000h          ; DPL=0?
        jz      short _tr@trace         ; GP fault will handle it
break_handler:
        mov     ebx, edx
        movzx   eax, ax
        jmp     Get_FlatAddress         ; ebx=linear address
        ; use breakpoint if no error (CF=0)

Ring0_client:
        ; Ring0 call
        cmp     bl, 20h                 ; INT 20h is special
        jne     short break_handler
        stc                             ; use trace
        ret

trace_in21:
        in      al, dx
        mov     byte ptr [ebp].R_EAX, al
set_new_eip:
        sub     esi, ebx                ;length of the instruction
        add     [ebp].R_EIP, esi        ;new offset
        pop     esi                     ;get rid of call in Single_Step_Once
        ret

trace_out21:
        mov     al, byte ptr [ebp].R_EAX
        out     dx, al
        jmp     short set_new_eip

SCODE_ENDS

LCODE_SEG       ; ===========================================================

; Flags used in DX during assemble command
; DL flags
RM__BYTE        equ 01h         ; implied byte size
RM__WORD        equ 02h         ; implied word size
RM__DWRD        equ 04h         ; 32-bit register/dword
RM__FWRD        equ 08h         ; 16:32-bit fword
RM__QWRD        equ 10h         ; 64-bit qword
RM__DIRA        equ 20h         ; uses direct addressing
RM__DATA        equ 40h         ; operand includes 16/32 bit data
RM__ADDR        equ 80h         ; memory reference not registers
RM__BYTE_BIT    equ 0
RM__WORD_BIT    equ 1
RM__DWRD_BIT    equ 2
RM__FWRD_BIT    equ 3
RM__DIRA_BIT    equ 5
RM__DATA_BIT    equ 6
RM__ADDR_BIT    equ 7
; DH flags - instruction prefix
PRE_ADR32       equ 80h
PRE_OPR32       equ 40h
PRE_SMASK       equ 07h
PRE_ES          equ 1
PRE_CS          equ 2
PRE_SS          equ 3
PRE_DS          equ 4
PRE_FS          equ 5
PRE_GS          equ 6
seg_Prefix      db  26h, 2eh, 36h, 3eh, 64h, 65h

insName label word
X0      equ $
_invl:  db 1,'?'

arg__PREFINS:
        stosb
get_Opcode:
        mov     asmBufPtr, edi          ; start of next instruction
        call    Parse_Line
_movzx: FullCmd 'MOVZX'    GOTO_REL16, arg__MULTYPE, Opcode_Movzx
_movsx: FullCmd 'MOVSX'    GOTO_REL16, arg__MULTYPE, Opcode_Movsx
_movs:  PartCmd 'MOVS'     GOTO_REL16, arg__STRSIZE, 0A5A4h
_mov:   FullCmd 'MOV'      GOTO_REL16, arg__MULTYPE, Opcode_Mov
_pushf: PartCmd 'PUSHF'    GOTO_REL16, arg__wrdSIZE, 009Ch
_popf:  PartCmd 'POPF'     GOTO_REL16, arg__wrdSIZE, 009Dh
_pusha: PartCmd 'PUSHA'    GOTO_REL16, arg__wrdSIZE, 0060h
_popa:  PartCmd 'POPA'     GOTO_REL16, arg__wrdSIZE, 0061h
_push:  FullCmd 'PUSH'     GOTO_REL16, arg__MULTYPE, Opcode_Push
_pop:   FullCmd 'POP'      GOTO_REL16, arg__MULTYPE, Opcode_Pop
_inc:   FullCmd 'INC'      GOTO_REL16, arg__MULTYPE, Opcode_Inc
_dec:   FullCmd 'DEC'      GOTO_REL16, arg__MULTYPE, Opcode_Dec
_lods:  PartCmd 'LODS'     GOTO_REL16, arg__STRSIZE, 0ADACh
_stos:  PartCmd 'STOS'     GOTO_REL16, arg__STRSIZE, 0ABAAh
_scas:  PartCmd 'SCAS'     GOTO_REL16, arg__STRSIZE, 0AFAEh
_cmps:  PartCmd 'CMPS'     GOTO_REL16, arg__STRSIZE, 0A7A6h
_repe:  FullCmd 'REPE'     GOTO_REL16, arg__PREFINS, 00F3h
_repne: FullCmd 'REPNE'    GOTO_REL16, arg__PREFINS, 00F2h
_xchg:  FullCmd 'XCHG'     GOTO_REL16, arg__MULTYPE, Opcode_Xchg
_and:   FullCmd 'AND'      GOTO_REL16, arg__MULTYPE, Opcode_And
_test:  FullCmd 'TEST'     GOTO_REL16, arg__MULTYPE, Opcode_Test
_xor:   FullCmd 'XOR'      GOTO_REL16, arg__MULTYPE, Opcode_Xor
_or:    FullCmd 'OR'       GOTO_REL16, arg__MULTYPE, Opcode_Or
_add:   FullCmd 'ADD'      GOTO_REL16, arg__MULTYPE, Opcode_Add
_adc:   FullCmd 'ADC'      GOTO_REL16, arg__MULTYPE, Opcode_Adc
_sub:   FullCmd 'SUB'      GOTO_REL16, arg__MULTYPE, Opcode_Sub
_sbb:   FullCmd 'SBB'      GOTO_REL16, arg__MULTYPE, Opcode_Sbb
_cmp:   FullCmd 'CMP'      GOTO_REL16, arg__MULTYPE, Opcode_Cmp
_leave: FullCmd 'LEAVE'    GOTO_REL16, arg__NOPRND1, 00C9h
_lea:   FullCmd 'LEA'      GOTO_REL16, arg__R16_MEM, 008dh
_lds:   FullCmd 'LDS'      GOTO_REL16, arg__R16_MEM, 00c5h
_les:   FullCmd 'LES'      GOTO_REL16, arg__R16_MEM, 00c4h
_retf:  PartCmd 'RETF'     GOTO_REL16, arg__OPTWORD, 0CACBh
_ret:   PartCmd 'RET'      GOTO_REL16, arg__OPTWORD, 0C2C3h
_iret:  PartCmd 'IRET'     GOTO_REL16, arg__wrdSIZE, 00CFh
_clc:   FullCmd 'CLC'      GOTO_REL16, arg__NOPRND1, 00F8h
_cmc:   FullCmd 'CMC'      GOTO_REL16, arg__NOPRND1, 00F5h
_stc:   FullCmd 'STC'      GOTO_REL16, arg__NOPRND1, 00F9h
_cld:   FullCmd 'CLD'      GOTO_REL16, arg__NOPRND1, 00FCh
_std:   FullCmd 'STD'      GOTO_REL16, arg__NOPRND1, 00FDh
_cli:   FullCmd 'CLI'      GOTO_REL16, arg__NOPRND1, 00FAh
_sti:   FullCmd 'STI'      GOTO_REL16, arg__NOPRND1, 00FBh
_loopn: FullCmd 'LOOPNE'   GOTO_REL16, arg__RELJMP1, 00e0h
_loope: FullCmd 'LOOPE'    GOTO_REL16, arg__RELJMP1, 00e1h
_loop:  FullCmd 'LOOP'     GOTO_REL16, arg__RELJMP1, 00e2h
_jcxz:  FullCmd 'JCXZ'     GOTO_REL16, arg__RELJMP2, 00e3h
        FullCmd 'JECXZ'    GOTO_REL16, arg__RELJMP2, 40e3h  ;PRE_OPR32
_jo:    FullCmd 'JO'       GOTO_REL16, arg__RELJMP3, 0070h
_jno:   FullCmd 'JNO'      GOTO_REL16, arg__RELJMP3, 0071h
_jc:    FullCmd 'JC'       GOTO_REL16, arg__RELJMP3, 0072h
_jnc:   FullCmd 'JNC'      GOTO_REL16, arg__RELJMP3, 0073h
_je:    FullCmd 'JE'       GOTO_REL16, arg__RELJMP3, 0074h
_jne:   FullCmd 'JNE'      GOTO_REL16, arg__RELJMP3, 0075h
_ja:    FullCmd 'JA'       GOTO_REL16, arg__RELJMP3, 0077h
_jbe:   FullCmd 'JBE'      GOTO_REL16, arg__RELJMP3, 0076h
_js:    FullCmd 'JS'       GOTO_REL16, arg__RELJMP3, 0078h
_jns:   FullCmd 'JNS'      GOTO_REL16, arg__RELJMP3, 0079h
_jp:    FullCmd 'JP'       GOTO_REL16, arg__RELJMP3, 007ah
_jnp:   FullCmd 'JNP'      GOTO_REL16, arg__RELJMP3, 007bh
_jle:   FullCmd 'JLE'      GOTO_REL16, arg__RELJMP3, 007eh
_jl:    FullCmd 'JL'       GOTO_REL16, arg__RELJMP3, 007ch
_jge:   FullCmd 'JGE'      GOTO_REL16, arg__RELJMP3, 007dh
_jg:    FullCmd 'JG'       GOTO_REL16, arg__RELJMP3, 007fh
_jmp:   FullCmd 'JMP'      GOTO_REL16, arg__MULTYPE, Opcode_Jmp
_call:  FullCmd 'CALL'     GOTO_REL16, arg__MULTYPE, Opcode_Call
_imul:  FullCmd 'IMUL'     GOTO_REL16, arg__MULTYPE, Opcode_Imul
_mul:   FullCmd 'MUL'      GOTO_REL16, arg__MULTYPE, Opcode_Mul
_idiv:  FullCmd 'IDIV'     GOTO_REL16, arg__MULTYPE, Opcode_Idiv
_div:   FullCmd 'DIV'      GOTO_REL16, arg__MULTYPE, Opcode_Div
_int3:  FullCmd 'INT3'     GOTO_REL16, arg__NOPRND1, 00CCh
_into:  FullCmd 'INTO'     GOTO_REL16, arg__NOPRND1, 00CEh
_int:   FullCmd 'INT'      GOTO_REL16, Int_Opcode,   00CDh
_nop:   FullCmd 'NOP'      GOTO_REL16, arg__NOPRND1, 0090h
_xlat:  FullCmd 'XLAT'     GOTO_REL16, arg__SEGOVR1, 00D7h
_lahf:  FullCmd 'LAHF'     GOTO_REL16, arg__NOPRND1, 009Fh
_sahf:  FullCmd 'SAHF'     GOTO_REL16, arg__NOPRND1, 009Eh
_aaa:   FullCmd 'AAA'      GOTO_REL16, arg__NOPRND1, 0037h
_daa:   FullCmd 'DAA'      GOTO_REL16, arg__NOPRND1, 0027h
_aas:   FullCmd 'AAS'      GOTO_REL16, arg__NOPRND1, 003Fh
_das:   FullCmd 'DAS'      GOTO_REL16, arg__NOPRND1, 002Fh
_cbw:   FullCmd 'CBW'      GOTO_REL16, arg__16BIT,   0098h
        FullCmd 'CWDE'     GOTO_REL16, arg__32BIT,   0098h
_cwd:   FullCmd 'CWD'      GOTO_REL16, arg__16BIT,   0099h
        FullCmd 'CDQ'      GOTO_REL16, arg__32BIT,   0099h
_ins:   PartCmd 'INS'      GOTO_REL16, arg__STRSIZE, 6D6Ch
_outs:  PartCmd 'OUTS'     GOTO_REL16, arg__STRSIZE, 6F6Eh
_hlt:   FullCmd 'HLT'      GOTO_REL16, arg__NOPRND1, 00F4h
_wait:  FullCmd 'WAIT'     GOTO_REL16, arg__NOPRND1, 009Bh
_lock:  FullCmd 'LOCK'     GOTO_REL16, arg__PREFINS, 00F0h
_aam:   FullCmd 'AAM'      GOTO_REL16, arg__NOPRND2, 0AD4h
_aad:   FullCmd 'AAD'      GOTO_REL16, arg__NOPRND2, 0AD5h
_in:    FullCmd 'IN'       GOTO_REL16, arg__MULTYPE, Opcode_In
_out:   FullCmd 'OUT'      GOTO_REL16, arg__MULTYPE, Opcode_Out
;---------------------------------------- 286 instructions -------------------
_enter: FullCmd 'ENTER'    GOTO_REL16, arg__WRD_BYT, 00C8h
_bound: FullCmd 'BOUND'    GOTO_REL16, arg__R16_MEM, 0062h
_arpl:  FullCmd 'ARPL'     GOTO_REL16, arg__MEM_R16, 0063h
;---------------------------------------- 286 prefix (0fh) -------------------
_clts:  FullCmd 'CLTS'     GOTO_REL16, arg__NOPRND2, 060Fh
_sldt:  FullCmd 'SLDT'     GOTO_REL16, arg__0F_MEM_, 0000h
_str:   FullCmd 'STR'      GOTO_REL16, arg__0F_MEM_, 0800h
_lldt:  FullCmd 'LLDT'     GOTO_REL16, arg__0F_MEM_, 1000h
_ltr:   FullCmd 'LTR'      GOTO_REL16, arg__0F_MEM_, 1800h
_verr:  FullCmd 'VERR'     GOTO_REL16, arg__0F_MEM_, 2000h
_verw:  FullCmd 'VERW'     GOTO_REL16, arg__0F_MEM_, 2800h
_sgdt:  FullCmd 'SGDT'     GOTO_REL16, arg__0F_MEM_, 0001h
_sidt:  FullCmd 'SIDT'     GOTO_REL16, arg__0F_MEM_, 0801h
_lgdt:  FullCmd 'LGDT'     GOTO_REL16, arg__0F_MEM_, 1001h
_lidt:  FullCmd 'LIDT'     GOTO_REL16, arg__0F_MEM_, 1801h
_smsw:  FullCmd 'SMSW'     GOTO_REL16, arg__0F_MEM_, 2001h
_lmsw:  FullCmd 'LMSW'     GOTO_REL16, arg__0F_MEM_, 3001h
_lar:   FullCmd 'LAR'      GOTO_REL16, arg__R16_RM2, 020Fh
_lsl:   FullCmd 'LSL'      GOTO_REL16, arg__R16_RM2, 030Fh
_ldall: FullCmd 'LOADALL'  GOTO_REL16, arg__NOPRND2, 050fh
;---------------------------------------- 386 prefix (0fh) -------------------
_invd:  FullCmd 'INVD'     GOTO_REL16, arg__NOPRND2, 080fh
_wbinvd:FullCmd 'WBINVD'   GOTO_REL16, arg__NOPRND2, 090fh
_invlpg:FullCmd 'INVLPG'   GOTO_REL16, arg__0F_MEM_, 3801h
_cpuid: FullCmd 'CPUID'    GOTO_REL16, arg__NOPRND2, 0a20fh
_salc:  FullCmd 'SALC'     GOTO_REL16, arg__NOPRND1, 00D6h
_wrmsr: FullCmd 'WRMSR'    GOTO_REL16, arg__NOPRND2, 300fh
_rdtsc: FullCmd 'RDTSC'    GOTO_REL16, arg__NOPRND2, 310fh
_rdmsr: FullCmd 'RDMSR'    GOTO_REL16, arg__NOPRND2, 320fh
_rdpmc: FullCmd 'RDPMC'    GOTO_REL16, arg__NOPRND2, 330fh
_ud1:   FullCmd 'UD1'      GOTO_REL16, arg__NOPRND2, 0b90fh
_ud2:   FullCmd 'UD2'      GOTO_REL16, arg__NOPRND2, 0b0fh
_rsm:   FullCmd 'RSM'      GOTO_REL16, arg__NOPRND2, 0aa0fh
_xadd:  FullCmd 'XADD'     GOTO_REL16, arg__MULTYPE, Opcode_Xadd
_cmpxch:FullCmd 'CMPXCHG'  GOTO_REL16, arg__MULTYPE, Opcode_Cmpxchg
_bswap: FullCmd 'BSWAP'    GOTO_REL16, arg__MULTYPE, Opcode_Bswap
_bts:   FullCmd 'BTS'      GOTO_REL16, arg__MULTYPE, Opcode_Bts
_btr:   FullCmd 'BTR'      GOTO_REL16, arg__MULTYPE, Opcode_Btr
_btc:   FullCmd 'BTC'      GOTO_REL16, arg__MULTYPE, Opcode_Btc
_bt:    FullCmd 'BT'       GOTO_REL16, arg__MULTYPE, Opcode_Bt
_bsf:   FullCmd 'BSF'      GOTO_REL16, arg__R16_RM2, 0BC0Fh
_bsr:   FullCmd 'BSR'      GOTO_REL16, arg__R16_RM2, 0BD0Fh
_shld:  FullCmd 'SHLD'     GOTO_REL16, arg__SHLRD__, 0A50Fh
_shrd:  FullCmd 'SHRD'     GOTO_REL16, arg__SHLRD__, 0AD0Fh
_lss:   FullCmd 'LSS'      GOTO_REL16, arg__R16_RM2, 0B20Fh
_lfs:   FullCmd 'LFS'      GOTO_REL16, arg__R16_RM2, 0B40Fh
_lgs:   FullCmd 'LGS'      GOTO_REL16, arg__R16_RM2, 0B50Fh
_seto:  FullCmd 'SETO'     GOTO_REL16, arg__RM8____, 900Fh
_setno: FullCmd 'SETNO'    GOTO_REL16, arg__RM8____, 910Fh
_setc:  FullCmd 'SETC'     GOTO_REL16, arg__RM8____, 920Fh
_setnc: FullCmd 'SETNC'    GOTO_REL16, arg__RM8____, 930Fh
_sete:  FullCmd 'SETE'     GOTO_REL16, arg__RM8____, 940Fh
_setne: FullCmd 'SETNE'    GOTO_REL16, arg__RM8____, 950Fh
_seta:  FullCmd 'SETBE'    GOTO_REL16, arg__RM8____, 960Fh
_setbe: FullCmd 'SETA'     GOTO_REL16, arg__RM8____, 970Fh
_sets:  FullCmd 'SETS'     GOTO_REL16, arg__RM8____, 980Fh
_setns: FullCmd 'SETNS'    GOTO_REL16, arg__RM8____, 990Fh
_setp:  FullCmd 'SETP'     GOTO_REL16, arg__RM8____, 9A0Fh
_setnp: FullCmd 'SETNP'    GOTO_REL16, arg__RM8____, 9B0Fh
_setle: FullCmd 'SETLE'    GOTO_REL16, arg__RM8____, 9E0Fh
_setl:  FullCmd 'SETL'     GOTO_REL16, arg__RM8____, 9C0Fh
_setge: FullCmd 'SETGE'    GOTO_REL16, arg__RM8____, 9D0Fh
_setg:  FullCmd 'SETG'     GOTO_REL16, arg__RM8____, 9F0Fh
_cmovo: FullCmd 'CMOVO'    GOTO_REL16, arg__R16_RM2, 400Fh
_cmovno:FullCmd 'CMOVNO'   GOTO_REL16, arg__R16_RM2, 410Fh
_cmovc: FullCmd 'CMOVC'    GOTO_REL16, arg__R16_RM2, 420Fh
_cmovnc:FullCmd 'CMOVNC'   GOTO_REL16, arg__R16_RM2, 430Fh
_cmove: FullCmd 'CMOVE'    GOTO_REL16, arg__R16_RM2, 440Fh
_cmovne:FullCmd 'CMOVNE'   GOTO_REL16, arg__R16_RM2, 450Fh
_cmova: FullCmd 'CMOVBE'   GOTO_REL16, arg__R16_RM2, 460Fh
_cmovbe:FullCmd 'CMOVA'    GOTO_REL16, arg__R16_RM2, 470Fh
_cmovs: FullCmd 'CMOVS'    GOTO_REL16, arg__R16_RM2, 480Fh
_cmovns:FullCmd 'CMOVNS'   GOTO_REL16, arg__R16_RM2, 490Fh
_cmovp: FullCmd 'CMOVP'    GOTO_REL16, arg__R16_RM2, 4A0Fh
_cmovnp:FullCmd 'CMOVNP'   GOTO_REL16, arg__R16_RM2, 4B0Fh
_cmovle:FullCmd 'CMOVLE'   GOTO_REL16, arg__R16_RM2, 4E0Fh
_cmovl: FullCmd 'CMOVL'    GOTO_REL16, arg__R16_RM2, 4C0Fh
_cmovge:FullCmd 'CMOVGE'   GOTO_REL16, arg__R16_RM2, 4D0Fh
_cmovg: FullCmd 'CMOVG'    GOTO_REL16, arg__R16_RM2, 4F0Fh

;;** instructions after this line are not used in opcode1

_not:   FullCmd 'NOT'      GOTO_REL16, arg__REGMEM_, 010F7h
_neg:   FullCmd 'NEG'      GOTO_REL16, arg__REGMEM_, 018F7h
_rol:   FullCmd 'ROL'      GOTO_REL16, arg__ROTATE_, 000D3h
_ror:   FullCmd 'ROR'      GOTO_REL16, arg__ROTATE_, 008D3h
_rcl:   FullCmd 'RCL'      GOTO_REL16, arg__ROTATE_, 010D3h
_rcr:   FullCmd 'RCR'      GOTO_REL16, arg__ROTATE_, 018D3h
_shl:   FullCmd 'SHL'      GOTO_REL16, arg__ROTATE_, 020D3h
_shr:   FullCmd 'SHR'      GOTO_REL16, arg__ROTATE_, 028D3h
_sar:   FullCmd 'SAR'      GOTO_REL16, arg__ROTATE_, 038D3h

;---------------------------------------- MMX instructions -------------------
_emms:     FullCmd 'EMMS'      GOTO_REL16, arg__NOPRND2, 0770fh
_movd:     FullCmd 'MOVD'      GOTO_REL16, arg__MULTYPE, Opcode_Movd
_movq:     FullCmd 'MOVQ'      GOTO_REL16, arg__MULTYPE, Opcode_Movq
_packsswb: FullCmd 'PACKSSWB'  GOTO_REL16, arg__MMXMEM_, 0630fh
_packssdw: FullCmd 'PACKSSDW'  GOTO_REL16, arg__MMXMEM_, 06b0fh
_packuswb: FullCmd 'PACKUSWB'  GOTO_REL16, arg__MMXMEM_, 0670fh
_punpcklbw:FullCmd 'PUNPCKLBW' GOTO_REL16, arg__MMXMEM_, 0600fh
_punpcklwd:FullCmd 'PUNPCKLWD' GOTO_REL16, arg__MMXMEM_, 0610fh
_punpckldq:FullCmd 'PUNPCKLDQ' GOTO_REL16, arg__MMXMEM_, 0620fh
_punpckhbw:FullCmd 'PUNPCKHBW' GOTO_REL16, arg__MMXMEM_, 0680fh
_punpckhwd:FullCmd 'PUNPCKHWD' GOTO_REL16, arg__MMXMEM_, 0690fh
_punpckhdq:FullCmd 'PUNPCKHDQ' GOTO_REL16, arg__MMXMEM_, 06a0fh
_psllw:    FullCmd 'PSLLW'     GOTO_REL16, arg__MULTYPE, Opcode_Psllw
_pslld:    FullCmd 'PSLLD'     GOTO_REL16, arg__MULTYPE, Opcode_Pslld
_psllq:    FullCmd 'PSLLQ'     GOTO_REL16, arg__MULTYPE, Opcode_Psllq
_psrlw:    FullCmd 'PSRLW'     GOTO_REL16, arg__MULTYPE, Opcode_Psrlw
_psrld:    FullCmd 'PSRLD'     GOTO_REL16, arg__MULTYPE, Opcode_Psrld
_psrlq:    FullCmd 'PSRLQ'     GOTO_REL16, arg__MULTYPE, Opcode_Psrlq
_psraw:    FullCmd 'PSRAW'     GOTO_REL16, arg__MULTYPE, Opcode_Psraw
_psrad:    FullCmd 'PSRAD'     GOTO_REL16, arg__MULTYPE, Opcode_Psrad
_paddb:    FullCmd 'PADDB'     GOTO_REL16, arg__MMXMEM_, 0fc0fh
_paddw:    FullCmd 'PADDW'     GOTO_REL16, arg__MMXMEM_, 0fd0fh
_paddd:    FullCmd 'PADDD'     GOTO_REL16, arg__MMXMEM_, 0fe0fh
_paddsb:   FullCmd 'PADDSB'    GOTO_REL16, arg__MMXMEM_, 0ec0fh
_paddsw:   FullCmd 'PADDSW'    GOTO_REL16, arg__MMXMEM_, 0ed0fh
_paddusb:  FullCmd 'PADDUSB'   GOTO_REL16, arg__MMXMEM_, 0dc0fh
_paddusw:  FullCmd 'PADDUSW'   GOTO_REL16, arg__MMXMEM_, 0dd0fh
_psubb:    FullCmd 'PSUBB'     GOTO_REL16, arg__MMXMEM_, 0f80fh
_psubw:    FullCmd 'PSUBW'     GOTO_REL16, arg__MMXMEM_, 0f90fh
_psubd:    FullCmd 'PSUBD'     GOTO_REL16, arg__MMXMEM_, 0fa0fh
_psubsb:   FullCmd 'PSUBSB'    GOTO_REL16, arg__MMXMEM_, 0e80fh
_psubsw:   FullCmd 'PSUBSW'    GOTO_REL16, arg__MMXMEM_, 0e90fh
_psubusb:  FullCmd 'PSUBUSB'   GOTO_REL16, arg__MMXMEM_, 0d80fh
_psubusw:  FullCmd 'PSUBUSW'   GOTO_REL16, arg__MMXMEM_, 0d90fh
_pmulhw:   FullCmd 'PMULHW'    GOTO_REL16, arg__MMXMEM_, 0e50fh
_pmullw:   FullCmd 'PMULLW'    GOTO_REL16, arg__MMXMEM_, 0d50fh
_pmaddwd:  FullCmd 'PMADDWD'   GOTO_REL16, arg__MMXMEM_, 0f50fh
_pcmpeqb:  FullCmd 'PCMPEQB'   GOTO_REL16, arg__MMXMEM_, 0740fh
_pcmpeqw:  FullCmd 'PCMPEQW'   GOTO_REL16, arg__MMXMEM_, 0750fh
_pcmpeqd:  FullCmd 'PCMPEQD'   GOTO_REL16, arg__MMXMEM_, 0760fh
_pcmpgtb:  FullCmd 'PCMPGTB'   GOTO_REL16, arg__MMXMEM_, 0640fh
_pcmpgtw:  FullCmd 'PCMPGTW'   GOTO_REL16, arg__MMXMEM_, 0650fh
_pcmpgtd:  FullCmd 'PCMPGTD'   GOTO_REL16, arg__MMXMEM_, 0660fh
_pand:     FullCmd 'PAND'      GOTO_REL16, arg__MMXMEM_, 0db0fh
_pandn:    FullCmd 'PANDN'     GOTO_REL16, arg__MMXMEM_, 0df0fh
_por:      FullCmd 'POR'       GOTO_REL16, arg__MMXMEM_, 0eb0fh
_pxor:     FullCmd 'PXOR'      GOTO_REL16, arg__MMXMEM_, 0ef0fh

_cs:    PartCmd 'CS:'      GOTO_REL16, arg__PREFINS, 002Eh
_ds:    PartCmd 'DS:'      GOTO_REL16, arg__PREFINS, 003Eh
_es:    PartCmd 'ES:'      GOTO_REL16, arg__PREFINS, 0026h
_fs:    PartCmd 'FS:'      GOTO_REL16, arg__PREFINS, 0064h
_gs:    PartCmd 'GS:'      GOTO_REL16, arg__PREFINS, 0065h
_ss:    PartCmd 'SS:'      GOTO_REL16, arg__PREFINS, 0036h
_esc:   PartCmd 'F'        GOTO_REL16, X87_Opcodes,  0000h

;** Alternative names used by Assembler

        FullCmd 'REPZ'     GOTO_REL16, arg__PREFINS, 00F3h
        FullCmd 'REPNZ'    GOTO_REL16, arg__PREFINS, 00F2h
        FullCmd 'REP'      GOTO_REL16, arg__PREFINS, 00F3h

        FullCmd 'JNLE'     GOTO_REL16, arg__RELJMP3, 007fh
        FullCmd 'JNL'      GOTO_REL16, arg__RELJMP3, 007dh
        FullCmd 'JNGE'     GOTO_REL16, arg__RELJMP3, 007ch
        FullCmd 'JNG'      GOTO_REL16, arg__RELJMP3, 007eh
        FullCmd 'JPE'      GOTO_REL16, arg__RELJMP3, 007ah
        FullCmd 'JPO'      GOTO_REL16, arg__RELJMP3, 007bh
        FullCmd 'JB'       GOTO_REL16, arg__RELJMP3, 0072h
        FullCmd 'JNAE'     GOTO_REL16, arg__RELJMP3, 0072h
        FullCmd 'JNA'      GOTO_REL16, arg__RELJMP3, 0076h
        FullCmd 'JNBE'     GOTO_REL16, arg__RELJMP3, 0077h
        FullCmd 'JNB'      GOTO_REL16, arg__RELJMP3, 0073h
        FullCmd 'JNZ'      GOTO_REL16, arg__RELJMP3, 0075h
        FullCmd 'JAE'      GOTO_REL16, arg__RELJMP3, 0073h
        FullCmd 'JZ'       GOTO_REL16, arg__RELJMP3, 0074h
        FullCmd 'LOOPZ'    GOTO_REL16, arg__RELJMP1, 00e1h
        FullCmd 'LOOPNZ'   GOTO_REL16, arg__RELJMP1, 00e0h
        FullCmd 'SETNLE'   GOTO_REL16, arg__RM8____, 9F0Fh
        FullCmd 'SETNL'    GOTO_REL16, arg__RM8____, 9D0Fh
        FullCmd 'SETNG'    GOTO_REL16, arg__RM8____, 9E0Fh
        FullCmd 'SETNGE'   GOTO_REL16, arg__RM8____, 9C0Fh
        FullCmd 'SETPE'    GOTO_REL16, arg__RM8____, 9A0Fh
        FullCmd 'SETPO'    GOTO_REL16, arg__RM8____, 9B0Fh
        FullCmd 'SETNA'    GOTO_REL16, arg__RM8____, 960Fh
        FullCmd 'SETB'     GOTO_REL16, arg__RM8____, 920Fh
        FullCmd 'SETNZ'    GOTO_REL16, arg__RM8____, 950Fh
        FullCmd 'SETZ'     GOTO_REL16, arg__RM8____, 940Fh
        FullCmd 'SETNB'    GOTO_REL16, arg__RM8____, 930Fh
        FullCmd 'SETNBE'   GOTO_REL16, arg__RM8____, 970Fh
        FullCmd 'CMOVB'    GOTO_REL16, arg__R16_RM2, 420Fh
        FullCmd 'CMOVNB'   GOTO_REL16, arg__R16_RM2, 430Fh
        FullCmd 'CMOVZ'    GOTO_REL16, arg__R16_RM2, 440Fh
        FullCmd 'CMOVNZ'   GOTO_REL16, arg__R16_RM2, 450Fh
        FullCmd 'CMOVNA'   GOTO_REL16, arg__R16_RM2, 460Fh
        FullCmd 'CMOVNBE'  GOTO_REL16, arg__R16_RM2, 470Fh
        FullCmd 'CMOVPE'   GOTO_REL16, arg__R16_RM2, 4A0Fh
        FullCmd 'CMOVPO'   GOTO_REL16, arg__R16_RM2, 4B0Fh
        FullCmd 'CMOVNG'   GOTO_REL16, arg__R16_RM2, 4E0Fh
        FullCmd 'CMOVNGE'  GOTO_REL16, arg__R16_RM2, 4C0Fh
        FullCmd 'CMOVNL'   GOTO_REL16, arg__R16_RM2, 4D0Fh
        FullCmd 'CMOVNLE'  GOTO_REL16, arg__R16_RM2, 4F0Fh
        FullCmd 'SAL'      GOTO_REL16, arg__ROTATE_, 020D3h

        db 0
        ret             ; return with CF=1

X87_Opcodes:
         call    Parse_LineNoSkip ; do not skip blanks
;---------------------------------------- 287 instructions -------------------
_fld1:   FullCmd 'LD1'      GOTO_REL16, arg__NOPRND2, 0E8D9h
_fldl2t: FullCmd 'LDL2T'    GOTO_REL16, arg__NOPRND2, 0E9D9h
_fldl2e: FullCmd 'LDL2E'    GOTO_REL16, arg__NOPRND2, 0EAD9h
_fldpi:  FullCmd 'LDPI'     GOTO_REL16, arg__NOPRND2, 0EBD9h
_fldlg2: FullCmd 'LDLG2'    GOTO_REL16, arg__NOPRND2, 0ECD9h
_fldln2: FullCmd 'LDLN2'    GOTO_REL16, arg__NOPRND2, 0EDD9h
_fldz:   FullCmd 'LDZ'      GOTO_REL16, arg__NOPRND2, 0EED9h
_fnop:   FullCmd 'NOP'      GOTO_REL16, arg__NOPRND2, 0D0D9h
_fchs:   FullCmd 'CHS'      GOTO_REL16, arg__NOPRND2, 0E0D9h
_fabs:   FullCmd 'ABS'      GOTO_REL16, arg__NOPRND2, 0E1D9h
_ftst:   FullCmd 'TST'      GOTO_REL16, arg__NOPRND2, 0E4D9h
_fxam:   FullCmd 'XAM'      GOTO_REL16, arg__NOPRND2, 0E5D9h
_fprem1: FullCmd 'PREM1'    GOTO_REL16, arg__NOPRND2, 0F5D9h
_fprem:  FullCmd 'PREM'     GOTO_REL16, arg__NOPRND2, 0F8D9h
_fyl2xp1:FullCmd 'YL2XP1'   GOTO_REL16, arg__NOPRND2, 0F9D9h
_fyl2x:  FullCmd 'YL2X'     GOTO_REL16, arg__NOPRND2, 0F1D9h
_f2xm1:  FullCmd '2XM1'     GOTO_REL16, arg__NOPRND2, 0F0D9h
_fptan:  FullCmd 'PTAN'     GOTO_REL16, arg__NOPRND2, 0F2D9h
_fpatan: FullCmd 'PATAN'    GOTO_REL16, arg__NOPRND2, 0F3D9h
_fsqrt:  FullCmd 'SQRT'     GOTO_REL16, arg__NOPRND2, 0FAD9h
_frndint:FullCmd 'RNDINT'   GOTO_REL16, arg__NOPRND2, 0FCD9h
_fscale: FullCmd 'SCALE'    GOTO_REL16, arg__NOPRND2, 0FDD9h
_fsincos:FullCmd 'SINCOS'   GOTO_REL16, arg__NOPRND2, 0FBD9h
_fsin:   FullCmd 'SIN'      GOTO_REL16, arg__NOPRND2, 0FED9h
_fcos:   FullCmd 'COS'      GOTO_REL16, arg__NOPRND2, 0FFD9h
_fxtract:FullCmd 'XTRACT'   GOTO_REL16, arg__NOPRND2, 0F4D9h
_feni:   FullCmd 'ENI'      GOTO_REL16, arg__NOPRND2, 0E0DBh
_fdisi:  FullCmd 'DISI'     GOTO_REL16, arg__NOPRND2, 0E1DBh
_fclex:  FullCmd 'CLEX'     GOTO_REL16, arg__NOPRND2, 0E2DBh
_finit:  FullCmd 'INIT'     GOTO_REL16, arg__NOPRND2, 0E3DBh
_fsetpm: FullCmd 'SETPM'    GOTO_REL16, arg__NOPRND2, 0E4DBh
_fdecstp:FullCmd 'DECSTP'   GOTO_REL16, arg__NOPRND2, 0F6D9h
_fincstp:FullCmd 'INCSTP'   GOTO_REL16, arg__NOPRND2, 0F7D9h
_fldenv: FullCmd 'LDENV'    GOTO_REL16, arg__MEMADR_, 020D9h
_fldcw:  FullCmd 'LDCW'     GOTO_REL16, arg__MEMADR_, 028D9h
_fstenv: FullCmd 'STENV'    GOTO_REL16, arg__MEMADR_, 030D9h
_fstcw:  FullCmd 'STCW'     GOTO_REL16, arg__MEMADR_, 038D9h
_frstor: FullCmd 'RSTOR'    GOTO_REL16, arg__MEMADR_, 020DDh
_fsave:  FullCmd 'SAVE'     GOTO_REL16, arg__MEMADR_, 030DDh
_fstsw:  FullCmd 'STSW'     GOTO_REL16, arg__MEMADR_, 038DDh
_fadd:   PartCmd 'ADD'      GOTO_REL16, x87_Check4P, 11000100b
_fmul:   PartCmd 'MUL'      GOTO_REL16, x87_Check4P, 11001100b
_fsubr:  PartCmd 'SUBR'     GOTO_REL16, x87_Check4P, 11101100b
_fsub:   PartCmd 'SUB'      GOTO_REL16, x87_Check4P, 11100100b
_fcomp:  PartCmd 'COMP'     GOTO_REL16, x87_Check4P, 11011100b
_fcom:   PartCmd 'COM'      GOTO_REL16, x87_Check4P, 11010100b
_fdivr:  PartCmd 'DIVR'     GOTO_REL16, x87_Check4P, 11111100b
_fdiv:   PartCmd 'DIV'      GOTO_REL16, x87_Check4P, 11110100b
_fstp:   PartCmd 'STP'      GOTO_REL16, x87_MemAddr, 11011101b
_fst:    PartCmd 'ST'       GOTO_REL16, x87_MemAddr, 11010101b
_fld:    PartCmd 'LD'       GOTO_REL16, x87_MemAddr, 11000001b
_fucomp: PartCmd 'UCOMP'    GOTO_REL16, x87_ST_n,    11101101b
_fucom:  PartCmd 'UCOM'     GOTO_REL16, x87_ST_n,    11100101b
_fxch:   PartCmd 'XCH'      GOTO_REL16, x87_ST_n,    11001001b
_ffree:  PartCmd 'FREE'     GOTO_REL16, x87_ST_n,    11000101b
         db 0
         ret
_f???:   db 1,'?'

; IN:   DS:ESI  = ptr data
; OUT:  CF=0    EAX = hex data
;       CF=1    no hex data
getHexValue:
        push    ebx
        xor     ecx, ecx
        call    Skip_Blanks
        cmp     al, '+'
        je      short gh_Val1
        cmp     al, '-'
        jne     short gh_Val2
        inc     ecx
gh_Val1:inc     esi
gh_Val2:call    Scan_Hex
        xchg    eax, ebx
        jc      short gh_Val3
        jecxz   short gh_Val3
        neg     eax
        clc
gh_Val3:pop     ebx
        ret

getHexWord:
        call    getHexValue
        jc      short ghw_1
        movzx   ecx, ax
        xor     ecx, eax
        jz      short ghw_1
        movsx   ecx, ax
        xor     ecx, eax
        neg     ecx
ghw_1:  ret

arg__STRSIZE:
        xchg    ebx, eax        ;opcode
        lodsb                   ;B/W/D
        and     al, not 20h
        cmp     al, 'B'
        je      short arg_put2
        inc     ebx              ;bit0=1 for word/dword
        or      dl, RM__WORD + RM__DATA
        cmp     al, 'W'
        je      short arg_put2
        cmp     al, 'D'
        jne     short arg_Error1
        or      dh, PRE_OPR32
arg_put2:
        xchg    eax, ebx
arg__SEGOVR1:
        stosb
        call    getSegOvr
        clc
        ret

getSeg1:test    dh, PRE_SMASK
        jnz     short getSegErr
        or      dh, al
        ret
getSegErr:
        sub     esi, 3
arg_Error1:
        stc
        ret

Opr@_relwrd:    ;rel.16/32
        call    getHexValue
        jc      short rl16ret
        sub     eax, actual_IP
        sub     eax, 3          ; jumps are 3 bytes
do__relwrd:
        mov     dl, RM__DWRD    ; dword size
        test    def_segsize, DEFSEG_OPR32
        jnz     short do__rel32
        movsx   ebx, ax
        xor     ebx, eax
        jz      short arg__NOPRND2
        movsx   ebx, ax
        xor     ebx, eax
        jz      short arg__NOPRND2
        movzx   ebx, ax
        xor     ebx, eax
        jz      short arg__NOPRND2
        dec     eax             ; 1 more for address prefix
do__rel32:
        dec     eax             ; 2 more bytes for dword vs word
        dec     eax
        stosd
        or      dh, PRE_ADR32
rl16ret:ret

arg__NOPRND2:
        stosw
        ret

arg__RELJMP3:                           ;8/16/32 bit destinations
        stosb
        call    getHexValue
        jc      short rl16ret
        call    dst_rel8
        jnc     short rl16ret
        dec     eax
        dec     eax                     ;rel eip+4/eip+5
        xchg    ebx, eax
        mov     al, 0fh
        xchg    al, [edi-1]
        add     al, 10h                 ;7x -> 0f 8x
        stosb
        xchg    eax, ebx
        jmp     short do__relwrd

arg__RELJMP2:
        mov     dl, RM__DATA    ;jecxz/jcxz
        or      dh, ah          ;PRE_OPR32
arg__RELJMP1:
        stosb
Opr@_rel8:      ;rel.8
        call    getHexValue
        jc      short arg_Error
dst_rel8:
        sub     eax, actual_IP
        sub     eax, 2          ; short jumps are 2 bytes
        movsx   ebx, al
        xor     ebx, eax
        je      short arg_put1
arg_Error:
        stc
        ret

arg__WRDSIZE:
        mov     ah, not 20h
        and     ah, [esi]
        cmp     ah, 'D'
        jne     short arg__16BIT
        inc     esi
arg__32BIT:
        or      dl, RM__DATA
        or      dh, PRE_OPR32
arg__NOPRND1:
arg_put1:
        stosb
        clc
        ret

arg__16BIT:
        or      dl, RM__DATA
        and     dh, not PRE_OPR32
        stosb
        ret

arg__MULTYPE:
        lea     ebp, Opcodes_Start[eax]
        mov     asmInputPtr, esi
decode_Loop:
        mov     edi, asmBufPtr
decode_L1:
        movzx   eax, byte ptr [ebp]
        inc     ebp
        stosb
        movzx   ebx, word ptr opcode1[eax*4][0]
        mov     cl, byte ptr opcode1[eax*4][2]
decode_L2:
        and     ecx, 3fh
        jnz     short decode_L3
        mov     al, [ebp]
        inc     ebp
        stosb
        and     al, 7*8
        shr     al, 1
        mov     cl, byte ptr opcode2[ebx+eax][2]
        and     ecx, 3fh
decode_L3:
        call    dword ptr OprndTypeTable[ecx*4]
        jc      short decode_L4
        call    Skip_Blanks
        jz      short decode_L6
decode_L4:
        mov     esi, asmInputPtr
        xor     edx, edx                ; reset flags
        cmp     byte ptr [ebp], 0f1h ; nop as end of list
        jne     short decode_Loop
decode_L5:
        stc                     ; not found
decode_L6:
        ret

Opr@_0fp:       ;0F prefix
        pop     ebx                     ;remove ret from stack
        mov     al, [ebp]
        inc     ebp
        stosb
        mov     ebx, eax
        shr     bl, 3
        and     al, 7
        add     al, sysinst[ebx]
        cmp     al, 0f8h
        jae     short decode_L5         ;invalid
        movzx   ebx, word ptr opcode_0f[eax*4][0]
        mov     cl, byte ptr opcode_0f[eax*4][2]
        jmp     decode_L2

Opr@_none:      ;no operand inst's
Opr@_prefix:    ;Prefix instructions
Opr@_segovr:    ;seg: override
        clc
        ret

Dual_Operand_A0:
        mov     al, 0
        stosb
Dual_Operand:
        mov     asmRmPtr, edi    ; passed r/m byte
        pop     ebx
        lea     ecx, 12[ebx]
        push    ecx
        push    ebx
        call    [ebx+0]
        pop     ebx
        jc      short Dual_Oprnd1
        push    dword ptr [ebx+8]
        call    [ebx+4]
        pop     ecx
        jc      short Dual_Oprnd1
        call    Skip_Blanks
        cmp     al, ','
        jne     short Bad_Operand
        inc     esi
        call    ecx
        jnc     short Dual_OprRet
Dual_Oprnd1:
        pop     ebx
Bad_Operand:
        stc
Dual_OprRet:
        ret

Opr@_in_nn:     ;in al/ax/eax,nn
        call    Dual_Operand
        dd      OFFSET32 opr_Accu
        dd      OFFSET32 just_ret
        dd      OFFSET32 opr_Byte
        ret

Opr@_in_dx:     ;in al/ax/eax,dx
        call    Dual_Operand
        dd      OFFSET32 opr_Accu
        dd      OFFSET32 just_ret
        dd      OFFSET32 opr_Dx
        ret

Opr@_out_nn:    ;out nn,al/ax/eax
        call    Dual_Operand
        dd      OFFSET32 opr_Byte
        dd      OFFSET32 just_ret
        dd      OFFSET32 opr_Accu
just_ret:
        ret

Opr@_out_dx:    ;out dx,al/ax/eax
        call    Dual_Operand
        dd      OFFSET32 opr_Dx
        dd      OFFSET32 just_ret
        dd      OFFSET32 opr_Accu
        ret

Opr@_addr_acc:  ;address,acc
        call    save_rmbyte
        call    Dual_Operand
        dd      OFFSET32 get_MemAddr
        dd      OFFSET32 chk_direct
        dd      OFFSET32 opr_Accu
        ret

Opr@_r16:       ;r16    .....rrr
        call    get_RegWordDword
        jnc     short or_reg
        ret

Opr@_r32:       ;r32    .....rrr
        call    get_RegDword
        jnc     short or_reg
        ret

or_wrrr:        ; 0000wrrr
        test    dl, RM__WORD OR RM__DWRD
        jz      short or_reg
        or      al, 8           ; w-bit
or_reg: or      [edi-1], al
        ret

Opr@_seg:       ;seg    ...ss...
        call    get_segRegister1
        jnc     short or_reg
        ret

Opr@_fs_gs:     ;push/pop fs/gs
        call    get_segRegister2
        jnc     short or_reg
        ret

opr_Dx: call    Parse_Line
        FullCmd 'DX'   GOTO_REL16, dx_found, 0000h
        db 0
dx_found:
        ret

Int_Opcode:
        stosb                           ; CD
        call    opr_Byte                ; nn
        jc      short intOp2
        cmp     al, 3
        jne     short intOp1
        dec     edi
        mov     byte ptr [edi-1], 0cch
intOp1: clc
intOp2: ret

Opr@_sx8:       ;+nn/-nn
opr_sx8:call    getHexValue
        jc      short @f
        stosb
        movsx   ecx, al
        xor     ecx, eax
        neg     ecx             ; cf if non-zero
@@:     ret

opr_ByteWord:
        test    dl, RM__BYTE
        jz      short opr_WordDword

Opr@_int_nn:    ;int nn
Opr@_nn:        ;nn
opr_Byte:
        call    getHexWord
        adc     ah, 0ffh        ; cf if CF=1 or ah>0
        stosb
        ret

Opr@_nnnnw:     ;nnnn (16/32) (push)
        test    def_segsize, DEFSEG_OPR32
        jnz     short opr_Dword
opr_WordDword:
        test    dl, RM__DWRD
        jz      short opr_Word
opr_Dword:
        call    getHexValue
        stosd
        ret

arg__OPTWORD:
        stosb
        call    Skip_Blanks
        jz      short opdwret
        dec     byte ptr [edi-1]
Opr@_nnnn:      ;nnnn (16)
opr_Word:
        call    getHexWord
opwput: stosw
opdwret:ret

arg__WRD_BYT:   ;
        stosb
Opr@_nnnn_nn:   ;nnnn,nn (enter)
        call    Dual_Operand
        dd      OFFSET32 opr_Word
        dd      OFFSET32 just_ret
        dd      OFFSET32 opr_Byte
        ret

Opr@_reg_imm:   ;reg,imm  ....wrrr imm 
        call    Dual_Operand
        dd      OFFSET32 get_Register
        dd      OFFSET32 or_wrrr         ; 0000wrrr
        dd      OFFSET32 opr_ByteWord
        ret

Opr@_acc_imm:   ;acc,imm
        call    Dual_Operand
        dd      OFFSET32 opr_Accu
        dd      OFFSET32 just_ret
        dd      OFFSET32 opr_ByteWord
        ret

Opr@_ax_r16:    ;ax,r16 .....rrr
        dec     byte ptr [edi-1]         ; 91 used instead of 90 (=nop)
        call    chk_ax_r16
        jnc     short @f
        call    Dual_Operand
        dd      OFFSET32 get_RegWordDword
        dd      OFFSET32 or_reg
        dd      OFFSET32 opr_Accu
        cmp     al, 1
        je      short @f
        stc
@@:     ret

chk_ax_r16:
        call    Dual_Operand
        dd      OFFSET32 opr_Accu
        dd      OFFSET32 chk_4word
        dd      OFFSET32 get_RegWordDword
        jmp     or_reg

Opr@_reg_rm_sx8:  ;reg,r/m,+n/-n (imul)
        call    Dual_Operand
        dd      OFFSET32 Opr@_reg_rm
        dd      OFFSET32 just_ret
        dd      OFFSET32 Opr@_sx8
        ret

Opr@_reg_rm_nnnn: ;reg,r/m,nnnn  (imul)
        call    Dual_Operand
        dd      OFFSET32 Opr@_reg_rm
        dd      OFFSET32 just_ret
        dd      OFFSET32 opr_WordDword
        ret

arg__R16_RM2:   ;
        stosb
        xchg    al, ah
arg__R16_MEM:   ;
        stosb
Opr@_r16_rm:    ;reg,r/m (word)
        or      dl, RM__DATA
        call    Dual_Operand_A0
        dd      OFFSET32 get_RegWordDword
        dd      OFFSET32 or_00rrr000
        dd      OFFSET32 get_RegOrMem
        ret

Opr@_reg_rm:    ;reg,r/m (8/16)
        call    Dual_Operand_A0
        dd      OFFSET32 get_Register
        dd      OFFSET32 put_reg_w
        dd      OFFSET32 get_RegOrMem
        ret

arg__MEM_R16:
        stosb
Opr@_rm_r16:    ;r/m,reg (16/32)
        call    Dual_Operand_A0
        dd      OFFSET32 get_RegOrMem
        dd      OFFSET32 just_ret
        dd      OFFSET32 get_RegWordDword
        jmp     or_00rrr000

Opr@_rm_reg:    ;r/m,reg (8/16)
        call    Dual_Operand_A0
        dd      OFFSET32 get_RegOrMem
        dd      OFFSET32 just_ret
        dd      OFFSET32 get_Register
put_reg_w:
        call    or_00rrr000
clr_w_bit:
        test    dl, RM__BYTE
        jz      short @f
        mov     ebx, asmRmPtr
        and     byte ptr [ebx-2], not 1 ; w-bit
@@:     ret

arg__REGMEM_:   ; hh+w ll+rm            NOT
        stosw
Opr@_rm:        ;r/m    .......w mm...r/m (byte/word)
        call    get_RegOrMem
        jnc     short clr_w_bit
        ret

arg__MMXMEM_:
        stosw
Opr@_mmx_rm64:
        call    Dual_Operand_A0
        dd      OFFSET32 get_mmx
        dd      OFFSET32 or_00rrr000
        dd      OFFSET32 get_MmxOrMem
        ret

Opr@_mmx_rm32:
        call    Dual_Operand_A0
        dd      OFFSET32 get_mmx
        dd      OFFSET32 or_00rrr000
        dd      OFFSET32 get_RegOrMemWord
        ret

Opr@_mmx_imm8:
        call    Dual_Operand
        dd      OFFSET32 get_MmxOrMem
        dd      OFFSET32 just_ret
        dd      OFFSET32 opr_Byte
        ret

Opr@_rm64_mmx:
        call    Dual_Operand_A0
        dd      OFFSET32 get_MmxOrMem
        dd      OFFSET32 just_ret
        dd      OFFSET32 get_mmx
        jmp     or_00rrr000

Opr@_rm32_mmx:
        call    Dual_Operand_A0
        dd      OFFSET32 get_RegOrMemWord
        dd      OFFSET32 just_ret
        dd      OFFSET32 get_mmx
        jmp     or_00rrr000

get_MmxOrMem:
        call    get_mmx
        jc      get_MemAddr
        or      al, 0c0h
        or      [edi-1], al
        ret

get_mmx:
        call    Parse_Line
        PartCmd 'MM'    JUMP_ADDRS, <OFFSET32 mmx_regno>
        db 0
        ret             ; return with CF=1

mmx_regno:
        lodsb
        sub     al, '0'
        cmp     al, 8
        cmc
        ret

arg__SHLRD__:   ; hh ll+w rm    SHLD  r,rm,cl/nn
        stosw                   ; opcode for rmb,nn
Opr@_rm_r16_sc: ;r/m,r16,cl/nn (shld/shrd)
        call    Dual_Operand
        dd      OFFSET32 Opr@_rm_r16
        dd      OFFSET32 just_ret
        dd      OFFSET32 opr_SC
        neg     ah              ; cf if nn is the count
        mov     ebx, asmRmPtr
        sbb     byte ptr [ebx-2], 0
        ret

Opr@_acc_addr:  ;acc,address
        call    Dual_Operand
        dd      OFFSET32 opr_Accu
        dd      OFFSET32 save_rmbyte
        dd      OFFSET32 get_MemAddr
chk_direct:
        mov     ebx, asmRmPtr
        mov     al, saved_rmbyte
        mov     [ebx-1], al
        bt      edx, RM__DIRA_BIT
        cmc
        ret

save_rmbyte:
        mov     al, [edi-1]
        mov     saved_rmbyte, al
        ret

Opr@_seg_rm:    ;seg,r/m
        call    Dual_Operand_A0
        dd      OFFSET32 get_segRegisters
        dd      OFFSET32 or_reg
        dd      OFFSET32 get_RegOrMemWord
        ret

Opr@_rm_seg:    ;r/m,seg
        call    Dual_Operand_A0
        dd      OFFSET32 get_RegOrMemWord
        dd      OFFSET32 just_ret
        dd      OFFSET32 get_segRegisters
        jmp     short or_rmByte

Opr@_rmw_nn:    ;bit operations r/m16/32,imm8
        call    Dual_Operand
        dd      OFFSET32 get_RegOrMem
        dd      OFFSET32 chk_4word
        dd      OFFSET32 opr_Byte
        ret

Opr@_rm_sx8:    ;r/m,+n/-n
        call    Dual_Operand
        dd      OFFSET32 get_RegOrMem
        dd      OFFSET32 chk_4word
        dd      OFFSET32 Opr@_sx8
        ret

or_00rrr000_dl0:
        mov     dl, 0
or_00rrr000:
        shl     al, 3
or_rmByte:
        mov     ebx, asmRmPtr
        or      [ebx-1], al
        ret

Opr@_r16_rm8:   ;r16/r32,rm8 (movsx/movzx)
        call    Dual_Operand_A0
        dd      OFFSET32 get_RegWordDword
        dd      OFFSET32 or_00rrr000_dl0
        dd      OFFSET32 get_RegOrMemByte
        and     dl, not RM__BYTE                ;ignore byte type
        or      dl, RM__DATA                    ;16/32-bit opcode
        ret

Opr@_r32_rm16:  ;r32,rm16 (movsx/movzx)
        call    Dual_Operand_A0
        dd      OFFSET32 get_RegDword
        dd      OFFSET32 or_00rrr000
        dd      OFFSET32 get_RegOrMem
        or      dh, PRE_OPR32                   ;32-bit opcode
        or      dl, RM__WORD + RM__DATA
        test    dl, RM__BYTE + RM__DWRD
        jz      short @f
        stc
@@:     ret

spc_reg:call    Dual_Operand
        dd      OFFSET32 get_SpcialReg
        dd      OFFSET32 or_spcreg
        dd      OFFSET32 get_RegWordDword
spc_is32:
        or      dl, RM__DATA
        and     dh, not PRE_OPR32
        jmp     or_reg

Opr@_0f_2x:     ;mov CRn/DRn/TRn,r/m
        mov     al, 0c0h
        stosb
        call    spc_reg
        jnc     short spc_ret
        mov     edi, asmRmPtr
        call    Dual_Operand
        dd      OFFSET32 get_RegWordDword
        dd      OFFSET32 spc_is32
        dd      OFFSET32 get_SpcialReg
        xor     ah, al
or_spcreg:
        lodsb
        sub     al, '0'
        cmp     al, 8
        jae     short oprError1
        or      [edi-2], ah
        jmp     or_00rrr000

get_SpcialReg:
        call    Parse_Line
        PartCmd 'CR'   GOTO_REL16 spc_ret 2202h
        PartCmd 'DR'   GOTO_REL16 spc_ret 2302h
        PartCmd 'TR'   GOTO_REL16 spc_ret 2602h
        db      0
Opr@_float:     ;ESC nn,r/m
Opr@_16_or_32:  ;cbw(cwde)/cwd(cdq)
Opr@_d_for_32:  ;push/pop/pushf/popf/iret (+d when 32)
Opr@_32ovr:     ;32 bit override (op32/ad32)
Opr@_sb_or_sw:  ;sw/sd in ins lods/scas/movs/cmps/stos
oprError1:
        stc
spc_ret:
r32Ret: ret


Opr@_seg_off:   ;seg:off
        call    getHexWord
        jc      short oprError1
        xchg    ebx, eax
        call    Skip_Blanks
        cmp     al, ':'
        jne     short oprError1
        inc     esi
        call    getHexValue
        jc      short oprError1
        or      dl, RM__DWRD
        test    def_segsize, DEFSEG_OPR32
        jnz     short @f
        movzx   ecx, ax
        xor     ecx, eax
        jnz     short @f
        stosw
        xchg    ebx, eax
        stosw
        ret
@@:     or      dh, PRE_ADR32
        stosd
        xchg    ebx, eax
        stosw
        ret

arg__ROTATE_:     ; hh+i+c+w ll+rm        SHL  rm,1/cl/nn
        stosw
Opr@_rm_sc:     ;r/m,1/cl/nn
        call    Dual_Operand
        dd      OFFSET32 get_RegOrMem
        dd      OFFSET32 clr_w_bit
        dd      OFFSET32 opr_SC
        test    ah, ah
        jz      short rmscRet   ; if CL is count
        cmp     al, 1
        jne     short @f
        mov     ah, 2
        dec     edi
@@:     mov     ebx, asmRmPtr
        xor     [ebx-2], ah
rmscRet:ret

opr_SC: call    Parse_Line
        FullCmd 'CL'   GOTO_REL16 sccl_ret 0000h
        db 0
        call    opr_Byte
        mov     ah, 12h
sccl_ret:
        ret

; **-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**
; 
; **-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**-**

arg__0F_MEM_:     ; 0F hh ll+rmw
        mov     byte ptr [edi], 0fh
        inc     edi
        stosw
        jmp     short get_RegOrMemWord

Opr@_rm_imm:    ;r/m,imm  .......w r/m imm
        call    Dual_Operand
        dd      OFFSET32 get_RegOrMem
        dd      OFFSET32 clr_w_bit
        dd      OFFSET32 opr_ByteWord
        ret

arg__RM8____:   ; hh ll 00+rmb          SETcc
        stosw
Opr@_rmb:       ;r/m    ........ mmxxxr/m (setcc byte)
        mov     al, 0
        stosb
get_RegOrMemByte:
        call    get_RegOrMem
        jc      short gm_err2
        test    dl, RM__WORD + RM__DWRD
        jnz     short gm_err2
        or      dl, RM__BYTE
        ret

Opr@_rmw:       ;r/m (16/32)
get_RegOrMemWord:
        call    get_RegOrMem
chk_4word:
        jc      short @f
        test    dl, RM__FWRD + RM__QWRD + RM__BYTE ; word and dwords are ok
        jz      short @f
gm_err2:stc
@@:     ret

Opr@_mem24:     ;r/m (gdt/idt)
        call    get_MemAddr
        test    dl, RM__WORD + RM__BYTE ; dword and fwords are ok
        jz      short @f
        stc
@@:     ret

get_RegOrMem:
        call    get_Register0
        jc      short get_MemAddr
        or      al, 0c0h
        or      [edi-1], al
        ret

arg__MEMADR_:   ; memory address (not registers)
        stosw
Opr@_dword:     ; r/m (dword) (used in opcode2) (0=inst2)
get_MemAddr:
        ; In:   EDI-1 => [mmxxxr/m]
        ;       ESI => x[r1+r2+y]
        DBGBRK  5
        xor     eax, eax
        mov     [edi], eax              ; base address
        mov     [edi+4], eax            ; reg1, reg2
getMem1:call    Parse_Line
        PartCmd '['     GOTO_REL16 getMem3 RM__ADDR
        FullCmd 'BYTE'  GOTO_REL16 getMem2 RM__BYTE
        FullCmd 'WORD'  GOTO_REL16 getMem2 <RM__WORD + RM__DATA>
        FullCmd 'DWORD' GOTO_REL16 getMem2 <PRE_OPR32*100h + RM__DWRD + RM__DATA>
        FullCmd 'FWORD' GOTO_REL16 getMem2 <PRE_OPR32*100h + RM__FWRD + RM__DWRD + RM__DATA>
        FullCmd 'QWORD' GOTO_REL16 getMem2 <PRE_OPR32*100h + RM__QWRD + RM__DWRD + RM__DATA>
        db 0
        call    getSegOvr
        jnc     short getMem1
        call    getHexValue
        jc      short gm_err1
        add     [edi], eax
        jmp     getMem1

getMem2:or      edx, eax
        xor     al, RM__DWRD + RM__WORD + RM__BYTE
        and     al, dl
        and     al, RM__DWRD + RM__WORD + RM__BYTE
        jnz     short gm_err1
        call    Parse_Line
        FullCmd 'PTR'   GOTO_REL16, getMem1, 0
        db 0
        jmp     getMem1

gm_err1:stc
        ret

getMem3:or      dl, al                  ; al=RM__ADDR
getMem4:
        DBGBRK  5
        call    get_Reg32Address
        jnc     getAddr32
        call    Parse_Line
adrmod0:FullCmd 'BX+SI' GOTO_REL16 getAddr16 0000h
        FullCmd 'SI+BX' GOTO_REL16 getAddr16 0000h
adrmod1:FullCmd 'BX+DI' GOTO_REL16 getAddr16 0001h
        FullCmd 'DI+BX' GOTO_REL16 getAddr16 0001h
adrmod2:FullCmd 'BP+SI' GOTO_REL16 getAddr16 0002h
        FullCmd 'SI+BP' GOTO_REL16 getAddr16 0002h
adrmod3:FullCmd 'BP+DI' GOTO_REL16 getAddr16 0003h
        FullCmd 'DI+BP' GOTO_REL16 getAddr16 0003h
adrmod4:FullCmd 'SI'    GOTO_REL16 getAddr16 0004h
adrmod5:FullCmd 'DI'    GOTO_REL16 getAddr16 0005h
adrmod6:FullCmd 'BP'    GOTO_REL16 getAddr16 0006h
adrmod7:FullCmd 'BX'    GOTO_REL16 getAddr16 0007h
        db 0
getMem5:call    getHexValue
        jc      short getMem6
        add     [edi], eax
getMem6:call    Skip_Blanks
        cmp     al, '-'
        je      getMem5
        inc     esi
        cmp     al, '+'
        je      getMem4
        cmp     al, ']'
        jne     short getMemErr

        ; its a direct address
        or      dl, RM__DIRA
        mov     eax, [edi]
        test    def_segsize, DEFSEG_ADR32
        jnz     short @f
        movzx   ecx, ax
        xor     ecx, eax
        jnz     short @f
        xor     byte ptr [edi-1], 06h   ; [d16]
        stosw
        ret
@@:     or      dh, PRE_ADR32
        xor     byte ptr [edi-1], 05h   ; [d32]
        stosd
        ret

getAddr16:
        or      [edi-1], al
        jmp     short a16get2

a16get1:call    getHexValue
        jc      short getMemErr
        add     [edi], eax
a16get2:call    Skip_Blanks
        cmp     al, '-'
        je      short a16get1
        cmp     al, '+'
        je      short a16get1
        cmp     al, ']'
        je      short a16finish
getMemErr:
        stc
        ret

a16finish:
        inc     esi
        lea     ebx, [edi-1]
        mov     ecx, [edi]
        mov     al, [ebx]
        and     al, 7
        cmp     al, 6                   ;[bp] => [bp+0]
        je      short @f
        jecxz   short off_d0
@@:     movsx   eax, cl
        cmp     eax, ecx
        je      short off_d8

        movzx   eax, cx
        cmp     ecx, eax
        jz      short off_d16
        movsx   eax, cx
        xor     ecx, eax
        jnz     short getMemErr2
off_d16:or      byte ptr [ebx], 80h     ; +d16
        stosw
off_d0: clc
        ret

getAddr32:
        or      dh, PRE_ADR32
a32get3:xchg    [edi+4], al
        xchg    [edi+5], al
        test    al, al
        jz      short a32get4
getMemErr2:
        stc
        ret

a32get1:inc     esi
        call    get_Reg32Address
        jnc     short a32get3
a32get2:call    getHexValue
        jc      short getMemErr2
        add     [edi], eax
a32get4:call    Skip_Blanks
        cmp     al, '-'
        je      short a32get2
        cmp     al, '+'
        je      short a32get1
        cmp     al, ']'
        jne     short getMemErr2
        inc     esi
        DBGBRK  5
        mov     ecx, [edi]              ; offset
        mov     eax, [edi+4]            ; reg1, reg2
        lea     ebx, [edi-1]            ; ptr r/m byte

        cmp     al, ah
        jae     short @f
        xchg    al, ah
@@:     test    ah, 0c0h                ; r*n twice?
        jnz     getMemErr2

        test    ax, 20c0h               ; r2 or r1*n
        jnz     short mkaddr3

        ; single register addressing [Exx]/[Exx+d8]/[Exx+d32]
        and     al, 7
        or      [ebx], al
        cmp     al, 4                   ; 4=sib present (=ESP)
        je      short mkaddr3
mkaddr0:cmp     al, 5                   ; 5=dircet (=EBP)
        je      short mkaddr2
mkaddr1:jecxz   short off_d0
mkaddr2:movsx   eax, cl
        cmp     eax, ecx
        jne     short off_d32
off_d8: or      byte ptr [ebx], 40h     ; +d8
        stosb
        ret

off_d32:xchg    eax, ecx
        or      byte ptr [ebx], 80h     ; +d32
        stosd
        ret

mkaddr3:; [esp+x] is used, or:  [r1+]r2*n is used
        or      byte ptr [ebx], 04h     ; sib present
        test    al, 0c0h
        jnz     short @f
        shl     al, 3
@@:     test    ah, ah                  ; any base?
        jnz     short mkaddr4

        test    al, 0c0h                ; scale?
        jnz     short mkaddr5

        shr     al, 3                   ; use it as the base
        or      al, 4*8                 ; 00100bbb = [base+x], no index
        stosb
        cmp     al, 4*8+5               ; [xxx+EBP]?
        jne     short mkaddr1
        jmp     short mkaddr2           ; [d32+1*EBP]

mkaddr4:and     ah, 7
        test    al, 0c0h
        jnz     short @f
        cmp     ah, 5                   ; [ebp+..]?
        jne     short @f
        xchg    al, ah                  ; use other reg as base
        shl     al, 3
        shr     ah, 3
@@:     or      al, ah
        stosb
        xchg    al, ah
        jmp     short mkaddr0

mkaddr5:or      al, 5                   ; ssiii101 = [d32+s*i]
        stosb
        xchg    eax, ecx
        stosd
        ret

get_Reg32Address:
        push    esi
        call    Parse_Line
        PartCmd '2*'    GOTO_REL16 adr32Indx1 040h
        PartCmd '4*'    GOTO_REL16 adr32Indx1 080h
        PartCmd '8*'    GOTO_REL16 adr32Indx1 0c0h
        db 0
        call    get_RegDword
        jc      short getA32Err
        xchg    ecx, eax
        call    Parse_Line
        PartCmd '*2'    GOTO_REL16 adr32Indx2 040h
        PartCmd '*4'    GOTO_REL16 adr32Indx2 080h
        PartCmd '*8'    GOTO_REL16 adr32Indx2 0c0h
        db 0
        xchg    ecx, eax
        or      al, 20h                 ; make it non-zero
getA32Ret:
        pop     ebx                     ; saved ESI
        ret
getA32Err:
        pop     esi
        stc
        ret

adr32Indx1:
        xchg    ecx, eax
        call    get_RegDword
        jc      short getA32Err
        xchg    ecx, eax
adr32Indx2:
        cmp     cl, 4                   ; ESP cannot be used as index
        je      short getA32Err
        shl     cl, 3
        or      al, cl                  ; al=[ssrrr000]
        pop     ebx                     ; saved ESI
        ret

get_RegWordDword:
        call    get_RegDword
        jnc     short opr_Exx
get_RegWord:
        call    Parse_Line      ;see RM__xxxx
        FullCmd 'AX' GOTO_REL16 opr_Wx 00h
        FullCmd 'CX' GOTO_REL16 opr_Wx 01h
        FullCmd 'DX' GOTO_REL16 opr_Wx 02h
        FullCmd 'BX' GOTO_REL16 opr_Wx 03h
        FullCmd 'SP' GOTO_REL16 opr_Wx 04h
        FullCmd 'BP' GOTO_REL16 opr_Wx 05h
        FullCmd 'SI' GOTO_REL16 opr_Wx 06h
        FullCmd 'DI' GOTO_REL16 opr_Wx 07h
        db 0
        ret

opr_Exx:or      dh, PRE_OPR32
        or      dl, RM__DWRD + RM__DATA
        ret
opr_Wx: or      dl, RM__WORD + RM__DATA
        ret

get_Register0:
        mov     asmRmPtr, edi
get_Register:
        call    get_RegWordDword
        jnc     short regByteRet
get_RegByte:
        call    Parse_Line
        FullCmd 'AL'   GOTO_REL16, opr_Bx, 0
        FullCmd 'CL'   GOTO_REL16, opr_Bx, 1
        FullCmd 'DL'   GOTO_REL16, opr_Bx, 2
        FullCmd 'BL'   GOTO_REL16, opr_Bx, 3
        FullCmd 'AH'   GOTO_REL16, opr_Bx, 4
        FullCmd 'CH'   GOTO_REL16, opr_Bx, 5
        FullCmd 'DH'   GOTO_REL16, opr_Bx, 6
        FullCmd 'BH'   GOTO_REL16, opr_Bx, 7
        db 0
regByteRet:
        ret

opr_Accu:
        call    Parse_Line
        FullCmd 'AL'   GOTO_REL16, opr_Bx, 0
        FullCmd 'AX'   GOTO_REL16, opr_Wx, 1
        FullCmd 'EAX'  GOTO_REL16, opr_Exx, 1
        db 0
        ret
opr_Bx: mov     ebx, asmRmPtr
        and     byte ptr [ebx-1], not 1 ; w-bit
        or      dl, RM__BYTE
        ret

get_segRegister1:
        call    Parse_Line
        FullCmd 'ES' GOTO_REL16 segreg_ret 0*8
        FullCmd 'CS' GOTO_REL16 segreg_ret 1*8
        FullCmd 'SS' GOTO_REL16 segreg_ret 2*8
        FullCmd 'DS' GOTO_REL16 segreg_ret 3*8
        db 0
segreg_ret:
        ret

get_RegDword:
        call    Parse_Line      ;see RM__xxxx
        FullCmd 'EAX' GOTO_REL16, regwrd_ret 00h
        FullCmd 'ECX' GOTO_REL16, regwrd_ret 01h
        FullCmd 'EDX' GOTO_REL16, regwrd_ret 02h
        FullCmd 'EBX' GOTO_REL16, regwrd_ret 03h
        FullCmd 'ESP' GOTO_REL16, regwrd_ret 04h
        FullCmd 'EBP' GOTO_REL16, regwrd_ret 05h
        FullCmd 'ESI' GOTO_REL16, regwrd_ret 06h
        FullCmd 'EDI' GOTO_REL16, regwrd_ret 07h
        db 0
regwrd_ret:
        ret

get_segRegisters:
        call    get_segRegister1
        jnc     short get_segRet
get_segRegister2:
        call    Parse_Line
        FullCmd 'FS'    GOTO_REL16, get_segRet, 4*8
        FullCmd 'GS'    GOTO_REL16, get_segRet, 5*8
        db 0
get_segRet:
        ret

getSegOvr:
        call    Parse_Line
        PartCmd 'CS:'   GOTO_REL16, getSeg1, PRE_CS
        PartCmd 'DS:'   GOTO_REL16, getSeg1, PRE_DS
        PartCmd 'ES:'   GOTO_REL16, getSeg1, PRE_ES
        PartCmd 'SS:'   GOTO_REL16, getSeg1, PRE_SS
        PartCmd 'FS:'   GOTO_REL16, getSeg1, PRE_FS
        PartCmd 'GS:'   GOTO_REL16, getSeg1, PRE_GS
        db 0
        ret

Opcodes_Start label byte
Opcode_Movzx equ ($-Opcodes_Start)
        db 00fh, 0b6h   ; _r16_rm8
        db 00fh, 0b7h   ; _r32_rm16
        db 0f1h
Opcode_Movsx equ ($-Opcodes_Start)
        db 00fh, 0beh   ; _r16_rm8
        db 00fh, 0bfh   ; _r32_rm16
        db 0f1h
Opcode_Mov equ ($-Opcodes_Start)
        db 0a1h         ; _acc_addr (b/w)
        db 0a3h         ; _addr_acc (b/w)
        db 08bh         ; _reg_rm   (b/w)
        db 08eh         ; _seg_rm
        db 0b0h         ; _reg_imm  (b/w)
        db 0c7h, 000h   ; _rm_imm   (b/w)
        db 089h         ; _rm_reg   (b/w)
        db 08ch         ; _rm_seg
        db 00fh, 020h   ; _0f_2x    (CRn/DRn/TRn)
        db 0f1h
Opcode_Push equ ($-Opcodes_Start)
        db 050h         ; _r16
        db 006h         ; _seg
        db 00fh, 0a0h   ; _fs_gs
        db 06ah         ; _sx8
        db 068h         ; _nnnnw
        db 0ffh, 30h    ; _rmw
        db 0f1h
Opcode_Pop equ ($-Opcodes_Start)
        db 058h         ; _r16
        db 007h         ; _seg
        db 00fh, 0a1h   ; _fs_gs
        db 08fh, 00h    ; _rmw
        db 0f1h
Opcode_Inc equ ($-Opcodes_Start)
        db 040h         ; _r16
        db 0ffh, 000h   ; _rm
        db 0f1h
Opcode_Dec equ ($-Opcodes_Start)
        db 048h         ; _r16
        db 0ffh, 008h   ; _rm
        db 0f1h
Opcode_Xchg equ ($-Opcodes_Start)
        db 091h         ; _ax_r16
        db 087h         ; _rm_reg
        db 0f1h
Opcode_Add equ ($-Opcodes_Start)
        db 003h         ; _reg_rm
        db 001h         ; _rm_reg
        db 083h, 000h   ; _rm_sx8
        db 005h         ; _acc_imm
        db 081h, 000h   ; _rm_imm
        db 0f1h
Opcode_Or  equ ($-Opcodes_Start)
        db 00bh         ; _reg_rm
        db 009h         ; _rm_reg
        db 083h, 008h   ; _rm_sx8
        db 00dh         ; _acc_imm
        db 081h, 008h   ; _rm_imm
        db 0f1h
Opcode_Adc equ ($-Opcodes_Start)
        db 013h         ; _reg_rm
        db 011h         ; _rm_reg
        db 083h, 010h   ; _rm_sx8
        db 015h         ; _acc_imm
        db 081h, 010h   ; _rm_imm
        db 0f1h
Opcode_Sbb equ ($-Opcodes_Start)
        db 01bh         ; _reg_rm
        db 019h         ; _rm_reg
        db 083h, 018h   ; _rm_sx8
        db 01dh         ; _acc_imm
        db 081h, 018h   ; _rm_imm
        db 0f1h
Opcode_And equ ($-Opcodes_Start)
        db 023h         ; _reg_rm
        db 021h         ; _rm_reg
        db 083h, 020h   ; _rm_sx8
        db 025h         ; _acc_imm
        db 081h, 020h   ; _rm_imm
        db 0f1h
Opcode_Sub equ ($-Opcodes_Start)
        db 02bh         ; _reg_rm
        db 029h         ; _rm_reg
        db 083h, 028h   ; _rm_sx8
        db 02dh         ; _acc_imm
        db 081h, 028h   ; _rm_imm
        db 0f1h
Opcode_Xor equ ($-Opcodes_Start)
        db 033h         ; _reg_rm
        db 031h         ; _rm_reg
        db 083h, 030h   ; _rm_sx8
        db 035h         ; _acc_imm
        db 081h, 030h   ; _rm_imm
        db 0f1h
Opcode_Cmp equ ($-Opcodes_Start)
        db 03bh         ; _reg_rm
        db 039h         ; _rm_reg
        db 083h, 038h   ; _rm_sx8
        db 03dh         ; _acc_imm
        db 081h, 038h   ; _rm_imm
        db 0f1h
Opcode_Test equ ($-Opcodes_Start)
        db 085h         ; _rm_reg
        db 0a9h         ; _acc_imm
        db 0f7h, 000h   ; _rm_imm
        db 0f1h
Opcode_Jmp equ ($-Opcodes_Start)
        db 0ffh, 020h   ; _rmw
        db 0ffh, 028h   ; _dword
        db 0eah         ; _seg_off
        db 0ebh         ; _rel8
        db 0e9h         ; _relwrd
        db 0f1h
Opcode_Call equ ($-Opcodes_Start)
        db 0ffh, 010h   ; _rmw
        db 0ffh, 018h   ; _dword
        db 09ah         ; _seg_off
        db 0e8h         ; _relwrd
        db 0f1h
Opcode_Imul equ ($-Opcodes_Start)
        db 0f7h, 028h   ; _rm
        db 06bh         ; _reg_rm_sx8
        db 069h         ; _reg_rm_nnnn
        db 00fh, 0afh   ; _reg_rm
        db 0f1h
Opcode_Mul equ ($-Opcodes_Start)
        db 0f7h, 020h   ; _rm
        db 0f1h
Opcode_Idiv equ ($-Opcodes_Start)
        db 0f7h, 038h   ; _rm
        db 0f1h
Opcode_Div equ ($-Opcodes_Start)
        db 0f7h, 030h   ; _rm
        db 0f1h
Opcode_In  equ ($-Opcodes_Start)
        db 0edh             ; _out_dx
        db 0e5h             ; _out_nn
        db 0f1h
Opcode_Out equ ($-Opcodes_Start)
        db 0efh             ; _out_dx
        db 0e7h             ; _out_nn
        db 0f1h
Opcode_Bts equ ($-Opcodes_Start)
        db 00fh, 0abh       ; _rm_r16
        db 00fh, 0bah, 028h ; _rmw_nn
        db 0f1h
Opcode_Btr equ ($-Opcodes_Start)
        db 00fh, 0b3h       ; _rm_r16
        db 00fh, 0bah, 030h ; _rmw_nn
        db 0f1h
Opcode_Btc equ ($-Opcodes_Start)
        db 00fh, 0bbh       ; _rm_r16
        db 00fh, 0bah, 038h ; _rmw_nn
        db 0f1h
Opcode_Bt  equ ($-Opcodes_Start)
        db 00fh, 0a3h       ; _rm_r16
        db 00fh, 0bah, 020h ; _rmw_nn
        db 0f1h
Opcode_Cmpxchg   equ ($-Opcodes_Start)
        db 00fh, 0b0h       ; _rm_reg
        db 00fh, 0b1h       ; _rm_reg
        db 00fh, 0c7h       ; _rm_reg
        db 0f1h
Opcode_Xadd      equ ($-Opcodes_Start)
        db 00fh, 0c0h       ; _rm_reg
        db 00fh, 0c1h       ; _rm_reg
        db 0f1h
Opcode_Bswap     equ ($-Opcodes_Start)
        db 00fh, 0c8h       ; _r32
        db 0f1h
Opcode_Movd      equ ($-Opcodes_Start)
        db 00fh, 06eh       ; _mmx_rm32
        db 00fh, 07eh       ; _rm32_mmx
        db 0f1h
Opcode_Movq      equ ($-Opcodes_Start)
        db 00fh, 06fh       ; _mmx_rm64
        db 00fh, 07fh       ; _rm64_mmx
        db 0f1h
Opcode_Psllw     equ ($-Opcodes_Start)
        db 00fh, 071h, 030h ; _mmx_imm8
        db 00fh, 0f1h       ; _mmx_rm64
        db 0f1h
Opcode_Pslld     equ ($-Opcodes_Start)
        db 00fh, 072h, 030h ; _mmx_imm8
        db 00fh, 0f2h       ; _mmx_rm64
        db 0f1h
Opcode_Psllq     equ ($-Opcodes_Start)
        db 00fh, 073h, 030h ; _mmx_imm8
        db 00fh, 0f3h       ; _mmx_rm64
        db 0f1h
Opcode_Psrlw     equ ($-Opcodes_Start)
        db 00fh, 071h, 010h ; _mmx_imm8
        db 00fh, 0d1h       ; _mmx_rm64
        db 0f1h
Opcode_Psrld     equ ($-Opcodes_Start)
        db 00fh, 072h, 010h ; _mmx_imm8
        db 00fh, 0d2h       ; _mmx_rm64
        db 0f1h
Opcode_Psrlq     equ ($-Opcodes_Start)
        db 00fh, 073h, 010h ; _mmx_imm8
        db 00fh, 0d3h       ; _mmx_rm64
        db 0f1h
Opcode_Psraw     equ ($-Opcodes_Start)
        db 00fh, 071h, 020h ; _mmx_imm8
        db 00fh, 0e1h       ; _mmx_rm64
        db 0f1h
Opcode_Psrad     equ ($-Opcodes_Start)
        db 00fh, 072h, 020h ; _mmx_imm8
        db 00fh, 0e2h       ; _mmx_rm64
        db 0f1h

PUBPROC Assemble
        ;In:    ESI=ptr instruction
        ;       EBP=IP for first byte of instruction
        ;       def_segsize bit0=32 bit operand size
        ;                   bit1=32 bit address size
        ;                   bit7=V86 address type
        ;Out:   CF=0: ESI=opcodes
        ;             EDI=ptr end of asmBuffer
        ;       CF=1: error
        DBGBRK  3
        mov     actual_IP, ebp
        mov     edi, OFFSET32 asmBuffer
        xor     edx, edx                ; reset flags
        call    get_Opcode
        jc      short asmbly1
        call    Skip_Blanks
        jnz     short asmbly1
        mov     esi, OFFSET32 asmBuffer
        mov     al, dl
        and     al, RM__BYTE + RM__WORD + RM__DWRD ; = 7
        cmp     al, 3                   ;0,1=RM__BYTE, 2=RM__WORD
        jb      short asmbly3
        cmp     al, 4                   ;4=RM__DWRD
        je      short asmbly3
        ; more than one type defined
asmbly1:stc
        ret
asmbly3:mov     ah, def_segsize         ;bit0=32 bit operand size
                                        ;bit1=32 bit address size
        shl     ah, 6                   ;ADR32,OPR32 => PRE_ADR32,PRE_OPR32
        xor     ah, dh
        and     ah, dl                  ;mask with RM__ADDR,RM__DATA
        mov     bl, dh
        and     ebx, PRE_SMASK
        mov     al, seg_Prefix[ebx-1]
        call    Insert_Prefix
        test    ah, PRE_ADR32
        mov     al, 67h                 ;PRE_ADR32
        call    Insert_Prefix
        mov     al, 66h                 ;PRE_OPR32
        test    ah, PRE_OPR32
Insert_Prefix:
        jz      short asmbly2
        dec     esi
        mov     [esi], al
asmbly2:ret

x87_Check4P:    ; x87 memory types
        mov     ah, not 20h
        and     ah, [esi]
        cmp     ah, 'P'
        jne     short x87_Mem1
        inc     esi
        ; it can only be fxxxp st(n)
        or      al, 6                   ; DE group
x87_ST_n:       ; x87 register
        mov     ah, al
        and     ax, 0f807h
        or      al, 0d8h
        stosw
get_x87Register:
        call    Parse_Line
        PartCmd 'ST'   GOTO_REL16, opr_STi, 0
        db 0
        ret
opr_STi:mov     al, [esi]
        sub     al, '0'
        cmp     al, 8
        jae     short @f
        inc     esi
        or      [edi-1], al
        ret
@@:     xor     al, al
x87_MemDone:
        ret

x87_Mem1:
        or      al, 4                   ; assume fxxx STi DC
        call    x87_ST_n
        jc      short x87_Mem2
        cmp     al, 0
        jne     short x87_MemDone
        call    Skip_Blanks
        xor     al, ','
        jnz     short x87_MemDone
        ; its ST,STi    D8 C0+
        and     byte ptr [edi-2], not 4
        inc     esi
        jmp     get_x87Register

x87_MemAddr:    ; x87 memory types
        call    x87_ST_n
        jnc     short x87_MemDone
        call    Parse_Line
_R80:   FullCmd 'R80'   GOTO_REL16, x87_Mem4, 2bh
_I64:   FullCmd 'I64'   GOTO_REL16, x87_Mem4, 2fh
_B80:   FullCmd 'B80'   GOTO_REL16, x87_Mem4, 27h
        db 0
x87_Mem2:
        call    Parse_Line
_F32:   FullCmd 'R32'   GOTO_REL16, x87_Mem3, 0d8h
_I32:   FullCmd 'DWORD' GOTO_REL16, x87_Mem3, 0dah
_F64:   FullCmd 'R64'   GOTO_REL16, x87_Mem3, 0dch
_I16:   FullCmd 'WORD'  GOTO_REL16, x87_Mem3, 0deh
        db 0
        mov     al, 0deh                ; WORD by default
x87_Mem3:
        and     word ptr [edi-2], 3801h
        xor     [edi-2], ax
        jmp     get_MemAddr

x87_Mem4:
        and     word ptr [edi-2], 1000h
        mov     ah, al
        and     ax, 3807h
        or      al, 0d8h
        jmp     x87_Mem3

_byte   db 'BYTE PTR '
_word   db 'WORD PTR '

        even
modtbl  dw adrmod0-X0, adrmod1-X0, adrmod2-X0, adrmod3-X0
        dw adrmod4-X0, adrmod5-X0, adrmod6-X0, adrmod7-X0

I_cnt   = 0

mkParam macro   p, n, q, m
        &p&n    equ <&q&m>
        endm

I_type  macro   t
        mkParam <Opr__>, %I_cnt, <Opr@>, &t
        mkParam <Adr__>, %I_cnt, <Adr@>, &t
        dd OFFSET32 Opc@&t
        t = I_cnt
        I_cnt = I_cnt + 1
        endm

InstTypeTable label dword
 I_type _dword       ;r/m (dword) (used in opcode2) (0=inst2)
 I_type _none        ;no operand inst's
 I_type _prefix      ;Prefix instructions
 I_type _segovr      ;seg: override
 I_type _r16         ;r16    .....rrr
 I_type _r32         ;r32    .....rrr
 I_type _seg         ;seg    ...ss...
 I_type _ax_r16      ;ax,r16 .....rrr
 I_type _reg_rm      ;reg,r/m (8/16)
 I_type _rm_reg      ;r/m,reg (8/16)
 I_type _seg_rm      ;seg,r/m
 I_type _rm_seg      ;r/m,seg
 I_type _acc_addr    ;acc,address
 I_type _addr_acc    ;address,acc
 I_type _acc_imm     ;acc,imm
 I_type _reg_imm     ;reg,imm  ....wrrr imm 
 I_type _r16_rm      ;reg,r/m (word)
 I_type _rm_r16      ;r/m,reg (16/32)
 I_type _int_nn      ;int nn
 I_type _nn          ;nn
 I_type _nnnn        ;nnnn (16)
 I_type _nnnnw       ;nnnn (16/32) (push)
 I_type _sx8         ;+nn/-nn
 I_type _nnnn_nn     ;nnnn,nn (enter)
 I_type _reg_rm_sx8  ;reg,r/m,+n/-n (imul)
 I_type _reg_rm_nnnn ;reg,r/m,nnnn  (imul)
 I_type _rm          ;r/m    .......w mm...r/m (byte/word)
 I_type _rmb         ;r/m    ........ mmxxxr/m (setcc byte)
 I_type _rmw         ;r/m (16/32)
 I_type _rmw_nn      ;bit operations r/m16/32,imm8
 I_type _rm_imm      ;r/m,imm  .......w r/m imm
 I_type _rm_sx8      ;r/m,+n/-n
 I_type _rm_sc       ;r/m,1/cl/nn
 I_type _mem24       ;r/m (gdt/idt)
 I_type _r16_rm8     ;r16/32,r/m8 (movsx/movzx)
 I_type _r32_rm16    ;r32,r/m16 (movsx/movzx)
 I_type _rm_r16_sc   ;r/m,reg,cl/nn (shld/shrd)
 I_type _rel8        ;rel.8
 I_type _relwrd      ;rel.16
 I_type _seg_off     ;seg:off
 I_type _0fp         ;0F prefix
 I_type _32ovr       ;32 bit override (op32/ad32)
 I_type _float       ;ESC nn,r/m
 I_type _fs_gs       ;push/pop fs/gs
 I_type _0f_2x       ;mov CRn/DRn/TRn,r/m
 I_type _in_nn       ;in al/ax/eax,nn
 I_type _in_dx       ;in al/ax/eax,dx
 I_type _out_nn      ;out nn,al/ax/eax
 I_type _out_dx      ;out dx,al/ax/eax
 I_type _sb_or_sw    ;sw/sd in ins lods/scas/movs/cmps/stos
 I_type _d_for_32    ;push/pop/pushf/popf/iret (+d when 32)
 I_type _16_or_32    ;cbw(cwde)/cwd(cdq)
 I_type _mmx_rm32    ;mmx,r32/mem
 I_type _rm32_mmx    ;r32/mem,mmx
 I_type _mmx_rm64    ;mmx,rm/mmx
 I_type _rm64_mmx    ;rm,mmx
 I_type _mmx_imm8    ;mmx,imm8

mkJump  macro p, n
        dd OFFSET32 &p&n
        endm

mkJumpTable macro name, p, cnt
&name   label dword
        J_cnt = 0
        REPT    cnt
        mkJump  &p, %J_cnt
        J_cnt = J_cnt+1
        ENDM
        endm

mkJumpTable effAdrTypeTable, <Adr__>, I_cnt
mkJumpTable OprndTypeTable,  <Opr__>, I_cnt

K_cnt   = 0

K_type  macro   t
        @&t   = K_cnt
        K_cnt = K_cnt + 1
        dd OFFSET32 _k@&t
        dd OFFSET32 _tr@&t
        endm

StepType label dword
 K_type inst_2
 K_type prefix
 K_type adr32
 K_type opr32
 K_type 0f
 K_type trace
 K_type step3a          ;label 16/32
 K_type stepm1          ;r/m next byte
 K_type stepm2          ;r/m
 K_type stepf           ;ssss:oooo
 K_type step1
 K_type step2
 K_type stepx           ;step6 if int 20 (vxdcall)

inst1   macro   a,t,x
        dw      a - X0
        db      t
        ifb     <x>
        db      @trace
        else
        db      @&x
        endif
        endm

inst2   macro   a
        dw      a - opcode2
        dw      0
        endm

opcode2 equ this word
_grp80  equ this word
_grp81  equ this word
_grp82  equ this word
 inst1 _add   _rm_imm           ;add r/m,nn
 inst1 _or    _rm_imm           ;or  r/m,nn
 inst1 _adc   _rm_imm           ;adc r/m,nn
 inst1 _sbb   _rm_imm           ;sbb r/m,nn
 inst1 _and   _rm_imm           ;and r/m,nn
 inst1 _sub   _rm_imm           ;sub r/m,nn
 inst1 _xor   _rm_imm           ;xor r/m,nn
 inst1 _cmp   _rm_imm           ;cmp r/m,nn
_grp83  equ this word
 inst1 _add   _rm_sx8           ;add r/m,+nn/-nn
 inst1 _or    _rm_sx8           ;or  r/m,+nn/-nn
 inst1 _adc   _rm_sx8           ;adc r/m,+nn/-nn
 inst1 _sbb   _rm_sx8           ;sbb r/m,+nn/-nn
 inst1 _and   _rm_sx8           ;and r/m,+nn/-nn
 inst1 _sub   _rm_sx8           ;sub r/m,+nn/-nn
 inst1 _xor   _rm_sx8           ;xor r/m,+nn/-nn
 inst1 _cmp   _rm_sx8           ;cmp r/m,+nn/-nn
_grp8f  equ this word
 inst1 _pop   _rmw              ;pop r/m
 inst1 _pop   _rmw              ;pop r/m
 inst1 _pop   _rmw              ;pop r/m
 inst1 _pop   _rmw              ;pop r/m
 inst1 _pop   _rmw              ;pop r/m
 inst1 _pop   _rmw              ;pop r/m
 inst1 _pop   _rmw              ;pop r/m
 inst1 _pop   _rmw              ;pop r/m
_grpc0  equ this word
_grpc1  equ this word
_grpd0  equ this word
_grpd1  equ this word
_grpd2  equ this word
_grpd3  equ this word
 inst1 _rol   _rm_sc            ;rol r/m,1/cl/nn
 inst1 _ror   _rm_sc            ;ror r/m,1/cl/nn
 inst1 _rcl   _rm_sc            ;rcl r/m,1/cl/nn
 inst1 _rcr   _rm_sc            ;rcr r/m,1/cl/nn
 inst1 _shl   _rm_sc            ;shl r/m,1/cl/nn
 inst1 _shr   _rm_sc            ;shr r/m,1/cl/nn
 inst1 _shl   _rm_sc            ;sal r/m,1/cl/nn
 inst1 _sar   _rm_sc            ;sar r/m,1/cl/nn
_grpc6  equ this word
_grpc7  equ this word
 inst1 _mov   _rm_imm           ;mov r/m,nn/nnnn
 inst1 _mov   _rm_imm           ;mov r/m,nn/nnnn
 inst1 _mov   _rm_imm           ;mov r/m,nn/nnnn
 inst1 _mov   _rm_imm           ;mov r/m,nn/nnnn
 inst1 _mov   _rm_imm           ;mov r/m,nn/nnnn
 inst1 _mov   _rm_imm           ;mov r/m,nn/nnnn
 inst1 _mov   _rm_imm           ;mov r/m,nn/nnnn
 inst1 _mov   _rm_imm           ;mov r/m,nn/nnnn
_grpf6  equ this word
_grpf7  equ this word
 inst1 _test  _rm_imm           ;test r/m,nn
 inst1 _invl  _none             ;?
 inst1 _not   _rm               ;not r/m
 inst1 _neg   _rm               ;neg r/m
 inst1 _mul   _rm               ;mul r/m
 inst1 _imul  _rm               ;imul r/m
 inst1 _div   _rm               ;div r/m
 inst1 _idiv  _rm               ;idiv r/m
_grpfe  equ this word
 inst1 _inc   _rm               ;inc r/m
 inst1 _dec   _rm               ;dec r/m
 inst1 _invl  _none             ;?
 inst1 _invl  _none             ;?
_gr0fba equ this word
 inst1 _invl  _none             ;
 inst1 _invl  _none             ;
 inst1 _invl  _none             ;
 inst1 _invl  _none             ;
 inst1 _bt    _rmw_nn           ;
 inst1 _bts   _rmw_nn           ;
 inst1 _btr   _rmw_nn           ;
 inst1 _btc   _rmw_nn           ;
_grpff  equ this word
 inst1 _inc   _rm               ;inc r/m
 inst1 _dec   _rm               ;dec r/m
 inst1 _call  _rmw      stepm2  ;call r/m
 inst1 _call  _dword    stepm2  ;call dword ptr r/m
 inst1 _jmp   _rmw      trace   ;jmp  r/m
 inst1 _jmp   _dword    trace   ;jmp  dword ptr r/m
 inst1 _push  _rmw              ;push r/m
 inst1 _invl  _none             ;?
_gr0f00 equ this word
 inst1 _sldt  _rmw              ;sldt r/m
 inst1 _str   _rmw              ;str  r/m
 inst1 _lldt  _rmw      stepm2  ;lldt r/m
 inst1 _ltr   _rmw      stepm2  ;ltr  r/m
 inst1 _verr  _rmw              ;verr r/m
 inst1 _verw  _rmw              ;verw r/m
 inst1 _invl  _none             ;
 inst1 _invl  _none             ;
_gr0f01 equ this word
 inst1 _sgdt  _mem24            ;sgdt r/m
 inst1 _sidt  _mem24            ;sidt r/m
 inst1 _lgdt  _mem24    trace   ;lgdt r/m
 inst1 _lidt  _mem24    trace   ;lidt r/m
 inst1 _smsw  _rmw              ;smsw r/m
 inst1 _invl  _none             ;
 inst1 _lmsw  _rmw      stepm2  ;lmsw r/m
 inst1 _invlpg _rmw             ;

_gr0f71 equ this word
 inst1 _invl  _none                 ;0
 inst1 _invl  _none                 ;1
 inst1 _psrlw _mmx_imm8             ;2
 inst1 _invl  _none                 ;3
 inst1 _psraw _mmx_imm8             ;4
 inst1 _invl  _none                 ;5
 inst1 _psllw _mmx_imm8             ;6
;inst1 _invl  _none                 ;7
_gr0f72 equ this word
 inst1 _invl  _none                 ;0
 inst1 _invl  _none                 ;1
 inst1 _psrld _mmx_imm8             ;2
 inst1 _invl  _none                 ;3
 inst1 _psrad _mmx_imm8             ;4
 inst1 _invl  _none                 ;5
 inst1 _pslld _mmx_imm8             ;6
;inst1 _invl  _none                 ;7
_gr0f73 equ this word
 inst1 _invl  _none                 ;0
 inst1 _invl  _none                 ;1
 inst1 _psrlq _mmx_imm8             ;2
 inst1 _invl  _none                 ;3
 inst1 _invl  _none                 ;4
 inst1 _invl  _none                 ;5
 inst1 _psllq _mmx_imm8             ;6
 inst1 _invl  _none                 ;7

opcode1 equ this word
 inst1 _add   _rm_reg           ;00;add r/m,reg byte
 inst1 _add   _rm_reg              ;add r/m,reg word
 inst1 _add   _reg_rm              ;add reg,r/m byte
 inst1 _add   _reg_rm              ;add reg,r/m word
 inst1 _add   _acc_imm             ;add al,imm
 inst1 _add   _acc_imm             ;add ax,imm
 inst1 _push  _seg                 ;push es
 inst1 _pop   _seg                 ;pop es
 inst1 _or    _rm_reg           ;08;or  r/m,reg byte
 inst1 _or    _rm_reg              ;or  r/m,reg word
 inst1 _or    _reg_rm              ;or  reg,r/m byte
 inst1 _or    _reg_rm              ;or  reg,r/m word
 inst1 _or    _acc_imm             ;or  al,imm
 inst1 _or    _acc_imm             ;or  ax,imm
 inst1 _push  _seg                 ;push cs
 inst1 _invl  _0fp      0f         ;SYSTEM 286
 inst1 _adc   _rm_reg           ;10;adc r/m,reg byte
 inst1 _adc   _rm_reg              ;adc r/m,reg word
 inst1 _adc   _reg_rm              ;adc reg,r/m byte
 inst1 _adc   _reg_rm              ;adc reg,r/m word
 inst1 _adc   _acc_imm             ;adc al,imm
 inst1 _adc   _acc_imm             ;adc ax,imm
 inst1 _push  _seg                 ;push ss
 inst1 _pop   _seg                 ;pop ss
 inst1 _sbb   _rm_reg           ;18;sbb r/m,reg byte
 inst1 _sbb   _rm_reg              ;sbb r/m,reg word
 inst1 _sbb   _reg_rm              ;sbb reg,r/m byte
 inst1 _sbb   _reg_rm              ;sbb reg,r/m word
 inst1 _sbb   _acc_imm             ;sbb al,imm
 inst1 _sbb   _acc_imm             ;sbb ax,imm
 inst1 _push  _seg                 ;push ds
 inst1 _pop   _seg                 ;pop ds
 inst1 _and   _rm_reg           ;20;and r/m,reg byte
 inst1 _and   _rm_reg              ;and r/m,reg word
 inst1 _and   _reg_rm              ;and reg,r/m byte
 inst1 _and   _reg_rm              ;and reg,r/m word
 inst1 _and   _acc_imm             ;and al,imm
 inst1 _and   _acc_imm             ;and ax,imm
 inst1 _es    _segovr   prefix     ;es:
 inst1 _daa   _none                ;daa
 inst1 _sub   _rm_reg           ;28;sub r/m,reg byte
 inst1 _sub   _rm_reg              ;sub r/m,reg word
 inst1 _sub   _reg_rm              ;sub reg,r/m byte
 inst1 _sub   _reg_rm              ;sub reg,r/m word
 inst1 _sub   _acc_imm             ;sub al,imm
 inst1 _sub   _acc_imm             ;sub ax,imm
 inst1 _cs    _segovr   prefix     ;cs:
 inst1 _das   _none                ;das
 inst1 _xor   _rm_reg           ;30;xor r/m,reg byte
 inst1 _xor   _rm_reg              ;xor r/m,reg word
 inst1 _xor   _reg_rm              ;xor reg,r/m byte
 inst1 _xor   _reg_rm              ;xor reg,r/m word
 inst1 _xor   _acc_imm             ;xor al,imm
 inst1 _xor   _acc_imm             ;xor ax,imm
 inst1 _ss    _segovr   prefix     ;ss:
 inst1 _aaa   _none                ;aaa
 inst1 _cmp   _rm_reg           ;38;cmp r/m,reg byte
 inst1 _cmp   _rm_reg              ;cmp r/m,reg word
 inst1 _cmp   _reg_rm              ;cmp reg,r/m byte
 inst1 _cmp   _reg_rm              ;cmp reg,r/m word
 inst1 _cmp   _acc_imm             ;cmp al,imm
 inst1 _cmp   _acc_imm             ;cmp ax,imm
 inst1 _ds    _segovr   prefix     ;ds:
 inst1 _aas   _none                ;aas
 inst1 _inc   _r16              ;40;inc ax
 inst1 _inc   _r16                 ;inc cx
 inst1 _inc   _r16                 ;inc dx
 inst1 _inc   _r16                 ;inc bx
 inst1 _inc   _r16                 ;inc sp
 inst1 _inc   _r16                 ;inc bp
 inst1 _inc   _r16                 ;inc si
 inst1 _inc   _r16                 ;inc di
 inst1 _dec   _r16              ;48;dec ax
 inst1 _dec   _r16                 ;dec cx
 inst1 _dec   _r16                 ;dec dx
 inst1 _dec   _r16                 ;dec bx
 inst1 _dec   _r16                 ;dec sp
 inst1 _dec   _r16                 ;dec bp
 inst1 _dec   _r16                 ;dec si
 inst1 _dec   _r16                 ;dec di
 inst1 _push  _r16              ;50;push ax
 inst1 _push  _r16                 ;push cx
 inst1 _push  _r16                 ;push dx
 inst1 _push  _r16                 ;push bx
 inst1 _push  _r16                 ;push sp
 inst1 _push  _r16                 ;push bp
 inst1 _push  _r16                 ;push si
 inst1 _push  _r16                 ;push di
 inst1 _pop   _r16              ;58;pop ax
 inst1 _pop   _r16                 ;pop cx
 inst1 _pop   _r16                 ;pop dx
 inst1 _pop   _r16                 ;pop bx
 inst1 _pop   _r16                 ;pop sp
 inst1 _pop   _r16                 ;pop bp
 inst1 _pop   _r16                 ;pop si
 inst1 _pop   _r16                 ;pop di
 inst1 _pusha _d_for_32         ;60;pusha
 inst1 _popa  _d_for_32            ;popa
 inst1 _bound _r16_rm              ;bound
 inst1 _arpl  _rm_r16   stepm1     ;arpl
 inst1 _fs    _segovr   prefix     ;fs:
 inst1 _gs    _segovr   prefix     ;gs:
 inst1 _invl  _32ovr    opr32      ;operand size
 inst1 _invl  _32ovr    adr32      ;address size
 inst1 _push  _nnnnw            ;68;push nnnn (16/32)
 inst1 _imul  _reg_rm_nnnn         ;imul reg,r/m,nnnn
 inst1 _push  _sx8                 ;push +n/-n
 inst1 _imul  _reg_rm_sx8          ;imul reg,r/m,+n/-n
 inst1 _ins   _sb_or_sw step1      ;insb
 inst1 _ins   _sb_or_sw step1      ;insw/d
 inst1 _outs  _sb_or_sw step1      ;outsb
 inst1 _outs  _sb_or_sw step1      ;outsw/d
 inst1 _jo    _rel8     trace   ;70;jo  label
 inst1 _jno   _rel8     trace      ;jno label
 inst1 _jc    _rel8     trace      ;jc  label
 inst1 _jnc   _rel8     trace      ;jnc label
 inst1 _je    _rel8     trace      ;je  label
 inst1 _jne   _rel8     trace      ;jne label
 inst1 _jbe   _rel8     trace      ;jbe label
 inst1 _ja    _rel8     trace      ;ja  label
 inst1 _js    _rel8     trace   ;78;jo  label
 inst1 _jns   _rel8     trace      ;jno label
 inst1 _jp    _rel8     trace      ;jc  label
 inst1 _jnp   _rel8     trace      ;jnc label
 inst1 _jl    _rel8     trace      ;je  label
 inst1 _jge   _rel8     trace      ;jne label
 inst1 _jle   _rel8     trace      ;jbe label
 inst1 _jg    _rel8     trace      ;ja  label
 inst2 _grp80                   ;80;
 inst2 _grp81
 inst2 _grp82
 inst2 _grp83
 inst1 _test  _rm_reg              ;test r/m,reg byte
 inst1 _test  _rm_reg              ;test r/m,reg word
 inst1 _xchg  _rm_reg              ;xchg r/m,reg byte
 inst1 _xchg  _rm_reg              ;xchg r/m,reg word
 inst1 _mov   _rm_reg           ;88;mov  r/m,reg byte
 inst1 _mov   _rm_reg              ;mov  r/m,reg word
 inst1 _mov   _reg_rm              ;mov  reg,r/m byte
 inst1 _mov   _reg_rm              ;mov  reg,r/m word
 inst1 _mov   _rm_seg              ;mov  r/m,seg
 inst1 _lea   _r16_rm              ;lea  reg,r/m
 inst1 _mov   _seg_rm              ;mov  seg,r/m
 inst2 _grp8f
 inst1 _nop   _none             ;90;nop
 inst1 _xchg  _ax_r16              ;xchg cx,ax
 inst1 _xchg  _ax_r16              ;xchg dx,ax
 inst1 _xchg  _ax_r16              ;xchg bx,ax
 inst1 _xchg  _ax_r16              ;xchg sp,ax
 inst1 _xchg  _ax_r16              ;xchg bp,ax
 inst1 _xchg  _ax_r16              ;xchg si,ax
 inst1 _xchg  _ax_r16              ;xchg di,ax
 inst1 _cbw   _16_or_32         ;98;cbw
 inst1 _cwd   _16_or_32            ;cwd
 inst1 _call  _seg_off  stepf      ;call seg:off
 inst1 _wait  _none                ;wait
 inst1 _pushf _d_for_32 step1      ;pushf
 inst1 _popf  _d_for_32 step1      ;popf
 inst1 _sahf  _none                ;sahf
 inst1 _lahf  _none                ;lahf
 inst1 _mov   _acc_addr         ;a0;mov al,address
 inst1 _mov   _acc_addr            ;mov ax,address
 inst1 _mov   _addr_acc            ;mov address,al
 inst1 _mov   _addr_acc            ;mov address,ax
 inst1 _movs  _sb_or_sw step1      ;movsb
 inst1 _movs  _sb_or_sw step1      ;movsw
 inst1 _cmps  _sb_or_sw step1      ;cmpsb
 inst1 _cmps  _sb_or_sw step1      ;cmpsw
 inst1 _test  _acc_imm          ;a8;test al,nn
 inst1 _test  _acc_imm             ;test ax,nnnn
 inst1 _stos  _sb_or_sw step1      ;stosb
 inst1 _stos  _sb_or_sw step1      ;stosw
 inst1 _lods  _sb_or_sw step1      ;lodsb
 inst1 _lods  _sb_or_sw step1      ;lodsw
 inst1 _scas  _sb_or_sw step1      ;scasb
 inst1 _scas  _sb_or_sw step1      ;scasw
 inst1 _mov   _reg_imm          ;b0;mov al,nn
 inst1 _mov   _reg_imm             ;mov cl,nn
 inst1 _mov   _reg_imm             ;mov dl,nn
 inst1 _mov   _reg_imm             ;mov bl,nn
 inst1 _mov   _reg_imm             ;mov ah,nn
 inst1 _mov   _reg_imm             ;mov ch,nn
 inst1 _mov   _reg_imm             ;mov dh,nn
 inst1 _mov   _reg_imm             ;mov bh,nn
 inst1 _mov   _reg_imm          ;b8;mov ax,nnnn
 inst1 _mov   _reg_imm             ;mov cx,nnnn
 inst1 _mov   _reg_imm             ;mov dx,nnnn
 inst1 _mov   _reg_imm             ;mov bx,nnnn
 inst1 _mov   _reg_imm             ;mov sp,nnnn
 inst1 _mov   _reg_imm             ;mov bp,nnnn
 inst1 _mov   _reg_imm             ;mov si,nnnn
 inst1 _mov   _reg_imm             ;mov di,nnnn
 inst2 _grpc0                   ;c0;
 inst2 _grpc1
 inst1 _ret   _nnnn     trace      ;ret nnnn (16)
 inst1 _ret   _none     trace      ;ret
 inst1 _les   _r16_rm              ;les reg,r/m
 inst1 _lds   _r16_rm              ;lds reg,r/m
 inst2 _grpc6
 inst2 _grpc7
 inst1 _enter _nnnn_nn          ;c8;enter nnnn,nn
 inst1 _leave _none                ;leave
 inst1 _retf  _nnnn     trace      ;retf nnnn (16)
 inst1 _retf  _none     trace      ;retf
 inst1 _int3  _none     step1      ;int 3
 inst1 _int   _int_nn   stepx      ;int nn
 inst1 _into  _none     step1      ;into
 inst1 _iret  _d_for_32 trace      ;iret
 inst2 _grpd0                   ;d0;
 inst2 _grpd1
 inst2 _grpd2
 inst2 _grpd3
 inst1 _aam   _nn                  ;aam
 inst1 _aad   _nn                  ;aad
 inst1 _salc  _none                ;salc (undoc: Set AL on Carry ff/00)
 inst1 _xlat  _none                ;xlat
 inst1 _esc   _float            ;d8;ESC
 inst1 _esc   _float
 inst1 _esc   _float
 inst1 _esc   _float
 inst1 _esc   _float
 inst1 _esc   _float
 inst1 _esc   _float
 inst1 _esc   _float
 inst1 _loopn _rel8     step2   ;e0;loopne label
 inst1 _loope _rel8     step2      ;loope  label
 inst1 _loop  _rel8     step2      ;loop   label
 inst1 _jcxz  _rel8     trace      ;jcxz   label
 inst1 _in    _in_nn    step2      ;inb port
 inst1 _in    _in_nn    step2      ;inw port
 inst1 _out   _out_nn   step2      ;outb port
 inst1 _out   _out_nn   step2      ;outw port
 inst1 _call  _relwrd   step3a  ;e8;call label
 inst1 _jmp   _relwrd   trace      ;jmp  rel.16
 inst1 _jmp   _seg_off  trace      ;jmp  seg:off
 inst1 _jmp   _rel8     trace      ;jmp  rel.8
 inst1 _in    _in_dx    step1      ;inb dx
 inst1 _in    _in_dx    step1      ;inw dx
 inst1 _out   _out_dx   step1      ;outb dx
 inst1 _out   _out_dx   step1      ;outw dx
 inst1 _lock  _prefix   prefix  ;f0;lock
 inst1 _invl  _none                ;?
 inst1 _repne _prefix   prefix     ;repne
 inst1 _repe  _prefix   prefix     ;repe
 inst1 _hlt   _none     step1      ;hlt
 inst1 _cmc   _none                ;cmc
 inst2 _grpf6
 inst2 _grpf7
 inst1 _clc   _none             ;f8;clc
 inst1 _stc   _none                ;stc
 inst1 _cli   _none     step1      ;cli
 inst1 _sti   _none     step1      ;sti
 inst1 _cld   _none                ;cld
 inst1 _std   _none                ;std
 inst2 _grpfe
 inst2 _grpff

opcode_0f equ this word
op_0f00 equ ($-opcode_0f)/4
 inst2 _gr0f00                 ;0f00;
 inst2 _gr0f01
 inst1 _lar   _r16_rm   stepm1      ;lar reg,r/m
 inst1 _lsl   _r16_rm   stepm1      ;lsl reg,r/m
 inst1 _invl  _none                 ;
 inst1 _ldall _none                 ;loadall (undocumented, loads from abs 800h)
 inst1 _clts  _none     step1       ;clts
 inst1 _ldall _none                 ;loadalld
op_0f20 equ ($-opcode_0f)/4
 inst1 _mov   _0f_2x           ;0f20;mov r/m,CRn
 inst1 _mov   _0f_2x                ;mov r/m,DRn
 inst1 _mov   _0f_2x    trace       ;mov CRn,r/m
 inst1 _mov   _0f_2x                ;mov DRn,r/m
 inst1 _mov   _0f_2x                ;mov r/m,TRn
 inst1 _invl  _none                 ;
 inst1 _mov   _0f_2x                ;mov TRn,r/m
;inst1 _invl  _none                 ;
op_0f08 equ ($-opcode_0f)/4
 inst1 _invd  _none                 ;
 inst1 _wbinvd _none                ;
 inst1 _invl  _none                 ;
 inst1 _ud2   _none                 ;UD2
;inst1 _invl  _none                 ;
;inst1 _invl  _none                 ;
;inst1 _invl  _none                 ;
;inst1 _invl  _none                 ;
op_0f78 equ ($-opcode_0f)/4
 inst1 _invl  _none                 ;(Cyrix: SVDC  mem80,sreg3)
 inst1 _invl  _none                 ;(Cyrix: RDSC  sreg3,mem80)
 inst1 _invl  _none                 ;(Cyrix: SVLDT mem80      )
 inst1 _invl  _none                 ;(Cyrix: RVLDT mem80      )
 inst1 _invl  _none                 ;(Cyrix: SVTS  mem80      )
 inst1 _invl  _none                 ;(Cyrix: RSTS  mem80      )
 inst1 _movd      _rm32_mmx         ;(Cyrix: SMINT            )
 inst1 _movq      _rm64_mmx         ;
op_0f30 equ ($-opcode_0f)/4
 inst1 _wrmsr _none            ;0f30;Write to a model specific register
 inst1 _rdtsc _none                 ;Read time stamp counter
 inst1 _rdmsr _none                 ;Read a model specific register value
 inst1 _rdpmc _none                 ;Read Performance Monitor Counter (P6)
 inst1 _invl  _none                 ;
 inst1 _invl  _none                 ;
 inst1 _invl  _none                 ;
;inst1 _invl  _none                 ;
op_0f70 equ ($-opcode_0f)/4
 inst1 _invl  _none                 ;
 inst2 _gr0f71                      ;
 inst2 _gr0f72                      ;
 inst2 _gr0f73                      ;
 inst1 _pcmpeqb   _mmx_rm64         ;
 inst1 _pcmpeqw   _mmx_rm64         ;
 inst1 _pcmpeqd   _mmx_rm64         ;
 inst1 _emms  _none                 ;
op_0f60 equ ($-opcode_0f)/4
 inst1 _punpcklbw _mmx_rm64         ;
 inst1 _punpcklwd _mmx_rm64         ;
 inst1 _punpckldq _mmx_rm64         ;
 inst1 _packsswb  _mmx_rm64         ;
 inst1 _pcmpgtb   _mmx_rm64         ;
 inst1 _pcmpgtw   _mmx_rm64         ;
 inst1 _pcmpgtd   _mmx_rm64         ;
 inst1 _packuswb  _mmx_rm64         ;
op_0f68 equ ($-opcode_0f)/4
 inst1 _punpckhbw _mmx_rm64         ;
 inst1 _punpckhwd _mmx_rm64         ;
 inst1 _punpckhdq _mmx_rm64         ;
 inst1 _packssdw  _mmx_rm64         ;
 inst1 _invl  _none                 ;
 inst1 _invl  _none                 ;
 inst1 _movd      _mmx_rm32         ;
 inst1 _movq      _mmx_rm64         ;
op_0f40 equ ($-opcode_0f)/4
 inst1 _cmovo  _r16_rm   trace ;0f40;cmovo
 inst1 _cmovno _r16_rm   trace      ;cmovno
 inst1 _cmovc  _r16_rm   trace      ;cmovc
 inst1 _cmovnc _r16_rm   trace      ;cmovnc
 inst1 _cmove  _r16_rm   trace      ;cmove
 inst1 _cmovne _r16_rm   trace      ;cmovne
 inst1 _cmovbe _r16_rm   trace      ;cmovbe
 inst1 _cmova  _r16_rm   trace      ;cmova
op_0f48 equ ($-opcode_0f)/4
 inst1 _cmovs  _r16_rm   trace ;0f48;cmovs
 inst1 _cmovns _r16_rm   trace      ;cmovns
 inst1 _cmovp  _r16_rm   trace      ;cmovp
 inst1 _cmovnp _r16_rm   trace      ;cmovnp
 inst1 _cmovl  _r16_rm   trace      ;cmovl
 inst1 _cmovge _r16_rm   trace      ;cmovge
 inst1 _cmovle _r16_rm   trace      ;cmovle
 inst1 _cmovg  _r16_rm   trace      ;cmovg
op_0f80 equ ($-opcode_0f)/4
 inst1 _jo    _relwrd   trace  ;0f80;jo  label
 inst1 _jno   _relwrd   trace       ;jno label
 inst1 _jc    _relwrd   trace       ;jc  label
 inst1 _jnc   _relwrd   trace       ;jnc label
 inst1 _je    _relwrd   trace       ;je  label
 inst1 _jne   _relwrd   trace       ;jne label
 inst1 _jbe   _relwrd   trace       ;jbe label
 inst1 _ja    _relwrd   trace       ;ja  label
op_0f88 equ ($-opcode_0f)/4
 inst1 _js    _relwrd   trace  ;0f88;jo  label
 inst1 _jns   _relwrd   trace       ;jno label
 inst1 _jp    _relwrd   trace       ;jc  label
 inst1 _jnp   _relwrd   trace       ;jnc label
 inst1 _jl    _relwrd   trace       ;je  label
 inst1 _jge   _relwrd   trace       ;jne label
 inst1 _jle   _relwrd   trace       ;jbe label
 inst1 _jg    _relwrd   trace       ;ja  label

op_0f90 equ ($-opcode_0f)/4
 inst1 _seto  _rmb             ;0f90;seto  r/m8
 inst1 _setno _rmb                  ;setno r/m8
 inst1 _setc  _rmb                  ;setc  r/m8
 inst1 _setnc _rmb                  ;setnc r/m8
 inst1 _sete  _rmb                  ;sete  r/m8
 inst1 _setne _rmb                  ;setne r/m8
 inst1 _setbe _rmb                  ;setbe r/m8
 inst1 _seta  _rmb                  ;seta  r/m8
op_0f98 equ ($-opcode_0f)/4
 inst1 _sets  _rmb             ;0f98;seto  r/m8
 inst1 _setns _rmb                  ;setno r/m8
 inst1 _setp  _rmb                  ;setc  r/m8
 inst1 _setnp _rmb                  ;setnc r/m8
 inst1 _setl  _rmb                  ;sete  r/m8
 inst1 _setge _rmb                  ;setne r/m8
 inst1 _setle _rmb                  ;setbe r/m8
 inst1 _setg  _rmb                  ;seta  r/m8
op_0fa0 equ ($-opcode_0f)/4
 inst1 _push  _fs_gs           ;0fa0;push fs
 inst1 _pop   _fs_gs                ;pop fs
 inst1 _cpuid _none                 ;cpuid (486+, EAX=cmd)
 inst1 _bt    _rm_r16               ;bt r/m16,reg16 (16/32)
 inst1 _shld  _rm_r16_sc            ;shld r/m,reg,imm
 inst1 _shld  _rm_r16_sc            ;shld r/m,reg,cl
 inst1 _invl  _none
 inst1 _invl  _none
op_0fa8 equ ($-opcode_0f)/4
 inst1 _push  _fs_gs             ;a8;push gs
 inst1 _pop   _fs_gs                ;pop gs
 inst1 _rsm   _none                 ;rsm (return from system management mode)
 inst1 _bts   _rm_r16               ;bts
 inst1 _shrd  _rm_r16_sc            ;shrd r/m,reg,imm
 inst1 _shrd  _rm_r16_sc            ;shrd r/m,reg,cl
 inst1 _invl  _none
 inst1 _imul  _reg_rm               ;imul
op_0fb0 equ ($-opcode_0f)/4
 inst1 _cmpxch _rm_reg         ;0fb0;r/m8,r16
 inst1 _cmpxch _rm_reg              ;
 inst1 _lss   _r16_rm               ;lss reg,r/m
 inst1 _btr   _rm_r16               ;bt
 inst1 _lfs   _r16_rm               ;lfs reg,r/m
 inst1 _lgs   _r16_rm               ;lgs reg,r/m
 inst1 _movzx _r16_rm8              ;r16/32,r/m8
 inst1 _movzx _r32_rm16             ;r32,r/m16
op_0fc0 equ ($-opcode_0f)/4
 inst1 _xadd  _rm_reg          ;0fc0;
 inst1 _xadd  _rm_reg
 inst1 _invl  _none
 inst1 _invl  _none
 inst1 _invl  _none
 inst1 _invl  _none
 inst1 _invl  _none
 inst1 _cmpxch _rm_reg              ;8 bytes
op_0fc8 equ ($-opcode_0f)/4
 inst1 _bswap _r32             ;0fc8;
 inst1 _bswap _r32
 inst1 _bswap _r32
 inst1 _bswap _r32
 inst1 _bswap _r32
 inst1 _bswap _r32
 inst1 _bswap _r32
 inst1 _bswap _r32
op_0fd0 equ ($-opcode_0f)/4
 inst1 _invl  _none                 ;
 inst1 _psrlw    _mmx_rm64          ;d1
 inst1 _psrld    _mmx_rm64          ;d2
 inst1 _psrlq    _mmx_rm64          ;d3
 inst1 _invl  _none                 ;
 inst1 _pmullw   _mmx_rm64          ;
;inst1 _invl  _none                 ;
;inst1 _invl  _none                 ;
op_0fb8 equ ($-opcode_0f)/4
 inst1 _invl  _none            ;0fb8;
 inst1 _ud1   _none                 ;UD1
 inst2 _gr0fba
 inst1 _btc   _rm_r16               ;btc r/m,r16
 inst1 _bsf   _r16_rm               ;bsf r16,r/m
 inst1 _bsr   _r16_rm               ;bsr r16,r/m
 inst1 _movsx _r16_rm8              ;r16/32,r/m8
 inst1 _movsx _r32_rm16             ;r32,r/m16
op_0fd8 equ ($-opcode_0f)/4
 inst1 _psubusb  _mmx_rm64          ;d8
 inst1 _psubusw  _mmx_rm64          ;d9
 inst1 _invl  _none                 ;
 inst1 _pand     _mmx_rm64          ;
 inst1 _invl  _none                 ;
 inst1 _paddusb  _mmx_rm64          ;
 inst1 _paddusw  _mmx_rm64          ;
 inst1 _pandn    _mmx_rm64          ;
op_0fe8 equ ($-opcode_0f)/4
 inst1 _psubsb   _mmx_rm64          ;e8
 inst1 _psubsw   _mmx_rm64          ;e9
 inst1 _invl  _none                 ;
 inst1 _por      _mmx_rm64          ;
 inst1 _paddsb   _mmx_rm64          ;
 inst1 _paddsw   _mmx_rm64          ;
 inst1 _invl  _none                 ;
 inst1 _pxor     _mmx_rm64          ;
op_0ff8 equ ($-opcode_0f)/4
 inst1 _psubb _mmx_rm64             ;f8
 inst1 _psubw _mmx_rm64             ;f9
 inst1 _psubd _mmx_rm64             ;fa
 inst1 _invl  _none                 ;
 inst1 _paddb _mmx_rm64             ;fc
 inst1 _paddw _mmx_rm64             ;fd
 inst1 _paddd _mmx_rm64             ;fe
;inst1 _invl  _none                 ;
op_0ff0 equ ($-opcode_0f)/4
 inst1 _invl  _none                 ;
 inst1 _psllw    _mmx_rm64          ;f1
 inst1 _pslld    _mmx_rm64          ;f2
 inst1 _psllq    _mmx_rm64          ;f3
 inst1 _invl  _none                 ;
 inst1 _pmaddwd _mmx_rm64           ;f5
 inst1 _invl  _none                 ;
;inst1 _invl  _none                 ;
op_0fe0 equ ($-opcode_0f)/4
 inst1 _invl  _none                 ;
 inst1 _psraw    _mmx_rm64          ;e1
 inst1 _psrad    _mmx_rm64          ;e2
 inst1 _invl  _none                 ;
 inst1 _invl  _none                 ;
 inst1 _pmulhw   _mmx_rm64          ;
 inst1 _invl  _none                 ;
 inst1 _invl  _none                 ;

_ndp_gr3 label word
_d9d0   dw _fnop    -X0         ;fnop
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0
_d9e0   dw _fchs    -X0         ;fchs
        dw _fabs    -X0         ;fabs
        dw _f???    -X0
        dw _f???    -X0
        dw _ftst    -X0         ;ftst
        dw _fxam    -X0         ;fxam
        dw _f???    -X0
        dw _f???    -X0
_d9e8   dw _fld1    -X0         ;fld1
        dw _fldl2t  -X0         ;fldl2t
        dw _fldl2e  -X0         ;fldl2e
        dw _fldpi   -X0         ;fldpi
        dw _fldlg2  -X0         ;fldlg2
        dw _fldln2  -X0         ;fldln2
        dw _fldz    -X0         ;fldz
        dw _f???    -X0
_d9f0   dw _f2xm1   -X0         ;f2xm1
        dw _fyl2x   -X0         ;fyl2x
        dw _fptan   -X0         ;fptan
        dw _fpatan  -X0         ;fpatan
        dw _fxtract -X0         ;fxtract
        dw _fprem1  -X0         ;fprem1
        dw _fdecstp -X0         ;fdecstp
        dw _fincstp -X0         ;fincstp
_d9f8   dw _fprem   -X0         ;fprem
        dw _fyl2xp1 -X0         ;fyl2xp1
        dw _fsqrt   -X0         ;fsqrt
        dw _fsincos -X0         ;fsincos
        dw _frndint -X0         ;frndint
        dw _fscale  -X0         ;fscale
        dw _fsin    -X0         ;fsin
        dw _fcos    -X0         ;fcos
_dbe0   dw _feni    -X0         ;feni
        dw _fdisi   -X0         ;fdisi
        dw _fclex   -X0         ;fclex
        dw _finit   -X0         ;finit
        dw _fsetpm  -X0         ;fsetpm
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0
_dfe0   dw _fstsw   -X0         ;fstsw ax
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0
        dw _f???    -X0

F_cnt   = 1                     ; 0 reserved for group2
F_type  macro   x
        _t_&x = F_cnt
        F_cnt = F_cnt + 1
        dd OFFSET32 _f_&x
        endm

F_inst1 macro   x, y
        IF      (_&x - X0) GT 0fffh
        .ERR Address _&x off range.
        ENDIF
        dw      (_&x - X0) + _t_&y*1000h
        endm

F_inst2 macro   x
        IF      (_&x - _ndp_gr3) GT 0fffh
        .ERR Address _&x off range.
        ENDIF
        dw      (_&x - _ndp_gr3)
        endm

F_inst  macro   x, y
        IFB     <y>
        F_inst2 x
        ELSE
        F_inst1 x, y
        ENDIF
        endm

        ;      0        2        4        6
ndptype dw  _F32-X0, _I32-X0, _F64-X0, _I16-X0, _R80-X0, _I64-X0, _B80-X0

_ndp_type label dword
        F_type  none
        F_type  R32
        F_type  I32
        F_type  R64
        F_type  I16
        F_type  R80
        F_type  I64
        F_type  B80
        F_type  STi
        F_type  MEM

F_insts macro   i1, i2, i3, i4
        F_inst  i1
        F_inst  i2
        F_inst  i3
        F_inst  i4
        endm


_ndp_gr1 label word
;           ==>   ----D9-----   ---DB----   ----DD-----   ----DF----
        F_insts  <fld    R32 > <fld  I32 > <fld    R64 > <fld   I16 >
        F_insts  <f???   none> <f??? none> <f???   none> <f???  none>        
        F_insts  <fst    R32 > <fst  I32 > <fst    R64 > <fst   I16 >
        F_insts  <fstp   R32 > <fstp I32 > <fstp   R64 > <fstp  I16 >
        F_insts  <fldenv MEM > <f??? none> <frstor MEM > <fld   B80 >
        F_insts  <fldcw  MEM > <fld  R80 > <f???   none> <fld   I64 >
        F_insts  <fstenv MEM > <f??? none> <fsave  MEM > <fstp  B80 >
        F_insts  <fstcw  MEM > <fstp R80 > <fstsw  MEM > <fstp  I64 >
_ndp_gr2 label word
        F_insts  <fld    STi > <f??? none> <ffree  STi > <ffree STi >
        F_insts  <fxch   STi > <f??? none> <fxch   STi > <fxch  STi >
        F_insts  <d9d0       > <f??? none> <fst    STi > <fst   STi >
        F_insts  <fstp   STi > <f??? none> <fstp   STi > <fstp  STi >
        F_insts  <d9e0       > <dbe0     > <fucom  STi > <dfe0      >
        F_insts  <d9e8       > <f??? none> <fucomp STi > <f???  none>
        F_insts  <d9f0       > <f??? none> <f???   none> <f???  none>
        F_insts  <d9f8       > <f??? none> <f???   none> <f???  none>

_ndpgr1 dw _fadd  - X0     ;00;fadd
        dw _fmul  - X0        ;fmul
        dw _fcom  - X0        ;fcom
        dw _fcomp - X0        ;fcomp
        dw _fsub  - X0     ;04;fsub
        dw _fsubr - X0        ;fsubr
        dw _fdiv  - X0        ;fdiv
        dw _fdivr - X0        ;fdivr

sysinst db op_0f00, op_0f08, 0f8h,    0f8h      ; 00-1f
        db op_0f20, 0f8h,    op_0f30, 0f8h      ; 20-3f
        db op_0f40, op_0f48, 0f8h,    0f8h      ; 40-5f
        db op_0f60, op_0f68, op_0f70, op_0f78   ; 60-7f
        db op_0f80, op_0f88, op_0f90, op_0f98   ; 80-9f
        db op_0fa0, op_0fa8, op_0fb0, op_0fb8   ; a0-bf
        db op_0fc0, op_0fc8, op_0fd0, op_0fd8   ; c0-df
        db op_0fe0, op_0fe8, op_0ff0, op_0ff8   ; e0-ff

regnm8  db  'ALCLDLBLAHCHDHBH'
regnm16 db  'AXCXDXBXSPBPSIDI'
segnam  db  'ESCSSSDSFSGS????'

;input: EBX    linear address of the first byte of instruction
;       ECX    segment/selector of the CS
;       DS=CS
;output C=0    use trace
;       C=1    Use step (EBX valid)

PUBPROC stepIns
        xor     eax, eax
        test    ecx, ecx
        js      short stpIns1
        lar     eax, ecx
        shr     eax, 8+6                ;ah=override flags
_k@prefix:
stpIns1:xor     ecx, ecx
        call    read_byte_cl
        movzx   esi, word ptr opcode1[ecx*4][0]
        movzx   edx, byte ptr opcode1[ecx*4][3]
        jmp     StepType[edx*8]

_k@0f:
;       286/386 prefix 0fh
        call    read_byte_cl
        mov     dl, cl
        shr     dl, 3
        mov     al, cl
        and     al, 7
        add     al, sysinst[edx]
        cmp     al, 0f8h
        jae     short _k@trace
        mov     dl, al
        movzx   esi, word ptr opcode_0f[edx*4]
        mov     dl, byte ptr opcode_0f[edx*4][3]
        jmp     StepType[edx*8]

_k@inst_2:
        call    read_byte_cl
        mov     dl, 7*8
        and     dl, cl
        shr     dl, 1
        lea     esi, opcode2[esi+edx]
        mov     dl,  byte ptr [esi+3]
        movzx   esi, word ptr [esi]
        jmp     StepType[edx*8]

_k@opr32:
        xor     ah, OPR32
        jmp     short stpIns1

_k@adr32:
        xor     ah, ADR32
        jmp     short stpIns1

_k@stepm1:
        call    read_byte_cl
_k@stepm2:
        call    rm_bytes
        stc                     ;use step
        ret
_k@stepf:
        inc     ebx
        inc     ebx
_k@step3a:
        inc     ebx
        test    ah, OPR32
        jz      short _k@step2
        inc     ebx
        inc     ebx
_k@step2:
        inc     ebx
_k@step1:
        stc                     ;use step
        ret

_k@stepx:
        test    [ebp].R_CS, 80000003h
        jnz     short _k@step2
        call    read_byte_cl
        cmp     cl, 20h         ; INT 20h is special
        jne     short _k@step1
        call    loddwrd
        DBGBRK  3
        shl     ah, 1           ;cf=1 if VXDjump
        cmc                     ;step(cf=1) if VXDcall
        ret

_k@trace:
        clc                     ;use trace
        ret

rm_bytes:
        mov     al, cl
        and     al, 7
        cmp     cl, 0c0h
        jae     short rm_w3
        test    ah, ADR32   ;32 bit addressing mode
        jnz     short rm_d1
        test    cl, 0c0h
        jz      short rm_w0
        jns     short rm_w1
rm_w2:  inc     ebx
rm_w1:  inc     ebx
rm_w3:  ret
rm_w0:  cmp     al, 6
        je      short rm_w2
        ret

rm_d1:  cmp     al, 4
        jne     short rm_d2
        call    read_byte_al_p1 ;SIB
        and     al, 7           ;base
rm_d2:  test    cl, 0c0h
        jz      short rm_l0
        test    cl, cl
        jns     short rm_w1
rm_d3:  add     ebx, 4
        ret
rm_l0:  cmp     al, 5
        je      short rm_d3
        ret

; ***************************************************************************
; input: EBX =  linear address of first byte of instruction
;        EAX =  segment/selector of CS
; output C=0    EAX:ESI  Effective address of instruction
;        C=1    No effective address
; ***************************************************************************

PUBPROC effAddr
        DBGBRK  3
        xor     edi, edi                ;0=no segment override
        xor     edx, edx
        test    eax, eax
        js      short effadr0
        lar     edx, eax
        shr     edx, 8+6
        and     dh, OPR32 + ADR32       ;dh=override flags
                                        ;bit0=32 bit operand size
                                        ;bit1=32 bit address size
Adr@_prefix:
effadr0:xor     eax, eax
        call    read_byte_al_p1
        movzx   esi, word ptr opcode1[eax*4]
        mov     cl, byte ptr opcode1[eax*4][2]
effadr1:and     ecx, 3fh
        jnz     short effadr2
        call    read_byte_al_p1         ;r/m byte
        mov     cl, 7*8
        and     cl, al
        shr     cl, 1
        add     esi, ecx
        mov     cl, 3fh
        and     cl, byte ptr opcode2[esi][2]
        movzx   esi, word ptr opcode2[esi]
effadr2:jmp     dword ptr effAdrTypeTable[ecx*4]

Adr@_segovr:
;       Prefix instructions
        cmp     al,3eh                  ;DS:
        je      short ds_prfx
        cmp     al,36h                  ;SS:
        je      short ss_prfx
        cmp     al,2eh                  ;CS:
        je      short cs_prfx
        cmp     al,26h                  ;ES:
        je      short es_prfx
        cmp     al,64h                  ;FS:
        je      short fs_prfx
        cmp     al,65h                  ;GS:
        jne     short effadr0
        lea     edi, [ebp].R_GS
        jmp     short effadr0
fs_prfx:lea     edi, [ebp].R_FS
        jmp     short effadr0
es_prfx:lea     edi, [ebp].R_ES
        jmp     short effadr0
ds_prfx:lea     edi, [ebp].R_DS
        jmp     short effadr0
ss_prfx:lea     edi, [ebp].R_SS
        jmp     short effadr0
cs_prfx:lea     edi, [ebp].R_CS
        jmp     short effadr0

Adr@_32ovr:
        sub     al,65h                  ;66->1, 67->2
        xor     dh,al
        jmp     short effadr0

Adr@_0fp:
;       286/386 prefix 0fh
        call    read_byte_al_p1
        mov     dl, al                   ;1st byte
        shr     al, 3
        mov     cl, 7
        and     cl, dl
        add     cl, sysinst[eax]
        cmp     al, 0f8h
        jae     short no_efad
        movzx   esi, word ptr opcode_0f[ecx*4]
        mov     cl, byte ptr opcode_0f[ecx*4][2]
        jmp     effadr1

Adr@_none:
Adr@_r16:
Adr@_r32:
Adr@_seg:
Adr@_rel8:
Adr@_relwrd:
Adr@_seg_off:
Adr@_int_nn:
Adr@_nn:
Adr@_nnnn:
Adr@_nnnnw:
Adr@_ax_r16:
Adr@_acc_imm:
Adr@_reg_imm:
Adr@_sx8:
Adr@_nnnn_nn:
Adr@_fs_gs:
Adr@_in_nn:
Adr@_in_dx:
Adr@_out_nn:
Adr@_out_dx:
Adr@_sb_or_sw:
Adr@_d_for_32:
Adr@_16_or_32:
no_efad:stc
        ret
Adr@_0f_2x:
Adr@_reg_rm:
Adr@_rm_reg:
Adr@_rm_r16:
Adr@_seg_rm:
Adr@_rm_seg:
Adr@_r16_rm:
Adr@_r16_rm8:
Adr@_r32_rm16:
Adr@_reg_rm_sx8:
Adr@_reg_rm_nnnn:
Adr@_rm_r16_sc:
Adr@_float:
Adr@_rmb:
Adr@_mmx_rm64:
Adr@_rm64_mmx:
Adr@_mmx_rm32:
Adr@_rm32_mmx:
        call    read_byte_al_p1
Adr@_rm:
Adr@_rmw:
Adr@_dword:
Adr@_rmw_nn:
Adr@_mmx_imm8:
Adr@_rm_imm:
Adr@_rm_sx8:
Adr@_rm_sc:
Adr@_mem24:
;       r/m     al=r/m byte, dl=opcode1, dh=flags
        cmp     al, 0c0h
        jae     short no_efad
        xor     esi, esi
        mov     dl, al
        and     al, 7
        test    dh, ADR32       ;32 bit addressing mode
        jnz     short ea32bit
        test    dl, 0c0h
        jz      short ea_mod0
        js      short ea_mod2
        call    read_byte_cl
        movsx   esi, cl
        jmp     a16mode[eax*4]
ea_mod2:xchg    eax, esi
        call    read_word_ax
        inc     ebx
        inc     ebx
        xchg    eax, esi
ea_modd:jmp     a16mode[eax*4]
ea_mod0:cmp     al, 6
        jne     short ea_modd
ea16dir:call    read_word_ax
        inc     ebx
        inc     ebx
        movzx   esi, ax
        jmp     short ds_defl

ea32bit:cmp     al, 4
        jne     short ea_base
        call    read_byte_al_p1 ;SIB
        mov     cl, 7*8         ;index bits
        and     cl, al
        cmp     cl, 4*8         ;index=4 mean no index register
        je      short ea_sibb
        xor     cl, 7*8         ;reverse order
        shr     ecx, 1
        mov     esi, [ebp].R_EDI[ecx]
        mov     cl, al
        shr     cl, 6           ;scale factor
        shl     esi, cl
ea_sibb:and     al, 7
ea_base:test    dl, 0c0h        ;mod=00
        jz      short ea32mm0
        js      short ea32mm2
        call    read_byte_cl
        movsx   ecx, cl
        add     esi, ecx
        jmp     a32mode[eax*4]
ea32mm2:xchg    eax, ecx
        call    read_dword_eax
        add     ebx, 4
        add     esi, eax
        jmp     a32mode[ecx*4]
ea32mm0:cmp     al, 5
        je      short ea32dir
        jmp     a32mode[eax*4]
Adr@_acc_addr:
Adr@_addr_acc:
        xor     esi, esi
        test    dh, ADR32       ;32 bit addressing mode
        jz      short ea16dir
ea32dir:call    read_dword_eax
        add     ebx, 4
        add     esi, eax
ds_defl:mov     eax, [ebp].R_DS
segovrr:test    edi, edi
        jz      short usedefs
        mov     eax, [edi]
usedefs:test    dh, ADR32
        jnz     short reteadr
        movzx   esi, si
reteadr:ret

rm__eax:add     esi,[ebp].R_EAX
        jmp     short ds_defl
rm__ecx:add     esi,[ebp].R_ECX
        jmp     short ds_defl
rm__edx:add     esi,[ebp].R_EDX
        jmp     short ds_defl
rm__00: add     esi,[ebp].R_EBX
rm__esi:add     esi,[ebp].R_ESI
        jmp     short ds_defl
rm__01: add     esi,[ebp].R_EDI
rm__ebx:add     esi,[ebp].R_EBX
        jmp     short ds_defl
rm__esp:add     esi,[ebp].R_ESP
        jmp     short ss_defl
rm__edi:add     esi,[ebp].R_EDI
        jmp     short ds_defl
rm__03: add     esi,[ebp].R_EDI
        jmp     short rm__ebp
rm__02: add     esi,[ebp].R_ESI
rm__ebp:add     esi,[ebp].R_EBP
ss_defl:mov     eax,[ebp].R_SS
        jmp     segovrr


; ***************************************************************************
;In:      EBX = pointer to first byte of instruction
;   actual_IP = offset of EIP in the segment
;Out:     EBX = pointer to next instruction
;   actual_IP = offset of next instruction
; ***************************************************************************

PUBPROC dispins
        DBGBRK  3
        mov     edi, OFFSET32 dissBuffOff

        mov     eax, actual_IP
        mov     edx, Code_Data_Ptrs[PNTR_CODE][4]
        test    edx, edx
        js      short @f
        call    GetSymNameForAddress
        jc      short @f
        mov     al, 0
        stosb
@@:     mov     eax, actual_IP
        call    hex_32
        push    edi
        mov     ecx, (dissBuffEnd - dissBuffOff - 8)
        mov     al, 20h
        rep     stosb
        sub     edi, (dissBuffEnd - dissBuffOpcode)
        mov     OpcBufPtr, edi
        mov     al, def_segsize
        and     eax, OPR32 + ADR32
        mov     word ptr rm_type, ax ;rm_type, sg_name=0
        push    ebx
dspins1:call    lodbyt
        mov     cl, al
        movzx   esi, word ptr opcode1[ecx*4][0]
        mov     dl, byte ptr opcode1[ecx*4][2]
dspins2:and     edx, 3fh
        jnz     short dspins3
        call    lodbyt
        mov     ch, al
        and     eax, 7*8
        shr     al, 1
        mov     dl, 3fh
        and     dl,  byte ptr opcode2[esi+eax][2]
        movzx   esi, word ptr opcode2[esi+eax][0]
dspins3:call    PutName
        mov     esi, edi
        mov     eax, OpcBufPtr
        add     eax, 8
dspins4:mov     byte ptr [edi], ' '
        inc     edi
        cmp     edi, eax
        jb      short dspins4
        call    InstTypeTable[edx*4]
        mov     word ptr [edi], 0
        mov     ecx, ebx
        pop     ebx
        pop     edi
        inc     edi
        push    ecx
        sub     ecx, ebx
        cmp     ecx, 9
        jb      short dsphex
        mov     cl, 8
dsphex: call    lodbyt1
        jc      short dsphex2
        call    hex_08
dsphex1:loop    short dsphex
        pop     ebx
nret1:  ret
dsphex2:mov     al, '?'
        stosb
        stosb
        jmp     short dsphex1

Opc@_32ovr:; 32 bit operand (66h), address (67h) override
        sub     cl, 65h         ;66->1, 67->2
        xor     rm_type, cl
        lea     edi, [esi-1]    ;back to the column
nxtPrfx:pop     esi             ;remove ret address
        jmp     dspins1

Opc@_segovr:;                   seg: override
        mov     al, [esi-3]     ;seg name (d/c/e/s/f/g)
        xchg    al, sg_name
        cmp     al, 0           ;1st time?
        jne     short put_sgo
        mov     word ptr [esi-2], '  '
        lea     edi, [esi-3]    ;back up column
        jmp     short nxtPrfx
put_sgo:mov     [esi-3], al     ;xS:
        ret

Opc@_prefix:;                   Prefix instructions
;;      cmp     edi, OFFSET32 dissBuffOprs
;;      je      short nxtPrfx
        lea     edi, [esi+1]
        jmp     short nxtPrfx

Opc@_reg_rm_sx8:;               reg,r/m,+n/-n
        call    Opc@_r16_rm
        jmp     short comasn
Opc@_rm_sx8:;                   r/m,+n/-n
        call    memType
comasn: mov     al,','
        stosb
Opc@_sx8:;                      +n/-n
        call    lodbyt
        mov     ah,'+'
        test    al,al
        jns     short psign
        neg     al
        mov     ah,'-'
psign:  mov     byte ptr[edi],ah
        inc     edi
        jmp     short hex_08
Opc@_rel8:;                     label rel.8
        cmp     cl, 0e3h        ;jcxz/jecxz
        jne     short @f
        call    Opc@_16_or_32
@@:     call    lodbyt
        movsx   eax,al
        add     eax, actual_IP
        test    rm_type, OPR32
        jz      short label_16
label_32:
        DBGBRK  3
        push    ecx
        push    eax
        call    GetP32NameFromAddress
        pop     eax
        pop     ecx
        jnc     short lbl32Done
        ; Address not found, now try its contents if flat memory
        test    def_segsize, DEFSEG_ZBASE ; base=0?
        jz      short hex_32
        cmp     byte ptr [edi-1], '['
        jne     short hex_32
        push    ecx
        push    eax
        xchg    esi, eax
        call    dword_read_@esi
        jc      short @f
        call    GetP32NameFromAddress
@@:     pop     eax
        pop     ecx
        jnc     short lbl32Done
PUBPROC hex_32
        call    hexhw
hexhw:  ror     eax,16
PUBPROC hex_16
        call    hexah
hexah:  xchg    ah,al
PUBPROC hex_08
        push    eax
        shr     al,4
        cmp     al,10
        cmc
        adc     al,'0'
        daa
        stosb
        pop     eax
PUBPROC hex_04
        and     al,0fh
        cmp     al,10
        cmc
        adc     al,'0'
        daa
        stosb
lbl32Done:
        ret

label_16:
        mov     edx, Code_Data_Ptrs[PNTR_CODE][4]
        call    V86P16NameFromAddress
        jc      short hex_16
        ret

Opc@_seg_off:;                  seg:off
        test    rm_type, OPR32  ;32 bit operand size
        jnz     short seg_off32
        call    lodwrd
        xchg    edx, eax                ;edx=off
        call    lodwrd
        xchg    edx, eax                ;edx=seg, eax=off
        call    V86P16NameFromAddress
        xchg    edx, eax                ;eax=seg, edx=off
        jnc     lbl32Done
        call    hex_16
        mov     al, ':'
        stosb
        xchg    edx, eax
        jmp     hex_16
seg_off32:
        call    loddwrd
        xchg    edx, eax
        call    lodwrd
        xchg    edx, eax                ;edx=seg, eax=off
        push    eax
        push    edx
        call    GetP32NameFromAddress
        pop     eax                     ;seg
        pop     edx                     ;off
        jnc     lbl32Done
        call    hex_16
        mov     al, ':'
        stosb
        xchg    edx, eax
        jmp     hex_32

PutName:add     esi, OFFSET32 X0
PutNam1:lodsb
        and     al, 15          ;length field
PutNam2:movsb
        dec     al
        jnz     PutNam2
        ret

Opc@_r32_rm16:;                 movsx/movzx r32,r/m16
        call    lodbyt
        mov     ch, al
        or      rm_type, OPR32
        mov     cl, 1           ;16/32 bits
        call    regstr
        and     rm_type, not OPR32 ;16 bits
        mov     al, ','
        stosb
        jmp     short memType
Opc@_r16_rm8:;                  movsx/movzx r16/32,r/m8
        call    lodbyt
        mov     ch,al
        mov     cl,1            ;16/32 bits
        call    regstr
        mov     cl,0            ;byte
        mov     al,','
        stosb
        jmp     short memType
Opc@_r16_rm:;                   r16,r/m
        mov     cl, 1
Opc@_reg_rm:;                   reg,r/m
        call    lodbyt
        mov     ch, al
reg_mem:call    regstr
and_mem:mov     al, ','
        stosb
Opc@_mem24:;                    r/m (for gdt and idt)
_f_MEM:
rm_addr:cmp     ch, 0c0h
        jb      short mem_adr
mode3:  mov     dl, ch
reg_xx: and     edx, 7
        test    cl, 1
        jz      short reg8
        add     edx, 8
        test    rm_type, OPR32  ;32 operand size
        jz      short reg8
        mov     al, 'E'
        stosb
reg8:   mov     ax, word ptr regnm8[edx*2]
        stosw
        ret

Opc@_dword:;                    dword/fword ptr r/m
        test    rm_type, OPR32  ;32 operand size
        jz      short rm_dword
        mov     al, 'F'
        jmp     short rm_xword

Opc@_rm:;                       r/m     .......w mm...r/m
memType:cmp     ch, 0c0h
        jae     short mode3
        mov     esi, OFFSET32 _byte
        test    cl, 1
        jz      short mem_typ
        test    rm_type, OPR32  ;32 operand size
        jz      short rm_word
rm_dword:
        mov     al, 'D'
rm_xword:
        stosb
rm_word:mov     esi, OFFSET32 _word
mem_typ:movsd                   ; WORD/BYTE
        movsd                   ; _PTR
        movsb                   ; _
mem_adr:mov     al, sg_name
        test    al, al
        jz      short memaddr
        stosb
        mov     ax, ':S'
        stosw
memaddr:mov     al, '['
        stosb
        mov     dl, ch
        and     edx, 7
        test    rm_type, ADR32  ;32 bit addressing mode
        jnz     short rm32bit
        test    ch, 0c0h
        jz      short mode0
        movzx   esi, word ptr modtbl[edx*2]
        call    PutName
        test    ch,ch
        js      short mode2
        call    Opc@_sx8
        mov     al,']'
        stosb
        ret
mode2:  mov     al,'+'
        stosb
mode2d: call    immwrd
        mov     al,']'
        stosb
        ret
mode0:  cmp     dl,6
        je      short mode2d
        movzx   esi,word ptr modtbl[edx*2]
        call    PutName
        mov     al,']'
        stosb
        ret

Opc@_mmx_rm64:
        call    lodbyt
        mov     ch, al
        call    mmxreg
        mov     al, ','
        stosb
mmxmem64:
        cmp     ch, 0c0h
        jb      short mem_adr
        mov     al, 'M'
        stosb
        stosb
        mov     al, ch
        and     al, 7
        add     al, '0'
        stosb
        ret

Opc@_rm_r16:;                   r/m,r16
        or      cl, 1
Opc@_rm_reg:;                   r/m,reg
        call    lodbyt
        mov     ch, al
mem_reg:call    rm_addr
        mov     al, ','
        stosb
regstr: mov     dl, ch
        shr     dl, 3
        jmp     reg_xx

rm32bit:cmp     dl, 4
        jne     short chkmod
        call    lodbyt          ;SIB
        mov     dl, al
        and     eax, 7*8         ;index bits
        cmp     al, 4*8          ;index=4 mean no index register
        je      short sibbase
        mov     esi, eax
        shr     esi, 2
        mov     ax, 0c001h
        and     ah, dl
        jz      short sibscl2
sibscl1:shl     al, 1
        sub     ah, 40h
        ja      short sibscl1
        add     ax, 2a30h
        stosw                   ;n*
sibscl2:mov     al, 'E'
        stosb
        mov     ax, word ptr regnm16[esi]
        stosw
        mov     al, '+'
        stosb
sibbase:and     dl, 7
chkmod: test    ch, 0c0h        ;mod=00
        jz      short mod00
        mov     al, 'E'
        stosb
        mov     ax, word ptr regnm16[edx*2]
        stosw
        test    ch, ch
        js      short mod10
        call    Opc@_sx8        ;disp8
        mov     al, ']'
        stosb
        ret
mod10:  mov     al, '+'
        stosb
        call    immdwrd
        mov     al, ']'
        stosb
        ret
mod2d:  call    loddwrd
        call    label_32
        mov     al, ']'
        stosb
        ret
mod00:  cmp     dl, 5
        je      short mod2d
        mov     al, 'E'
        stosb
        mov     ax, word ptr regnm16[edx*2]
        stosw
        mov     al, ']'
        stosb
        ret
        
Opc@_rmb:;                      r/m8    ........ mm...r/m
        mov     cl, 0
        call    lodbyt          ;r/m
        mov     ch, al
        jmp     memType
Opc@_rmw:;                      word ptr r/m
        mov     cl, 1
        jmp     memType

Opc@_seg_rm:;                   seg,r/m
        call    lodbyt
        mov     ch, al
        call    sgname
        mov     cl, 1
        jmp     and_mem
Opc@_rmw_nn:;                   r/m16/32,imm8
        call    Opc@_rmw
        jmp     and_nnb

Opc@_acc_addr:;                 Acc,address
        test    rm_type, ADR32
        sete    ch              ;00=32, 01=16
        add     ch, 5           ;05=32, 06=16
        jmp     reg_mem
Opc@_addr_acc:;                 address,Acc
        test    rm_type, ADR32
        sete    ch              ;00=32, 01=16
        add     ch, 5           ;05=32, 06=16
        jmp     mem_reg
Opc@_rm_seg:;                   r/m,seg
        call    lodbyt
        mov     ch, al
        mov     cl, 1
        call    rm_addr
        mov     al, ','
        stosb
sgname: mov     al, ch
        shr     al, 2
        and     eax, 7*2
        mov     ax, word ptr segnam[eax]
        stosw
        ret

Opc@_acc_imm:;                  Acc, imm
        shl     cl, 3
Opc@_reg_imm:;                  reg,imm
        call    r16nam
        test    cl, 8
        jz      short and_nnb
and_nnw:mov     al, ','
        stosb
Opc@_nnnnw:;                    push nnnn (16/32)
        test    rm_type, OPR32  ;32 bit operand size
        jz      short immwrd
immdwrd:call    loddwrd
        jmp     hex_32
Opc@_nnnn: ;                    nnnn
immwrd: call    lodwrd
        jmp     hex_16
Opc@_reg_rm_nnnn:;              reg,r/m,nnnn
        call    Opc@_r16_rm
        jmp     and_nnw
Opc@_rm_r16_sc:;                rm16/32,reg,cl/nn
        bts     ecx, 0
        jc      short Opc@_rm_reg_cl
        call    Opc@_rm_r16     ;cl&1 for 16/32
        jmp     short and_nnb

Opc@_rm_reg_cl:
        call    Opc@_rm_reg
and_cl: mov     al,','
        stosb
        mov     ax,'LC'             ;cl
        stosw
        ret
Opc@_rm_sc:;                    r/m,1/cl/nn
        call    Opc@_rm
        test    cl,16
        jz      short and_nnb
        test    cl,2
        jnz     short and_cl
        mov     ax,'1,'
        stosw                       ;,1
        ret
Opc@_nnnn_nn:;                  enter nnnn,nn
        call    immwrd
and_nnb:mov     al,','
        stosb
Opc@_nn:   ;                    nn
        call    lodbyt
        jmp     hex_08
Opc@_int_nn:;                   int nn
        test    Code_Data_Ptrs[PNTR_CODE][4], 80000003h
        jnz     short Opc@_nn
        call    lodbyt
        cmp     al, 20h         ; INT 20h is special
        jne     hex_08
        call    hex_08
        inc     edi
        call    loddwrd
        movzx   edx, ax         ; Service Number
        shr     eax, 16         ; VxD ID
        jmp     GetVxdService

Opc@_rm_imm:;                   r/m,imm (8/16)
        call    memType
        shr     cl, 1
        jnc     short and_nnb
        jmp     and_nnw
Opc@_ax_r16:;                   ax,r16
        test    rm_type, OPR32  ;32 operand size
        jz      short _axnam1
        mov     al,'E'
        stosb
_axnam1:mov     ax,'XA'
        stosw
        mov     al,','
        stosb
Opc@_r16:;                      r16
        or      cl,8
r16nam: test    cl,8            ;word ?
        jz      short r16nam1
        test    rm_type,OPR32   ;32 operand size
        jz      short r16nam1
Opc@_r32:;                      r32
        mov     al,'E'
        stosb
r16nam1:mov     dl, cl
        and     edx, 15
        mov     ax, word ptr regnm8[edx*2]
        stosw
        ret

Opc@_in_dx:
        call    accum
and_dx: mov     al,','
        stosb
        mov     ax,'XD'
        stosw
        ret
Opc@_in_nn:
        call    accum
        jmp     and_nnb
Opc@_out_dx:
        mov     ax,'XD'
        stosw
and_acc:mov     al,','
        stosb
accum:  mov     ax,'LA'         ;al
        test    cl,1
        jz      short accm2
        test    rm_type,OPR32
        jz      short accm1
        mov     byte ptr [edi],'E'
        inc     edi
accm1:  mov     ah,'X'
accm2:  stosw
        ret
Opc@_out_nn:
        call    Opc@_nn
        jmp     and_acc

Opc@_sb_or_sw:; b/w/d in ins/outs/lods/scas/movs/cmps/stos
        mov     eax, ' :SB'     ;s
        test    cl, 1
        jz      short put_s1
        mov     al, 'W'         ;w
        test    rm_type, OPR32
        jz      short put_s1
        mov     al, 'D'         ;d
put_s1: mov     [esi], al       ;to the end of inst
        mov     al, 0
        xchg    al, sg_name     ;seg name (d/c/e/s/f/g)
        test    al, al
        jz      short put_s2
;;      cmp     edi, OFFSET32 dissBuffOprs
;;      ja      short @f
;;      mov     edi, OFFSET32 dissBuffOprs-1
        inc     edi
        stosd                   ;'xS: '
put_s2: ret

Opc@_mmx_imm8:
        call    mmxmem64
        jmp     and_nnb

Opc@_mmx_rm32:
        call    lodbyt
        mov     ch, al
        call    mmxreg
        or      cl, 1
        or      rm_type, OPR32  ;32 operand size
        jmp     and_mem

Opc@_rm32_mmx:
        call    lodbyt
        mov     ch, al
        or      cl, 1
        or      rm_type, OPR32  ;32 operand size
        call    rm_addr
        jmp     short and_mmx

Opc@_rm64_mmx:
        call    lodbyt
        mov     ch, al
        call    mmxmem64
and_mmx:mov     al, ','
        stosb
mmxreg: mov     al, 'M'
        stosb
        stosb
        mov     al, ch
        shr     al, 3
        and     al, 7
        or      al, '0'
        stosb
        ret

Opc@_16_or_32:; select next opcode if 32
        test    rm_type,OPR32
        jz      short ret_d4
        ; change the opcode to the one follows this one
        push    edi
        mov     edi, OpcBufPtr
        movzx   eax, cl
        movzx   esi, word ptr opcode1[eax*4][0]
        mov     al, byte ptr [esi+X0]
        and     al, 15                  ;length of 1st name
        lea     esi, [esi+eax+5]        ;points to next name
        call    PutName
        pop     edi
        ret

Opc@_d_for_32:; add d to push/pop/pushf/popf/iret if 32
        test    rm_type,OPR32
        jz      short ret_d4
        mov     byte ptr [esi],'D'
ret_d4: ret

Opc@_0fp:
        lea     edi, [esi-1]            ;back to dissBuffOpcode (?)
        call    lodbyt
        movzx   edx, al
        shr     dl, 3
        mov     cl, al
        and     al, 7
        add     al, sysinst[edx]
        cmp     al, 0f8h
        jae     short invalid
        mov     dl, al
        pop     esi                     ;remove ret from stack
        movzx   esi, word ptr opcode_0f[edx*4][0]
        mov     dl,  byte ptr opcode_0f[edx*4][2]
        jmp     dspins2

Opc@_relwrd:;                   label rel.16/32
        test    rm_type, OPR32
        jz      short rel16l1
        call    loddwrd
        add     eax, actual_IP
        jmp     label_32
rel16l1:call    lodwrd
        add     eax, actual_IP
        jmp     label_16
invalid:mov     esi, OFFSET32 _invl
        jmp     PutNam1
Opc@_0f_2x:;                    mov CRn/DRn/TRn,r/m
        call    lodbyt
        mov     ch, al
        stc
        rcl     cl, 1           ;for word by rm_addr
        or      rm_type, OPR32  ;32 operand size
        test    cl, 4
        jz      short rdctlr1
        call    CTLreg
        jmp     and_mem
rdctlr1:call    rm_addr
        mov     al, ','
        stosb
CTLreg: mov     ax, 'RT'        ;TR
        test    cl, 8
        jnz     short ctlrg1
        mov     al, 'C'
        test    cl, 2
        jz      short ctlrg1
        mov     al, 'D'         ;CR or DR
ctlrg1: stosw
        mov     al, ch
        shr     al, 3
        and     al, 7
        add     al, '0'
        stosb
        ret
Opc@_seg:;                      seg     ...ss...
        movzx   eax, cl
        and     al, 38h
        shr     al, 2
        mov     ax, word ptr segnam[eax]
        stosw
Opc@_none: ;                    No operand Inst's
        ret
Opc@_fs_gs:;                    push/pop FS/GS
        mov     al, 8
        and     al, cl          ;0=FS, 8=GS
        cmp     al, 8
        mov     ax, 'SG'        ;GS
        sbb     al, 0
        stosw
        ret

Opc@_float:;                    esc : NDP coprocessor
        DBGBRK  2
        call    lodbyt
        mov     ch, al
        mov     dl, ch
        and     edx, 38h
        test    cl, 1
        jnz     short float3
        shr     dl, 2
        push    edi
        mov     edi, esi
        movzx   esi, word ptr _ndpgr1[edx]
        call    PutName
        cmp     ch, 0c0h
        jae     short float1

        mov     dl, 6
        and     dl, cl
        pop     edi
;;      mov     edi, OFFSET32 dissBuffOprs
f__RM:  movzx   esi, word ptr ndptype[edx]
        call    PutName
        mov     al, ' '
        stosb
        jmp     rm_addr

_f_R32:
_f_I32:
_f_R64:
_f_I16:
_f_R80:
_f_I64:
_f_B80: sub     edx, 2*_t_R32
        jmp     f__RM

float1: test    cl, 2
        jz      short float2
        mov     al, 'P'
        stosb
float2: pop     edi
;;      mov     edi, OFFSET32 dissBuffOprs
        test    cl, 4                   ; 0: ST,STi 1: STi
        jnz     short _f_STi
        mov     ax, 'TS'
        stosw
        mov     al, ','
        stosb
_f_STi: mov     ax, 'TS'
        stosw
        mov     al, ch
        and     al, 7
        add     al, '0'
        stosb
_f_none:ret

float3: mov     ah, 6
        and     ah, cl
        add     dl, ah
        cmp     al, 0c0h
        jb      short float4
        add     dl, (_ndp_gr2 - _ndp_gr1)
float4: movzx   eax, word ptr _ndp_gr1[edx]
        mov     dx, 0f000h
        and     edx, eax
        jnz     short float5
        mov     dl, 7
        and     dl, ch
        mov     edi, esi
        movzx   esi, _ndp_gr3[eax+edx*2]
        jmp     PutName
float5: xor     eax, edx
        xchg    esi, eax
        push    edi
        xchg    edi, eax
        call    PutName
        pop     edi
        shr     edx, 11
        jmp     _ndp_type[edx+edx-4]

LCODE_ENDS      ; ===========================================================
end
