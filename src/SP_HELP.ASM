title.  SoftProbe - Help support

SP_HELP EQU 1
include SP_DEFS.inc

; ---------------------------------------------------------------------------
; ** pmCode starts here -----------------------------------------------------
; ---------------------------------------------------------------------------
LCODE_SEG

h_lines = 0
HlpLn   macro   cmd, txt
        ifnb    <cmd>
        db      cmd
        endif
        ifnb    <txt>
        db      d_col,30,txt
        endif
        db      d_sub
        h_lines = h_lines+1
        endm

; WARNING: Do not use number 12 in the text (ie d_col,12) it is used as d_sub

_help_:
 HlpLn <a_b,'Breakpoints'>
 HlpLn 'BP [adr [cond]]'        'Break on execution'
 HlpLn 'BPX [adr [cond]]'       'Break on execution (using h/w breaks)'
 HlpLn 'BPB adr [cond]'         'Break on byte read or write'
 HlpLn 'BPW adr [cond]'         'Break on word read or write'
 HlpLn 'BPD adr [cond]'         'Break on dword read or write'
 HlpLn 'BPBW adr [cond]'        'Break on byte write'
 HlpLn 'BPWW adr [cond]'        'Break on word write'
 HlpLn 'BPDW adr [cond]'        'Break on dword write'
 HlpLn 'BPIO p [cond]'          'Break on port I/O (using h/w breaks)'
 HlpLn 'BIO p [cond]'           'Break on Port I/O'
 HlpLn 'BI n [cond]'            'Break on interrupt'
 HlpLn 'BM module'              'Break on module'
 HlpLn 'BD list'                'Disable breakpoints'
 HlpLn 'BE list'                'Enable breakpoints'
 HlpLn 'BC list'                'Clear breakpoints'
 HlpLn 'BD *'                   'Disable all breakpoints'
 HlpLn 'BE *'                   'Enable all breakpoints'
 HlpLn 'BC *'                   'Clear all breakpoints'
 HlpLn 'BL'                     'List breakpoints'
 HlpLn 'BI1 [ON|OFF]'           'Enable/Disable/Toggle Break on INT 1'
 HlpLn 'BI3 [ON|OFF]'           'Enable/Disable/Toggle Break on INT 3'
 HlpLn 'NMI [ON|OFF]'           'Enable/Disable/Toggle Break on NMI'
IFDEF   _W95_
 HlpLn 'BDO [ON|OFF]'           'Enable/Disable/Toggle Break on Debug Out'
ENDIF
 HlpLn 'BF [GP|PF|SF|OP] [ON|OFF]' 'Enable/Disable Break on Faults'
 HlpLn 'ZAP'                    'Remove embeded INT 3 or INT 1'
 HlpLn
 HlpLn <a_b,'Execution'>
 HlpLn 'T n'                    'Trace code n times'
 HlpLn 'P'                      'Step'
 HlpLn 'Q'                      'Return to the host'
 HlpLn 'G'                      'Return to the host'
 HlpLn 'G adr'                  'Goto address adr'
 HlpLn 'G = adr'                'Restart program from address adr'
 HlpLn 'GC'                     'Go Client Code'
 HlpLn 'GF'                     'Go and ignore fault'
 HlpLn 'END TASK [errcode]'     'Terminate current task'
 HlpLn 'END VM'                 'Terminate current VM'
 HlpLn 'RESET'                  'Reset the system'
 HlpLn 'IF exp cmd'             'If exp is non-zero execute cmd'
 HlpLn 'WHILE exp cmd[;cmd..]'  'While exp is non-zero execute cmd'
 HlpLn <>                       'Example: WHILE CS=28 P'
 HlpLn 'WHILE'                  'Repeats previously defined WHILE'
 HlpLn
 HlpLn <a_b,'Code and Data'>
 HlpLn 'A [adr]'         'Assemble code'
 HlpLn 'U [adr]'         'Un-Assemble code'
 HlpLn 'D [adr]'         'Display data'
 HlpLn 'DB [adr]'        'Display data as byte'
 HlpLn 'DW [adr]'        'Display data as word'
 HlpLn 'DD [adr]'        'Display data as dword'
 HlpLn 'DA [adr]'        'Display data as ascii'
 HlpLn 'DL [adr]'        'Display linear address'
 HlpLn 'DP exp'          'Display physical memory'
 HlpLn 'W [n]'           'Display watch window n (0-7)'
 HlpLn 'WB [exp]'        'Display exp in current watch window as byte'
 HlpLn 'WW [exp]'        'Display exp in current watch window as word'
 HlpLn 'WD [exp]'        'Display exp in current watch window as dword'
 HlpLn 'WA [exp]'        'Display exp in current watch window as ascii'
 HlpLn 'M blk adr'       'Move memory block blk to adr'
 HlpLn 'C blk adr'       'Compare memory block blk with adr'
 HlpLn 'F blk str'       'Fill memory block with str'
 HlpLn 'E adr str'       'Enter memory values'
 HlpLn 'S [blk str]'     'Search for str in memory block blk'
 HlpLn 'PC blk'          'Print memory block blk as code'
 HlpLn 'PB blk'          'Print memory block blk as bytes'
 HlpLn 'PW blk'          'Print memory block blk as words'
 HlpLn 'PD blk'          'Print memory block blk as dwords'
 HlpLn 'PA blk'          'Print memory block blk as ascii'
 HlpLn 'SET CMx[[=]adr]' 'Set code marker (x=0..9)'
 HlpLn 'SET DMx[[=]adr]' 'Set data marker (x=0..9)'
 HlpLn 'CMx'             'Go code marker (x=0..9)'
 HlpLn 'DMx'             'Go data marker (x=0..9)'
 HlpLn 'MC n'            'Scroll code window n lines'
 HlpLn 'MD n'            'Scroll data window n lines'
 HlpLn
 HlpLn <a_b,'Port I/O'>
 HlpLn 'I  port'         'Read I/O port byte'
 HlpLn 'IW port'         'Read I/O port word'
 HlpLn 'ID port'         'Read I/O port dword'
 HlpLn 'O  port val'     'Write byte to I/O port'
 HlpLn 'OW port val'     'Write word to I/O port'
 HlpLn 'OD port val'     'Write dword to I/O port'
 HlpLn 'CAP port1 [port2 [port3]]' 'Capture I/O port(s)'
 HlpLn 'CAP START'       'Start capture again'
 HlpLn 'CAP STOP'        'Stop capture'
 HlpLn 'CAP'             'View Captured data'
 HlpLn 'BIO n'           'Break on i/o port n'
 HlpLn
 HlpLn <a_b,'System Information'>
 HlpLn 'IDT [n]'         'Display Interrupt Descriptor Table'
 HlpLn 'GDT [sel]'       'Display Global Descriptor Table'
 HlpLn 'LDT [sel]'       'Display Local Descriptor Table'
 HlpLn 'SYS'             'Display system registers'
 HlpLn 'TSS [sel]'       'Display Task State Segment'
 HlpLn 'MSR [n]'         'Display Model Specific Registers'
 HlpLn 'VXD [vxdname]'   'Display loaded VxDs or vxdname'
 HlpLn 'PAGE [adr]'      'Display Page Table Entries'
 HlpLn 'PDE [adr]'       'Display Page Directory Entries'
 HlpLn 'HEAP'            'Display global heap'
 HlpLn 'TASK'            'Display loaded tasks'
 HlpLn 'ST'              'Display call stack'
 HlpLn 'VM'              'Display list of VMs'
IFDEF   _W95_
 HlpLn 'MOD [sel|hMod|name]' 'List/display 16-bit modules'
 HlpLn 'MOD32 [name]'    'List 32-bit Modules'
 HlpLn 'TH [handle]'     'Display Threads'
 HlpLn 'AC [handle]'     'Display Address Context'
 HlpLn 'PS [process]'    'Display Process [current] Information'
ELSE
 HlpLn 'MOD [sel|hMod|name]' 'List/display 16-bit modules'
ENDIF
 HlpLn 'ASC [num]'       'Display ASCII table'
IFDEF   _W95_
 HlpLn 'QD vxd'          'Query device vxd'
ENDIF
 HlpLn
 HlpLn <a_b,'V86 Information'>
 HlpLn 'MAP'             'Display DOS memory map'
 HlpLn 'DEV'             'Display DOS device drivers'
 HlpLn 'DI [n]'          'Display DOS interrupts'
 HlpLn 'DI GET'          'Records DOS interrupts'
 HlpLn
 HlpLn <a_b,'Misc'>
 HlpLn 'R reg [=] val'   'Set register value'
 HlpLn 'R flag [=] val'  'Modify EFLAGS bits'
 HlpLn 'H n1 [n2]'       'Hex calculator'
 HlpLn 'LOG ON|OFF'      'Turns logging ON or OFF'
 HlpLn 'LOG CLEAR'       'Clears log buffer'
 HlpLn 'LOG cmd'         'Log output of the cmd'
 HlpLn 'LOG :txt'        'Copies txt to the log'
 HlpLn 'LOG'             'View log'
 HlpLn 'PRINT LF|FF'     'Print a Line/Form Feed'
 HlpLn 'PRINT cmd'       'Print output of the cmd'
 HlpLn 'VS'              'Display user screen'
 HlpLn '?'               'Displays this help screen'
 HlpLn
 HlpLn <a_b,'Customization'>
 HlpLn 'SET CMx[[=]adr]' 'Set code marker (x=0..9)'
 HlpLn 'SET DMx[[=]adr]' 'Set data marker (x=0..9)'
 HlpLn 'CMx'             'Go code marker (x=0..9)'
 HlpLn 'DMx'             'Go data marker (x=0..9)'
 HlpLn 'SET PRN[=]LPTx'  'Assign LPTx (x=1,2 or 3) As Printer port'
 HlpLn 'SET PRN[=]nnnn'  'Use I/O Port nnnn (in hex) As Printer port'
 HlpLn 'SET SCR[=]VGA  [colors]' 'Use VGA Display (default)'
 HlpLn 'SET SCR[=]MONO [colors]' 'Use Secondary Mono Display'
 HlpLn 'SET SCR[=]LPTx'  'Switch to Remote Display Using LPTx'
 HlpLn 'SET SCR[=]COMx[:baud]' 'Switch to Remote Display Using COMx'
 HlpLn <>                'example: SET SCR=COM1:115200'
IFDEF   _W95_
 HlpLn 'SET HOTKEY[=][~][^][@]key' 'Define HotKey'
ELSE
 HlpLn 'SET HOTKEY[=]scancode' 'Define HotKey'
ENDIF
 HlpLn 'SET [~][^][@]key[=]cmd' 'Assigns cmd to the key'
 HlpLn <>                'key = One of: F1-F12, UP, DOWN, RIGHT, LEFT'
 HlpLn <>                'HOME, END, PGUP, PGDN, FIVE, PLUS, MINUS'
 HlpLn <>                'CR, TAB, ESC, BKSP, INS, DEL, PRT and SPACE.'
 HlpLn <>                'cmd = One or more commands'
 HlpLn <>                'Example: SET ~F8=T;D.AP;'
 HlpLn
 HlpLn <a_f,d_dup,80,'Ä'>
 HlpLn <a_b,'Definitions'>
 HlpLn 'reg = One the following register names:'
 HlpLn <d_col,4,'EAX, EBX, ECX, EDX, ESI, EDI, EBP, ESP, EIP'>
 HlpLn <d_col,4,'AX, BX, CX, DX, SI, DI, BP, SP, IP'>
 HlpLn <d_col,4,'AL, AH, BL, BH, CL, CH, DL, DH'>
 HlpLn <d_col,4,'CS, DS, ES, FS, GS, SS'>
 HlpLn
 HlpLn 'flag = One of the following EFLAGS bits:'
 HlpLn <d_col,4,'CF, PF, AF, ZF, SF, TF, IF, DF, OF, NT, RF, VM, AC'>
 HlpLn
 HlpLn 'exp = Expressions can be formed by one or more of:'
 HlpLn <d_col,4,'hex',    d_col,18,'Hexadecimal numbers (56BD)'         >
 HlpLn <d_col,4,'.num',   d_col,18,"Decimal numbers (.4509)"            >
 HlpLn <d_col,4,'reg',    d_col,18,'Any of above registers'             >
 HlpLn <d_col,4,'.A',     d_col,18,'offset value of effective address.' >
 HlpLn <d_col,4,'.AS',    d_col,18,'segment value of effective address.'>
 HlpLn <d_col,4,'.D',     d_col,18,'offset value of Data window.'       >
 HlpLn <d_col,4,'.DS',    d_col,18,'segment value of Data window.'      >
 HlpLn <d_col,4,'.C',     d_col,18,'offset value of Code window.'       >
 HlpLn <d_col,4,'.CS',    d_col,18,'segment value of Code window.'      >
 HlpLn <d_col,4,'.W',     d_col,18,'offset value of Watch window.'      >
 HlpLn <d_col,4,'.WS',    d_col,18,'segment value of Watch window.'     >
 HlpLn <d_col,4,'.M',     d_col,18,'offset value of Working memory.'    >
 HlpLn <d_col,4,'.MS',    d_col,18,'segment value of Working memory.'   >
 HlpLn <d_col,4,'.ML',    d_col,18,'size of Working memory (bytes).'    >
 HlpLn
 HlpLn <d_col,4,'Following operators can be used inside expressions:'>
 HlpLn <d_col,4,'Arithmatic:',d_col,18,'+ add  - sub/neg  * mul  / div  % mod'>
 HlpLn <                      d_col,18,'[] contents  () group'>
 HlpLn <d_col,4,'Logical:',   d_col,18,'| or  & and  ^ xor  ~ not'>
 HlpLn <d_col,4,'Boolean:',   d_col,18,'= equal  ',3ch,3eh,' not equal  ',3eh,' greater  ',3ch,' less than'>
 HlpLn <                      d_col,18,3eh,'= greater or equal  ',3ch,'= less or equal  '>
 HlpLn
 HlpLn 'sym = Symbolic name for an address can have following forms:'
 HlpLn <d_col,4,'name',    d_col,18,'Address of a vxd service by name (Get_Cur_VM_Handle)'>
 HlpLn <                   d_col,18,'Exported name of a module (DOS3CALL)'    >
IFDEF   _W95_
 HlpLn <                   d_col,18,'Exported name of a P32 module (THREAD32FIRST)'>
 HlpLn <d_col,4,'mod.name',d_col,18,'Exported name in a 16/32-bit module (KERNEL32.OPENFILE)'>
 HlpLn <d_col,4,'mod.nnnn',d_col,18,'Exported ordinal (hex) in a module (KERNEL32.11A)'>
 HlpLn <d_col,4,'mod.MDB', d_col,18,'Address of the module data base'              >
ELSE
 HlpLn <d_col,4,'mod.name',d_col,18,'Exported name in a module (KERNEL.OPENFILE)'>
 HlpLn <d_col,4,'mod.nnnn',d_col,18,'Exported ordinal (hex) in a module (KERNEL.1d)'>
ENDIF
 HlpLn <d_col,4,'vxd.name',d_col,18,'Vxd service by name (VMM.OPENFILE)'>
 HlpLn <d_col,4,'vxd.nnnn',d_col,18,'A vxd service by number (in hex) (VMM.E0)'    >
IFDEF   _W95_
 HlpLn <d_col,4,'vxd.W32.nnnn',d_col,18,'Win32 service of a vxd by number (in hex) (VWIN32.W32.1B)'>
ENDIF
 HlpLn <d_col,4,'vxd.PM',  d_col,18,'Address of the PM API of the vxd (VTD.PM)'    >
 HlpLn <d_col,4,'vxd.V86', d_col,18,'Address of the V86 API of the vxd (VDD.V86)'  >
 HlpLn <d_col,4,'vxd.CP',  d_col,18,'Address of the Control Procedure (VDD.CP)'    >
 HlpLn <d_col,4,'vxd',     d_col,18,'Same as vxd.CP'                               >
 HlpLn
 HlpLn 'adr = Address expressions are formed by sel/seg and offset parts.'
 HlpLn <d_col,4,'exp1:exp2',d_col,18,'Uses segment or selector address (current mode)'>
 HlpLn <d_col,4,'exp1\exp2',d_col,18,'Protected mode selector and offset address'     >
 HlpLn <d_col,4,'exp1!exp2',d_col,18,'Real/V86 mode segment and offset address'       >
 HlpLn <d_col,4,'exp',      d_col,18,'Uses current segment and mode'                  >
 HlpLn <d_col,4,'sym',      d_col,18,'Symbolic name (DOS3CALL)'                       >
 HlpLn <d_col,4,'If segment part not defined the implied segment will be used (if any)'>
 HlpLn <d_col,4,'If segment undefined current code/data will be assumed.'>
 HlpLn
 HlpLn 'blk = Address and size of a memory block and is defined like:'
 HlpLn <d_col,4,'adr L len',d_col,18,'Start address and length (PD DS:EDX L 20)'>
 HlpLn <d_col,4,'adr end',  d_col,18,'Start address and end (PC CS:2000 207E)'>
 HlpLn
 HlpLn 'str = Data string, can use any combinations of:'
 HlpLn <d_col,4,'exp',      d_col,18,'By value'>
 HlpLn <d_col,4,"'text'|",'"text"', d_col,18,'By ASCII value'>
 HlpLn
 HlpLn 'cond = Count and condition of the break:'
 HlpLn <d_col,4,'N=n',    d_col,18,'Break period (default: N=1)'>
 HlpLn <d_col,4,'exp',    d_col,18,'Break when exp is non-zero (AH',3EH,'3D)'>
 HlpLn <d_col,4,'N=n exp',d_col,18,'Combination of the two (N=5 DS=AF)'>
;HlpLn
;HlpLn <a_b,'Keys'>

PUBPROC Cmd_Help
        push    h_lines                 ;sl_limit
        push    0                       ;sl_index
        call    scrollLines
        db      ' SoftProbe/W V',VER_STR,' (C) 1995  Mehdi Sotoodeh.  '
        db      'All rights reserved.',d_sub
        ; will be called by scrollLines
        ; esi = context
        ; edx = ecx = index
        mov     edi, OFFSET32 _help_
        jecxz   short dspHlp2
        mov     al, d_sub
dspHlp1:mov     cl, 128
        repne   scasb
        dec     edx
        jnz     short dspHlp1
dspHlp2:mov     edx, edi
        call    Printf
        db      d_sub,d_ret
        ret

LCODE_ENDS
END

