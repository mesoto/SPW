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

INCLUDE SP_KRNL.INC
INCLUDE SPAPI.INC

.386
; -------------------------------------------------------------------------**
; XportLoader local variables
xl_endofnames   equ [bp-8]              ;word
xl_headerofs    equ [bp-6]              ;dword
xl_filehandle   equ [bp-2]              ;word
xl_retvalue     equ [bp]                ;word
; XportLoader parameters
xl_filename     equ [bp+18]             ;dword
xl_tempbuffer   equ [bp+22]             ;dword (512 bytes)
xl_sortbuffer   equ [bp+26]             ;dword (64k)
xl_savebuffer   equ [bp+30]             ;dword (big enough for symbols)

; -------------------------------------------------------------------------**
; In:   CX = Ordinal number
; Out:  AX (AL) = segment number
;       CX = Offset in the segment
Find_Entry:
        lds     si, dword ptr xl_savebuffer
        ; DS:SI = pointer to the EntryTable
FE_Loop:                                ; for (;;) {
        lodsb                           ;   if ((n = *mp.b++) == 0) {
        and     ax, 0ffh                ;     if (*mp.b)
        jz      short FE_Zero           ;       continue;
        cmp     ax, cx                  ;     else
        jae     FE_Found                ;       return;
        sub     cx, ax                  ;   }
        cmp     [si], ah                ;   if (n >= nOrd) break;
        je      FE_Loop                 ;   nOrd -= n;
        lea     eax, [eax+eax*2]        ;   if (*mp.b == 0)
        cmp     byte ptr [si], 0ffh     ;     continue; // unused
        jne     short @f                ;   if (*mp.b == 0xff)
        shl     ax, 1                   ;     mp.b += 6*n+1;
@@:     add     si, ax                  ;   else
        inc     si                      ;     mp.b += 3*n+1;
        jmp     FE_Loop                 ; }
FE_Zero:cmp     [si], al                ;
        jne     FE_Loop                 ;
        ret

FE_Found:                               ;
        lodsb                           ; if ((n = *mp.b++) == 0)
        cmp     al, 0                   ;   return;
        je      short FE_Done           ;
        dec     cx                      ; nOrd--;

        lea     ecx, [ecx+ecx*2]        ; if (n == 0xff) { // movable segment
        add     si, cx                  ;     mp.b += 6*nOrd;
        cmp     al, 0ffh                ;     e->Flags = *mp.b++;
        jne     short FE_Fixed          ;     mp.w++;            // INT 3FH
        add     si, cx                  ;     e->Seg   = *mp.b++;
        mov     cx, [si+4]              ;     e->Ofs   = *mp.w;
        mov     al, [si+3]              ;     e->Type  = 1;
        ret                             ;     return;
                                        ; }
FE_Fixed:                               ; mp.b += 3*nOrd;
        mov     cx, [si+1]              ; e->Flags = *mp.b++;
        cmp     al, 0feh                ; e->Seg   = n;
        jne     short FE_Done           ; e->Ofs   = *mp.w;
        xor     ax, ax                  ; e->Type  = (n == 0xfe) ?
FE_Done:ret                             ;    2 : 3; // 2=AT segment

; -------------------------------------------------------------------------**
; In:   ECX   = file position
;       AX    = block length
;       DS:SI = memory address
ReadBlkHdr:
        add     ecx, dword ptr xl_headerofs
; -------------------------------------------------------------------------**
; In:   ECX   = file position
;       AX    = block length
;       DS:SI = memory address
ReadBlkAt:
        movzx   edx, cx
        shr     ecx, 16
        push    ax
        mov     ax, 4200h
        mov     bx, xl_filehandle
        int     21h
        pop     cx
ReadBlk:
        mov     dx, si
        mov     ah, 3fh
        int     21h
        jc      short Sym_Failed
        cmp     ax, cx
        jne     short Sym_Failed
        ret

; -------------------------------------------------------------------------**
XportLoader     label far
        DBGBRK  2, 60H
        push    bp                      ;save important registers
        push    esi
        push    edi
        push    ds
        push    0                       ;xl_retvalue (assume failure)
        mov     bp, sp
        sub     sp, 8
        lds     dx, dword ptr xl_filename
        mov     ax, 3d00h
        int     21h
        jc      short Sym_Return
        mov     xl_filehandle, ax
        lds     si, dword ptr xl_tempbuffer
        xor     ecx, ecx                ;file beg
        mov     ax, 40h                 ;size of header
        call    ReadBlkAt
        cmp     word ptr [si], 5a4dh    ;MZ?
        jne     short Sym_Failed
        mov     ecx, dword ptr [si+3ch] ;ecx=file offset
        mov     dword ptr xl_headerofs, ecx
        mov     ax, 100h                ;size of NE/PE header
        call    ReadBlkAt
        cmp     word ptr [si], 454eh    ;NE?
        je      short Load_NE_Exports
IFDEF   _W95_
        cmp     dword ptr [si], 4550h   ;PE?
        je      Load_PE_Exports
ENDIF
        DBGBRK  2, 60H
Sym_Failed:
Sym_Close:
        mov     bx, xl_filehandle
        mov     ah, 3eh
        int     21h
Sym_Return:
        DBGBRK  2, 60H
        mov     sp, bp
        pop     ax                      ;xl_retvalue=length
        pop     ds
        pop     edi
        pop     esi
        pop     bp
        retf    16

Load_NE_Exports:
        DBGBRK  2, 60H
        mov     ax, ds:[si+6]           ;bytes in entry table
        movzx   ecx, word ptr ds:[si+4] ;entry table position
        lds     si, dword ptr xl_savebuffer
        call    ReadBlkHdr

        ; get the module name from the 1st entry in resident name table

        lds     si, dword ptr xl_tempbuffer
        movzx   ecx, word ptr [si+26h]  ;resident name table pos
        mov     ax, word ptr [si+28h]   ;module reference table pos
        sub     ax, cx                  ;size of resident name table
        lds     si, dword ptr xl_sortbuffer
        call    ReadBlkHdr              ;

        xchg    si, ax                  ;append
        les     di, dword ptr xl_tempbuffer
        mov     ecx, dword ptr es:[di+2ch] ;export name position
        mov     ax,   word ptr es:[di+20h] ;export name size
        call    ReadBlkAt               ;

        add     ax, si                  ;buffer for exported names
        xchg    di, ax                  ;end of exported names as scrach
        push    ds
        pop     es
        mov     xl_endofnames, di

Sym_Next:
        mov     bx, 00ffh
        and     bl, [si]                ;LString
        jz      short Sym_Done
        mov     dx, si
        lea     si, [si+bx+3]           ;1 for len, 2 for ord#
        mov     cx, ds:[si-2]           ;ordinal#
        jcxz    short Sym_Next
        push    si
        push    ds
        call    Find_Entry
        ; ax=segment, cx=offset
        pop     ds
        pop     si
        test    ax, ax
        jz      short Sym_Next
        ; keep the list sorted
        shl     eax, 16
        xchg    cx, ax
        ; eax = seg:offset
        mov     bx, xl_endofnames
Sym_Sort1:
        cmp     bx, di
        jae     short Sym_Sort2
        add     bx, 6
        cmp     eax, dword ptr [bx-6]
        jae     short Sym_Sort1
        xchg    eax, dword ptr [bx-6]
        xchg    dx, [bx-6+4]
        jmp     short Sym_Sort1
Sym_Sort2:
        stosd
        xchg    ax, dx
        stosw
        jmp     Sym_Next

Sym_Done:
        DBGBRK  2, 60H
        cmp     di, xl_endofnames
        jz      Sym_Failed

        mov     dx, di
        les     di, dword ptr xl_savebuffer
        push    di
        xor     si, si
        ; 1st entry is the module name
        movzx   ecx, byte ptr [si]
        inc     cx
        xor     ax, ax
        stosw                           ;@00 sh16_Size     - length
        stosw
        stosw                           ;@04 sh16_Type     - 0=P16
        rep     movsb                   ;@06 sh16_ModName  - LString name

        mov     si, xl_endofnames
@@:     movsw                           ;@+0 p16si_Offset  - offset
        movsw                           ;@+2 p16si_Segment - segment number
        mov     bx, di
        inc     di                      ;@+4 p16si_Ordinal
        inc     di
        lodsw
        xchg    si, ax
        mov     cl, [si]
        inc     cx
        rep     movsb                   ;@+6 p16si_Name - LString entry name
        mov     si, [si]                ;ordinal number
        mov     es:[bx], si             ;@+4 p16si_Ordinal
        xchg    ax, si
        cmp     si, dx
        jb      @b

SetSymHeader:
        mov     dword ptr es:[di], ecx  ;length for next module=0
        pop     bx                      ;ptr SYMINFO16_HEADER
        sub     di, bx                  ;length of the module info
        mov     es:[bx+0], di           ;@00 sh16_Size - length of entries
        mov     xl_retvalue, di        ;success=length(>0)
        jmp     Sym_Close

IFDEF   _W95_
Load_PE_Exports:
        DBGBRK  2, 60H
        cmp     [si].pe_NumberOfRvaAndSizes, 1 ; DIR_EXPORT=0
        jb      Sym_Failed
        mov     eax, [si].pe_Directories[DIR_EXPORT].pedd_Size
        test    eax, eax
        jz      Sym_Failed

        movzx   ecx, [si].pe_SizeOfOptionalHdr
        add     ecx, pe_OptHdrMagic
        mov     ax, SIZE PE_SECTION_HEADER_STRUC
        lds     si, dword ptr xl_tempbuffer
        add     si, 100h
        call    ReadBlkHdr

xport_sec_find:
        les     di, dword ptr xl_tempbuffer
        mov     ecx, es:[di].pe_Directories[DIR_EXPORT].pedd_RVA
        sub     ecx, [si].pes_SectionRVA
        cmp     ecx, [si].pes_PhysSize
        jb      short xport_sec_found
        dec     es:[di].pe_NumberOfSections
        jz      Sym_Failed
        mov     cx, SIZE PE_SECTION_HEADER_STRUC
        lea     si, [di+100h]
        call    ReadBlk
        jmp     xport_sec_find

xport_sec_found:
        DBGBRK  2, 60H
        mov     eax, es:[di].pe_Directories[DIR_EXPORT].pedd_Size
        cmp     eax, 0000fff0h          ;is it >64k? (kernel32.dll=4800h)
        jae     Sym_Failed
        add     ecx, [si].pes_PhysAddress ;file offset for export section
        ; Keep in mind that we are writing SYMINFO32_HEADER over the export
        ; section header (1st 6 bytes) which is unsed in our symbolic search.
        lds     si, dword ptr xl_savebuffer
        push    si                      ;to set the header
        call    ReadBlkAt
        ; ax=bytes read
        inc     ax
        and     eax, 0000fffeh          ;make it even
        mov     [si].sh32_Type, SYM_P32
        les     di, dword ptr xl_tempbuffer
        mov     edi, es:[di].pe_Directories[DIR_EXPORT].pedd_RVA
        xchg    edi, eax                ;end of export section
        sub     [si].pex_Name, eax
        sub     [si].pex_AddrOfFunctions, eax
        sub     [si].pex_AddrOfNames, eax
        sub     [si].pex_AddrOfNameOrdinals, eax
        cmp     [si].pex_Name, edi
        jae     Sym_Failed
        cmp     [si].pex_AddrOfFunctions, edi
        jae     Sym_Failed
        cmp     [si].pex_AddrOfNameOrdinals, edi
        jae     Sym_Failed
        mov     ebx, [si].pex_AddrOfNames
        cmp     ebx, edi
        jae     Sym_Failed
        add     bx, si                  ;points to the table of name ptrs
        movzx   ecx, word ptr [si].pex_NumberOfNames
@@:     sub     dword ptr [bx], eax
        cmp     dword ptr [bx], edi
        jae     Sym_Failed
        add     bx, 4
        loop    @b
        mov     [si].sh32_Size, ecx     ;make sure hi-word of size is zero
        push    ds
        pop     es
        jmp     SetSymHeader
ENDIF

