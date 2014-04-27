title.  SoftProbe - File system support.

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

SP_FSYS EQU 1
INCLUDE SP_DEFS.INC 
INCLUDE SP_KRNL.INC 
IFDEF   _W95_
INCLUDE IFSMGR.INC
;;INCLUDE IFS.INC
ENDIF

; ---------------------------------------------------------------------------
LDATA_SEG
; ---------------------------------------------------------------------------

IFDEF   _W95_
Prev_FileSystemHook     dd ?
ENDIF

LDATA_ENDS

; ---------------------------------------------------------------------------
LCODE_SEG
; ---------------------------------------------------------------------------

; ***************************************************************************
;
;
; ===========================================================================
IFDEF   _W95_
; Parameters passed thru stack
fsh_StkStruc    struc
  fsh_RetAddr   dd ?    ; Return address
  fsh_pIFSFunc  dd ?    ;
  fsh_Function  dd ?    ; Function code
  fsh_Drive     dd ?    ; 0=A, 1=B,...
  fsh_ResType   dd ?    ;
  fsh_CodePage  dd ?    ;
  fsh_pIOReq    dd ?    ;
fsh_StkStruc    ends

; int _cdecl FSHookProc(pIFSFunc, Function, Drive, ResType, CodePage, pIOReq)

FileSystemApiHook:
        DBGBRK  0
        mov     eax, esp
        ; Save some fields of incomming IO Request, they can be modified.
        xchg    esi, [esp].fsh_pIOReq
;       push    [esi].ir_options
;       push    [esi].ir_pos
;       push    [esi].ir_length
;       push    [esi].ir_locklen
;       push    [esi].ir_flags
;       push    [esi].ir_attr
;       push    [esi].ir_data

        push    esi
        push    [eax].fsh_CodePage
        push    [eax].fsh_ResType
        push    [eax].fsh_Drive
        push    [eax].fsh_Function
        push    [eax].fsh_pIFSFunc
        mov     eax, Prev_FileSystemHook
        call    dword ptr [eax]
        add     esp, 6*4
        ; Save the return value
        xchg    esi, [esp].fsh_pIOReq
        ret
ENDIF

PUBPROC FileSys_Device_Init
        DBGBRK  0
IFDEF   _W95_
        ; Win95 only debug services
        VxDCall IFSMgr_InstallFileSystemApiHook, FileSystemApiHook
        mov     Prev_FileSystemHook, eax
ENDIF
        ret

LCODE_ENDS

; ---------------------------------------------------------------------------
ICODE_SEG
; ---------------------------------------------------------------------------

ICODE_ENDS
END

