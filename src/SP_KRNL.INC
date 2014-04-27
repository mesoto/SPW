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

; ---------------------------------------------------------------------------
; IN:   ax = handle
; OUT:  ax = selector
; 3.1: handle=selector-1 => selector = handle | 1;
; 3.0: handle=selector+1 => selector = (handle&1) ? handle : handle-1;
; ---------------------------------------------------------------------------

HandleToSelector macro hnd
        or      hnd, 1
        endm

SEGMENT_TABLE_STRUC struc
 sg_filepos     dw 0 ; 00 postion within file (<< ne_align)
 sg_filesize    dw 0 ; 02 size of segment in file (0=64k)
 sg_flags       dw 0 ; 04 flags:
                     ;    0001 0=CODE, 1=DATA
                     ;    0008 iterated segment
                     ;    0010 movable
                     ;
 sg_memsize     dw 0 ; 06 initial size of segment when loaded (0=64k)
 sg_handle      dw 0 ; 08 handle or selector of segment in memory (for
                     ;    fixed segments, a selector; else a handle.
                     ;    Zero means not loaded)
SEGMENT_TABLE_STRUC ends

MODULE_TABLE_STRUC struc
 ne_signature   dw 0 ; 00 NE (454Eh)
 ne_usage       dw 0 ; 02 no of other modules that have refernces here
 ne_penttable   dw 0 ; 04 offset to entry table
 ne_pnextexe    dw 0 ; 06 selector of the next module table (0=last)
 ne_pautodata   dw 0 ; 08 offset to segment table entry for DGROUP
 ne_pfileinfo   dw 0 ; 0A offset of the file information structure:
                     ;    fi_len      db length of the rest of blk
                     ;                db flag
                     ;                dw ?
                     ;    fi_date     dw date of file
                     ;    fi_time     dw time of file
                     ;    fi_pathname db pathname of the file
 ne_flags       dw 0 ; 0C module flags:
                     ;    8000 0=task, 1=DLL
                     ;    0800 self load app
                     ;    0300 uses windows display api services
                     ;    0040 private allocation of memory
                     ;    0010 will use LIM 3.2 EMS
                     ;    0002 each instance will get it own DGROUP
                     ;    0001 each instance shares the DGROUP
 ne_autodata    dw 0 ; 0E logical segment number of DGROUP (1 based)
 ne_heap        dw 0 ; 10 initial local heap size
 ne_stack       dw 0 ; 12 initial stack size
 ne_csip        dd 0 ; 14 starting CS:IP
 ne_sssp        dd 0 ; 18 starting SS:SP
 ne_cseg        dw 0 ; 1C count of segments in segment table
 ne_cmod        dw 0 ; 1E count of entries in module reference table
 ne_cbnrestab   dw 0 ; 20 size of non-resident names table on disk
 ne_segtab      dw 0 ; 22 near * to segment table
 ne_rsrctab     dw 0 ; 24
 ne_restab      dw 0 ; 26
 ne_modtab      dw 0 ; 28
 ne_imptab      dw 0 ; 2A
 ne_nrestab     dd 0 ; 2C
 ne_cmovent     dw 0 ; 30
 ne_align       dw 0 ; 32
 ne_cres        dw 0 ; 34
 ne_exetyp      db 0 ; 36
 ne_flagsother  db 0 ; 37
 ne_gang_start  dw 0 ; 38 start of gangload area  OR offset to return thunks
 ne_gang_length dw 0 ; 3A length of gangload area OR offset to seg ref. bytes
 ne_swaparea    dw 0 ; 3C minimum code swap area size
 ne_expver      dw 0 ; 3E expected windows version num
MODULE_TABLE_STRUC ends

GLOBAL_HEAP_ARENA32_STRUC struc
 gh_next        dd 0 ; 00 offset of next arena (first SENTINEL to itself)
 gh_prev        dd 0 ; 04 offset of prev arena (last SENTINEL to itself)
 gh_base        dd 0 ; 08 linear base address of the block
 gh_bytes       dd 0 ; 0C size of block in bytes
 gh_handle      dw 0 ; 10 handle to this memory block; the bottom two bits
                     ;    marks whether the block is fixed or movable
                     ;    01  fixed (window 3.0: Ring 1)
                     ;    10  movable
                     ;    11  fixed (window 3.1: Ring 3)
 gh_owner       dw 0 ; 12 owner of the block; module handle, task handle
                     ;    PSP, or special:
                     ;    0  0000  free
                     ;    -1 FFFF  sentinel block
                     ;    -3 FFFD  Burgermaster itself (KRNL286 only)
                     ;    -4 FFFC  "NOT THERE" (mapped to hardware)
                     ;    -5 FFFB  "phantom" (defunct EMS type?)
                     ;    -6 FFFA  "wraith" (?)
                     ;    -7 FFF9  "bogus" (temporarily allocated)
 gh_count       db 0 ; 14 lock count for movable blocks
 gh_pglock      db 0 ; 15 number of times paged locked (GlobalPageLock())
 gh_flags       db 0 ; 16 Flags:
                     ;    04   DGROUP
                     ;    08   Discardable
 gh_selcount    db 0 ; 17 no of selectors required (used with huge blocks)
 gh_lruprev     dd 0 ; 18 offset of previous Global Arena in LRU
 gh_lrunext     dd 0 ; 1C offset of next Global Arena in LRU
GLOBAL_HEAP_ARENA32_STRUC ends

BURGERMASTER386_STRUC struc
 bm_heapchk     dw 0 ; 00 non-zero enables heap checking
 bm_freeze      dw 0 ; 02 non-zero prevents heap compaction
 bm_entries     dw 0 ; 04 no of entries in global heap (len of linked list)
 bm_1starena    dd 0 ; 06 offset of 1st global arena
 bm_lastarena   dd 0 ; 0A offset of last global arena
 bm_ncompact    db 0 ; 0E number of heap compactions
 bm_discard     db 0 ; 0F current discard level
                dd 0 ; 10 total bytes discarded so far
                dw 0 ; 14 always 0? (handle table list head)
                dw 0 ; 16 always 0? (free handle table list head)
                dw 0 ; 18 always 0? (handle delta)
                dw 0 ; 1A always 0? (near proc to expand handles)
                dw 0 ; 1C always 0? (handle to statistics table)
                dw 0 ; 1E lock-out access to lru chain from interrupt level
                dd 0 ; 20 offset of first handle in lru chain
                dw 0 ; 24 number of entries in lru chain
                dd 0 ; 26 no of paragraphs to reserve for discardable code
                dd 0 ; 2A fence of discardable code
 bm_freeblks    dw 0 ; 30 number of free blocks
BURGERMASTER386_STRUC ends

THHOOK_STRUC struc
 th_hGlobalHeap        dw 0 ; 00 handle to global heap info struc
                            ;    (BURGERMASTER)
 th_pGlobalHeap        dw 0 ; 02 selector to global heap info struc
                            ;    (BURGERMASTER)
 th_hExeHead           dw 0 ; 04 this is the handle to first module table
                            ;    list. Same as hi-word(GetModuleHandle)
 th_hExeSweep          dw 0 ; 06 unknown
 th_TopPDB             dw 0 ; 08 Kernel's PSP = hi-word(GetCurrentPDB)
 th_HeadPDB            dw 0 ; 0A handle to the 1st PDB
 th_TopSizePDB         dw 0 ; 0C
 th_HeadTDB            dw 0 ; 0E handle to 1st TDB = hi-word(GetCurrentTask)
 th_CurTDB             dw 0 ; 10 handle to the current task's TDB
 th_LoadTDB            dw 0 ; 12 unknown
 th_LockTDB            dw 0 ; 14 handle to locked task, or zero
 th_SelTableLen        dw 0 ; 16 len of selector lookup table
 th_SelTableStart      dd 0 ; 18 offset (within burgermaster) of above
                            ;    (see WINDOWS INTERNALS p113).
               db 04h dup(0); 1C
 th_WinVer             dw 0 ; 20
               db 06h dup(0); 22
 th_hGDI               dw 0 ; 28
 th_hUSER              dw 0 ; 2A
 th_hShell             dw 0 ; 2C
               db 16h dup(0); 2E
 th_InDos              dw 0 ; 44
 th_CurDTA             dd 0 ; 5A
               db 08h dup(0); 5E
 th_DosVer             dw 0 ; 66
               db 0bh dup(0); 68
 th_Debug              db 0 ; 73
THHOOK_STRUC ends

TASK_DB_STRUC struc
 td_next               dw 0          ; 00 selector of next task (0=last)
 td_sssp               dd 0          ; 02 ss:sp when last switched away
 td_nevents            dw 0          ; 06 semaphore (event count)
 td_priority           dw 0          ; 08 priority
 td_unknown1           dw 0          ; 0A
 td_hTask              dw 0          ; 0C always 0 (TDB.INC says next thread)
 td_unknown2           dw 3 dup(0)   ; 0E always 0
 td_fpcw               dw 0          ; 14 80x87 control word FLDCW/FSTCW
 td_flags              dw 0          ; 16 TDB.INC says task flags:
                                     ;    1=WINOLDAPP
                                     ;    8=OS2APP
                                     ;    10=WIN32
 td_errmode            dw 0          ; 18
 td_expWinVer          dw 0          ; 1A
 td_hInstance          dw 0          ; 1C instance handle for task
 td_hModule            dw 0          ; 1E module handle for task
 td_hQueue             dw 0          ; 20 selector of message queue
 td_hParent            dw 0          ; 22 selector of TDB of parent task
 td_SetSigHandlerFlag  dw 0          ; 24
 td_SetSigHandlerProc  dd 0          ; 26
 td_signalProc         dd 0          ; 2A task signal procedure
 td_gdiscardProc       dd 0          ; 2E global discard notification proc
 td_int0Proc           dd 0          ; 32 int 0 handler
 td_int2Proc           dd 0          ; 36 int 2 handler
 td_int4Proc           dd 0          ; 3A int 4 handler
 td_int6Proc           dd 0          ; 3E int 6 handler
 td_int7Proc           dd 0          ; 42 int 7 handler
 td_int3EProc          dd 0          ; 46 int 3e handler
 td_int75Proc          dd 0          ; 4A int 75 handler
 td_Comptability       dd 0          ; 4E result of GetProfileInt( modname,
                                     ;    "Compatibility", 0) (3.1)
 td_TIB_Selctor        dw 0          ; 52 value of the FS selector (_W95_)
                                     ;    LinAddr(FS)-10h => ThreadDB
 td_pRing3TCB          dd 0          ; 54 ptr a Ring3 TCB (_W95_)
                       db 08h dup(0) ; 58
 td_pdb                dw 0          ; 60 selector to PSP (PDB)
 td_dta                dd 0          ; 62 ptr disk transfer area
 td_currDrive          db 0          ; 66 current drive +80h (A=80..)
 td_currDir            db 43h dup(0) ; 67 current path for task
 td_directedYieldHTask dw 0          ; AA hTask of task that is being
                                     ;    DirectedYield()'ed to
 td_libraryListSeg     dw 0          ; AC selector for segment containing
                                     ;    refernced DLL list. Exists only
                                     ;    before InitTask has been called
 td_libraryListOffset  dw 0          ; AE offset of the DLL list in the
                                     ;    segment above
 td_codeAlias          dw 0          ; B0 code segment alias for this TDB
 td_moreProcThunks     dw 0          ; B2
 td_procThunksSig      dw 0          ; B4 'PT'
 td_unknown6           dw 0          ; B6
 td_nextAvailableThunk dw 0          ; B8
 td_procThunkData      db 38h dup(0) ; BA
 td_moduleName         db 8 dup(0)   ; F2 module name for task
 td_signature          dw 0          ; FA 'TD' (4454h)
                       dw 0          ; FC
                       dw 0          ; FE
 td_psp                db ?          ; 100 PSP for task
TASK_DB_STRUC ends

; ---------------------------------------------------------------------------
; WIN32 definitions
; ---------------------------------------------------------------------------
PE_IMAGE_DATA_DIRECTORY struc
  pedd_RVA              dd ?
  pedd_Size             dd ?
PE_IMAGE_DATA_DIRECTORY ends

DIR_EXPORT              equ 8*0  ; Export Directory
DIR_IMPORT              equ 8*1  ; Import Directory
DIR_RESOURCE            equ 8*2  ; Resource Directory
DIR_EXCEPTION           equ 8*3  ; Exception Directory
DIR_SECURITY            equ 8*4  ; Security Directory
DIR_BASERELOC           equ 8*5  ; Base Relocation Table
DIR_DEBUG               equ 8*6  ; Debug Directory
DIR_COPYRIGHT           equ 8*7  ; Description String
DIR_GLOBALPTR           equ 8*8  ; Machine Value (MIPS GP)
DIR_TLS                 equ 8*9  ; TLS Directory
DIR_LOAD_CONFIG         equ 8*10 ; Load Configuration Directory
NUM_DIRECTORY_ENTRIES   equ 16   ; Total in a PE header

PE_FILE_HEADER_STRUC    struc
 pe_Magic               dd 4550h ; 00 PE
 pe_Machine             dw 014ch ; 04 i386=14c
 pe_NumberOfSections    dw ?     ; 06
 pe_TimeDateStamp       dd ?     ; 08
 pe_PtrSymbolTable      dd ?     ; 0C
 pe_NumberOfSymbols     dd ?     ; 10
 pe_SizeOfOptionalHdr   dw ?     ; 14
 pe_Characteristics     dw ?     ; 16

 ; Start of the Optional Header

 pe_OptHdrMagic         dw 010Bh ; 18 010Bh
 pe_MajLinkVer          db ?     ; 1A major linker version
 pe_MinLinkVer          db ?     ; 1B minor linker version
 pe_SizeOfCode          dd ?     ; 1C
 pe_SizeOfInitData      dd ?     ; 20
 pe_SizeOfUninitData    dd ?     ; 24
 pe_AddrOfEntryPoint    dd ?     ; 28
 pe_BaseOfCode          dd ?     ; 2C
 pe_BaseOfData          dd ?     ; 30

 ; NT additional fields.

 pe_ImageBase           dd ?     ; 34
 pe_SectionAlignment    dd ?     ; 38
 pe_FileAlignment       dd ?     ; 3C
 pe_MajOsVer            dw ?     ; 40
 pe_MinOsVer            dw ?     ; 42
 pe_MajImageVer         dw ?     ; 44
 pe_MinImageVer         dw ?     ; 46
 pe_MajSubSysVer        dw ?     ; 48
 pe_MinSubSysVer        dw ?     ; 4A
                        dd ?     ; 4C
 pe_SizeOfImage         dd ?     ; 50
 pe_SizeOfHeaders       dd ?     ; 54
 pe_CheckSum            dd ?     ; 58
 pe_Subsystem           dw ?     ; 5C
 pe_DllCharacteristics  dw ?     ; 5E
 pe_SizeOfStackReserve  dd ?     ; 60
 pe_SizeOfStackCommit   dd ?     ; 64
 pe_SizeOfHeapReserve   dd ?     ; 68
 pe_SizeOfHeapCommit    dd ?     ; 6C
 pe_LoaderFlags         dd ?     ; 70
 pe_NumberOfRvaAndSizes dd ?     ; 74 = PE_IMAGE_NUMOF_DIR_ENTRIES
 pe_Directories         dd ?     ; 78 of type PE_IMAGE_DATA_DIRECTORY
PE_FILE_HEADER_STRUC    ends

PE_SECTION_HEADER_STRUC struc
 pes_Name               db 8 dup(0) ; 00
 pes_VirtualSize        dd ?        ; 08
 pes_SectionRVA         dd ?        ; 0C
 pes_PhysSize           dd ?        ; 10
 pes_PhysAddress        dd ?        ; 14
 pes_PtrToRelocations   dd ?        ; 18
 pes_PtrToLinenumbers   dd ?        ; 1C
 pes_NumOfRelocations   dw ?        ; 20
 pes_NumOfLinenumbers   dw ?        ; 22
 pes_Characteristics    dd ?        ; 24
PE_SECTION_HEADER_STRUC ends

PE_EXPORT_DIR_STRUC struc
 pex_Characteristics    dd ? ; 00
 pex_TimeDateStamp      dd ? ; 04
 pex_MajorVersion       dw ? ; 08
 pex_MinorVersion       dw ? ; 0A
 pex_Name               dd ? ; 0C
 pex_OrdinalBase        dd ? ; 10
 pex_NumberOfFunctions  dd ? ; 14
 pex_NumberOfNames      dd ? ; 18
 pex_AddrOfFunctions    dd ? ; 1C ptr ULONG  * pex_NumberOfFunctions
 pex_AddrOfNames        dd ? ; 20 ptr ULONG  * pex_NumberOfNames
 pex_AddrOfNameOrdinals dd ? ; 24 ptr USHORT * pex_NumberOfNames
PE_EXPORT_DIR_STRUC ends

IFDEF _W95_
; ---------------------------------------------------------------------------
; Following structure has been located just after VWIN32 DDB.
; ---------------------------------------------------------------------------
VWIN32_STATE_INFO_STRUC struc
 vw32_VmmPSPSegment     dw ? ; 00 value returned by Get_PSP_Segment
 vw32_VmmPSPSelector    dw ? ; 02 PM Selector to the above segment
 vw32_CurThread         dd ? ; 04 current R3TCB
 vw32_CurProcess        dd ? ; 08 returned by VWIN32_GetCurrentProcessHandle
 vw32_pTDBX             dd ? ; 0C
                        dd ? ; 10 000211ec ???
 vw32_CurContext        dd ? ; 14 current memory context?
 vw32_R0TcbTdbxOffset   dd ? ; 18 =8C the offset of pTDBX in RING0_TCB_STRUC
                             ;    VWIN32 gets this value from VMM on the 1st
                             ;    call it makes to _AllocateThreadDataSlot
                        dd ? ; 1C c2400fc0 ???
 vw32_pTDBX2            dd ? ; 20 another TDBX (usually same as 0C)
 vw32_pCriticalSection  dd ? ; 24
 vw32_pCriticalSection2 dd ? ; 28
 vw32_xxxProcedure      dd ? ; 2C points to kernel32.text
 vw32_xxxProcedure2     dd ? ; 30 points to kernel32.text
 vw32_PMInt30Offset     dw ? ; 34 offset of 3B:3E0
 vw32_PMInt30Selector   dw ? ; 36 =3Bh
 vw32_xxxProcedure3     dd ? ; 38 points to kernel32.text
 vw32_R0TCB             dd ? ; 3C points to a Ring0 TCB
 vw32_R0TCB2            dd ? ; 40 points to a Ring0 TCB
 vw32_xxxProcedure4     dd ? ; 44 points to kernel32.text
                        dd ? ; 48 0
 vw32_somePtr           dd ? ; 4C points to next dword
VWIN32_STATE_INFO_STRUC ends

ENDIF

; Kernel32 objects
K32OBJ_SEMAPHORE         equ 01h
K32OBJ_EVENT             equ 02h
K32OBJ_MUTEX             equ 03h
K32OBJ_CRITICAL_SECTION  equ 04h
K32OBJ_PROCESS           equ 05h
K32OBJ_THREAD            equ 06h
K32OBJ_FILE              equ 07h
K32OBJ_CHANGE            equ 08h
K32OBJ_CONSOLE           equ 09h
K32OBJ_SCREEN_BUFFER     equ 0Ah
K32OBJ_MEM_MAPPED_FILE   equ 0Bh
K32OBJ_SERIAL            equ 0Ch
K32OBJ_DEVICE_IOCTL      equ 0Dh
K32OBJ_PIPE              equ 0Eh
K32OBJ_MAILSLOT          equ 0Fh
K32OBJ_TOOLHELP_SNAPSHOT equ 10h
K32OBJ_SOCKET            equ 11h

ADDRESS_CONTEXT_STRUC struc
 ac_PageTablePtr      dd ? ; 00
 ac_NumTables         dd ? ; 04 number of tables
 ac_OtherInfo         dd ? ; 08 ptr OTHER_ADDR_CNTX_STRUC
 ac_NextAddrCntx      dd ? ; 0c next (loop, last points to first)
 ac_Signature         dd ? ; 10 0x44434443 = 'CDCD'
ADDRESS_CONTEXT_STRUC ends

OTHER_ADDR_CNTX_STRUC struc
 oac_MinAddr          dd ? ; 00 min address >> 12
 oac_MaxAddr          dd ? ; 04 max address >> 12
                      dd ? ; 08 ?
                      dd ? ; 0c ?
 oac_Mutex            dd ? ; 10 Mutex handle
OTHER_ADDR_CNTX_STRUC ends

IFDEF _W95_
WIN32_TDB_STRUC struc
                dd ? ; 00 00040000         ?
 td3_PE_Header  dd ? ; 04 ptr PE_Header
                dd ? ; 08 FFFFFFFF         ?
 td3_FilePath   dd ? ; 0C ptr filepath     C:\WIN95\SYSTEM\KERNEL32.DLL
 td3_ModuleName dd ? ; 10 ptr filename     KERNEL32.DLL
 td3_FPathLen   dw ? ; 14 001C             length of td3_FilePath
 td3_MNameLen   dw ? ; 16 000C             length of td3_ModuleName
                dd ? ; 18 FFFFFFFF         ?
 td3_NSections  dd ? ; 1C 00000006         Number of sections
                dd ? ; 20 00000000         ?
 td3_DefBaseAdr dd ? ; 24 def base of code (MZ header if base @80000000+)
 td3_Mod16DB    dw ? ; 28 019f             Module 16 databse
 td3_Usage      dw ? ; 2A 0007             Usage
 td3_ModRef     dd ? ; 2C                  ptr WIN32_MODREF_STRUC
                ; ....
                ; NE image of the hModule of this task follows here
                ; Offset = base( hModule )
                ; dw    454eh           ; NE image of the hModule of this task
                ; dd    ptr MZ_Header   ; +40 base of code
                ; dd    ptr MZ_Header   ; +44 base of code
WIN32_TDB_STRUC ends
ELSE
WIN32_TDB_STRUC struc
                dd ? ; 00 00040000         ?
 td3_PE_Header  dd ? ; 04 ptr PE_Header
                dd ? ; 08 FFFFFFFF         ?
 td3_FilePath   dd ? ; 0C ptr filepath     C:\WIN95\SYSTEM\KERNEL32.DLL
 td3_ModuleName dd ? ; 10 ptr filename     KERNEL32.DLL
                dd ? ; 14 000C001C         ?
                dd ? ; 18 FFFFFFFF         ?
                dd ? ; 1C 00000006         ?
                dd ? ; 20 00000000         ?
 td3_DefBaseAdr dd ? ; 24 def base of code (MZ header if base @80000000+)
 td3_Mod16DB    dw ? ; 28 019f             Module 16 databse
                dw ? ; 2A 0007             ?
                ; ....
                ; NE image of the hModule of this task follows here
                ; Offset = base( hModule )
                ; dw    454eh           ; NE image of the hModule of this task
                ; dd    ptr MZ_Header   ; +40 base of code
                ; dd    ptr MZ_Header   ; +44 base of code
WIN32_TDB_STRUC ends
ENDIF

WIN32_MODREF_STRUC struc
 mr_NextModref     dd ? ; 00 ptr next or 0 for end
                   dd ? ; 04
 mr_NextInstModref dd ? ; 08 modref of next use or 0 for end (cnt=td3_Usage)
                   dd ? ; 0c
 mr_ModTableIndex  dw ? ; 10
                   dw ? ; 12
                   dd ? ; 14
 mr_PtrProcessDB   dd ? ; 18 ptr WIN32_PROCESS_DATABASE struc
                   dd ? ; 1c
                   dd ? ; 20
                   dd ? ; 24
WIN32_MODREF_STRUC ends

WIN32_PROCESS_DATABASE   struc
 pdb32_Type              dd ? ; 00 K32OBJ_PROCESS = 5
 pdb32_RefCount          dd ? ; 04 number of references
                         dd ? ; 08 0?
 pdb32_SomeEvent         dd ? ; 0c
 pdb32_ExitCode          dd ? ; 10 returned by GetExitCodeProcess (103=alive)
                         dd ? ; 14 0?
 pdb32_ProcessHeap       dd ? ; 18 returned by GetProcessHeap
 pdb32_MemContext        dd ? ; 1c
 pdb32_Flags             dd ? ; 20
 pdb32_PSPLinAddr        dd ? ; 24 inear address of PSP?
 pdb32_PSPSelector       dw ? ; 28
 pdb32_ModTableIndex     dw ? ; 2a Index to the Module32_List
 pdb32_NumThreads        dw ? ; 2c No. of threads belonging to this ps
 pdb32_NotTermThreads    dw ? ; 2e always same as pdb32_NumThreads
                         dw ? ; 30 0?
 pdb32_cRing0Threads     dw ? ; 32 usually same as pdb32_NumThreads
 pdb32_HeapHandle        dd ? ; 34
 pdb32_TDB16             dd ? ; 38 win16 TDB
 pdb32_MemMapFiles       dd ? ; 3c ptr to head (dd base, dd next or 0)
 pdb32_PtrEnvDB          dd ? ; 40 cur dir, env, cmd line,...
 pdb32_PtrHandleTable    dd ? ; 44
 pdb32_PtrParentPdb32    dd ? ; 48 usually EXPLORER
 pdb32_PtrModRefList     dd ? ; 4c list of modules for this process
 pdb32_PtrThreadList     dd ? ; 50 listmgr style list
 pdb32_DebuggeeCtxBlk    dd ? ; 54 debuggee context block
 pdb32_LocalHeapFree     dd ? ; 58 head of the list
 pdb32_InitialRing0ID    dd ? ; 5c always 0
 pdb32_CritSec     dd 6 dup(?); 60 the actual structure not a pointer (obj4)
                         dd ? ; 78
                         dd ? ; 7c
 pdb32_pConsole          dd ? ; 80
 pdb32_tlsUseBits1       dd ? ; 84 Represents TLS indices 0 - 31
 pdb32_tlsUseBits2       dd ? ; 88 Represents TLS indices 32 - 63
 pdb32_ProcessDword      dd ? ; 8c returned by GetProcessDword
 pdb32_PtrProcessGroup   dd ? ; 90 0 or ptr master ps in a group
 pdb32_PtrExeModRefList  dd ? ; 94
 pdb32_TopExcFilter      dd ? ; 98 top exception filter
 pdb32_BasePriority      dd ? ; 9c 4=idle, 8=normal, 13=high, 18=realtime
 pdb32_HeapOwnList       dd ? ; a0
 pdb32_HeapHandleBlkList dd ? ; a4
 pdb32_SomeHeapPtr       dd ? ; a8
 pdb32_pConsoleProvider  dd ? ; ac
 pdb32_EnvSelector       dw ? ; b0
 pdb32_ErrorMode         dw ? ; b2
                         dd ? ; b4
WIN32_PROCESS_DATABASE   ends

; pdb32_Flags definitions: (page 107, win95 sys prog secrets)
PS32_fDebugSingle        equ 00000001h
PS32_fCreateProcessEvent equ 00000002h
PS32_fExitProcessEvent   equ 00000004h
PS32_fWin16Process       equ 00000008h
PS32_fDosProcess         equ 00000010h
PS32_fConsoleProcess     equ 00000020h
PS32_fFileApisAreOem     equ 00000040h
PS32_fNukeProcess        equ 00000080h
PS32_fServiceProcess     equ 00000100h
PS32_fLoginScriptHack    equ 00000800h

WIN32_ENVR_DATABASE      struc
 env32_pEnvironment      dd ? ; 00 points to dos like env strings
                         dd ? ; 04
 env32_pCmdLine          dd ? ; 08 command line passed to CreateProcess
 env32_pCurDir           dd ? ; 0c current directory
 env32_pStartupInfo      dd ? ; 10 ptr STARTUPINFOA (defined in WINBASE.H)
 env32_hStdIn            dd ? ; 14
 env32_hStdOut           dd ? ; 18
 env32_hStdErr           dd ? ; 1c
                         dd ? ; 20 1?
 env32_InheritConsole    dd ? ; 24 see CreateProcess
 env32_BreakType         dd ? ; 28
 env32_BreakSem          dd ? ; 2c
 env32_BreakEvent        dd ? ; 30
 env32_BreakThreadID     dd ? ; 34
 env32_BreakHandlers     dd ? ; 38
WIN32_ENVR_DATABASE      ends

; Partialy defined in VMM.INC
RING0_TCB_STRUC          STRUC
 R0TCB_Flags             dd ? ; 00
 R0TCB_Reserved1         dd ? ; 04
 R0TCB_Reserved2         dd ? ; 08
 R0TCB_Signature         dd ? ; 0C SCHED_OBJ_ID_THREAD = 'THCB'
 R0TCB_ClientPtr         dd ? ; 10
 R0TCB_VMHandle          dd ? ; 14
 R0TCB_ThreadId          dw ? ; 18
 R0TCB_PMLockOrigSS      dw ? ; 1A
 R0TCB_PMLockOrigESP     dd ? ; 1C
 R0TCB_PMLockOrigEIP     dd ? ; 20
 R0TCB_PMLockStackCount  dd ? ; 24
 R0TCB_PMLockOrigCS      dw ? ; 28
 R0TCB_PMPSPSelector     dw ? ; 2A
 R0TCB_ThreadType        dd ? ; 2C
 R0TCB_pad1              dw ? ; 30
 R0TCB_pad2              db ? ; 32
 R0TCB_extErrLocus       db ? ; 33
 R0TCB_extErr            dw ? ; 34
 R0TCB_extErrAction      db ? ; 36
 R0TCB_extErrClass       db ? ; 37
 R0TCB_extErrPtr         dd ? ; 38
 ; Undefined in VMM.INC from this point on.
                         dd ? ; 3C
 R0TCB_nextTcb           dd ? ; 40
                         dd ? ; 44
                         dd ? ; 48
 R0TCB_pClientReg        dd ? ; 4c points to the client register struc at
                              ;    ring0 transition time
 ; ....
RING0_TCB_STRUC          ENDS

; This is semi-documented in the NTDDK.H file from the NT DDK
WIN32_TIB_STRUC         struc
 tib_pvExcept           dd ? ; 00 Head of exception record list
 tib_TopOfStack         dd ? ; 04 Top of user stack
 tib_StackLow           dd ? ; 08 Base of user stack
 tib_W16TDB             dw ? ; 0C TDB
 tib_StackSelector16    dw ? ; 0E SS selector used for thunking to 16 bits
 tib_SelmanList         dd ? ; 10
 tib_UserPointer        dd ? ; 14 Available for application use
 tib_pTIB               dd ? ; 18 Linear address of TIB structure
 tib_TIBFlags           dw ? ; 1C Bit 0 if set, loader sets TF before jumping
                             ;    to the start address to activate debuggers.
 tib_Win16MutexCount    dw ? ; 1E
 tib_DebugContext       dd ? ; 20
 tib_pCurrentPriority   dd ? ; 24
 tib_MessageQueue       dd ? ; 28 Message Queue selector
 tib_pTLSArray          dd ? ; 2C Thread Local Storage array
WIN32_TIB_STRUC         ends

TDBX_STRUC              struc
 tdbx_ptdb              dd ? ; 00 PTHREAD_DATABASE
 tdbx_ppdb              dd ? ; 04 PPROCESDS_DATABASE
 tdbx_ContextHandle     dd ? ; 08
                        dd ? ; 0C
 tdbx_TimeOutHandle     dd ? ; 10
 tdbx_WakeParam         dd ? ; 14
 tdbx_BlockHandle       dd ? ; 18
 tdbx_BlockState        dd ? ; 1C
 tdbx_SuspendCount      dd ? ; 20
 tdbx_SuspendHandle     dd ? ; 24
 tdbx_MustCompleteCount dd ? ; 28
 tdbx_WaitExFlags       dd ? ; 2C
                             ; 00000001 - WAITEXBIT
                             ; 00000002 - WAITACKBIT
                             ; 00000004 - SUSPEND_APC_PENDING
                             ; 00000008 - SUSPEND_TERMINATED
                             ; 00000010 - BLOCKED_FOR_TERMINATION
                             ; 00000020 - EMULATE_NPX
                             ; 00000040 - WIN32_NPX
                             ; 00000080 - EXTENDED_HANDLES
                             ; 00000100 - FROZEN
                             ; 00000200 - DONT_FREEZE
                             ; 00000400 - DONT_UNFREEZE
                             ; 00000800 - DONT_TRACE
                             ; 00001000 - STOP_TRACING
                             ; 00002000 - WAITING_FOR_CRST_SAFE
                             ; 00004000 - CRST_SAFE
                             ; 00040000 - BLOCK_TERMINATE_APC
 tdbx_SyncWaitCount     dd ? ; 30
 tdbx_QueuedSyncFuncs   dd ? ; 34
 tdbx_UserAPCList       dd ? ; 38
 tdbx_KernAPCList       dd ? ; 3C
 tdbx_pPMPSPSelector    dd ? ; 40
 tdbx_BlockedOnID       dd ? ; 44
                  dd 7 dup(?); 48
 tdbx_TraceRefData      dd ? ; 64
 tdbx_TraceCallBack     dd ? ; 68
 tdbx_TraceEventHandle  dd ? ; 6C
 tdbx_TraceOutLastCS    dw ? ; 70
 tdbx_K16TDB            dw ? ; 72
 tdbx_K16PDB            dw ? ; 74
 tdbx_DosPDBSeg         dw ? ; 76
 tdbx_ExceptionCount    dw ? ; 78
TDBX_STRUC              ends

THREAD_DATABASE_STRUC   struc
 thdb_Type              dd ? ; 00 K32OBJ_THREAD (6)
 thdb_cReference        dd ? ; 04
 thdb_pProcess          dd ? ; 08
 thdb_someEvent         dd ? ; 0C An event object (What's it used for???)
 thdb_TIB db SIZE WIN32_TIB_STRUC dup (?) ; 10
                             ;    This field through field 3CH is a TIB
                             ;    structure (see TIB.H)
                             ;    FS selector points here
 thdb_pProcess2         dd ? ; 40 Another copy of the thread's process???
 thdb_Flags             dd ? ; 44
                             ; 00000001 - fCreateThreadEvent
                             ; 00000002 - fCancelExceptionAbort
                             ; 00000004 - fOnTempStack
                             ; 00000008 - fGrowableStack
                             ; 00000010 - fDelaySingleStep
                             ; 00000020 - fOpenExeAsImmovableFile
                             ; 00000040 - fCreateSuspended
                             ; 00000080 - fStackOverflow
                             ; 00000100 - fNestedCleanAPCs
                             ; 00000200 - fWasOemNowAnsi
                             ; 00000400 - fOKToSetThreadOem

 thdb_TerminationStat   dd ? ; 48 Returned by GetExitCodeThread
 thdb_TIBSelector       dw ? ; 4C
 thdb_EmulatorSelector  dw ? ; 4E
 thdb_cHandles          dd ? ; 50
 thdb_WaitNodeList      dd ? ; 54
                        dd ? ; 58
 thdb_Ring0Thread       dd ? ; 5C
 thdb_pTDBX             dd ? ; 60
 thdb_StackBase         dd ? ; 64
 thdb_TerminationStack  dd ? ; 68
 thdb_EmulatorData      dd ? ; 6C
 thdb_GetLastErrorCode  dd ? ; 70
 thdb_DebuggerCB        dd ? ; 74
 thdb_DebuggerThread    dd ? ; 78
 thdb_ThreadContext     dd ? ; 7C register context defined in WINNT.H
 thdb_Except16List      dd ? ; 80
 thdb_ThunkConnect      dd ? ; 84
 thdb_NegStackBase      dd ? ; 88
 thdb_CurrentSS         dd ? ; 8C
 thdb_SSTable           dd ? ; 90
 thdb_ThunkSS16         dd ? ; 94
 thdb_TLSArray   dd 64 dup(?); 98
 thdb_DeltaPriority     dd ? ; 198

; The retail version breaks off somewhere around here.
; All the remaining fields are most likely only in the debug version

                  dd 7 dup(?); 19C
 thdb_pCreateData16     dd ? ; 1B8
 thdb_APISuspendCount   dd ? ; 1BC # of times SuspendThread has been called
                        dd ? ; 1C0
 thdb_WOWChain          dd ? ; 1C4
 thdb_wSSBig            dw ? ; 1C8
                        dw ? ; 1CA
 thdb_lp16SwitchRec     dd ? ; 1CC
                  dd 6 dup(?); 1D0
 thdb_pSomeCritSect1    dd ? ; 1E8
 thdb_pWin16Mutex       dd ? ; 1EC
 thdb_pWin32Mutex       dd ? ; 1F0
 thdb_pSomeCritSect2    dd ? ; 1F4
                        dd ? ; 1F8
 thdb_ripString         dd ? ; 1FC
 thdb_LastTlsSetValueEIP dd 64 dup(?) ; 200 (parallel to TlsArray,
                             ; contains EIP where TLS value was last set from)
THREAD_DATABASE_STRUC   ends

