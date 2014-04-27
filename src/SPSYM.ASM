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

INCLUDE SPXPO.ASM

; -------------------------------------------------------------------------**
; In:   DS:IO_Buffer = file name (can be used as scratch memory, size=2000h)
;       DS=ES = CS
Sym_Load:
        DBGBRK  2, 60H
        call    message
        db      13,10,'Loading: ',0
        mov     si, offset IO_Buffer
        call    disp_msg

        DBGBRK  2, 60H
        mov     ax, Sym_Save_Seg
        push    ax
        push    0                       ;xl_savebuffer (64k)
        add     ax, 1000h
        push    ax
        push    0                       ;xl_sortbuffer (64k)
        push    cs
        push    offset Sym_Buffer       ;xl_tempbuffer (512 bytes)
        push    cs
        push    offset IO_Buffer        ;xl_filename
        push    cs
        call    near ptr XportLoader
        movzx   ecx, ax                 ;0=error, else length
        jcxz    short xpo_failed

        DBGBRK  2, 60H
        mov     edi, xms_symBuff_beg    ;destination offset
        lea     eax, [edi+ecx+4]
        cmp     eax, xms_symBuff_end    ;end of symbol information
        jae     short sym_not_loaded

        add     xms_symBuff_beg, ecx
        xor     ax, ax
        mov     dx, Sym_Save_Seg
        add     cx, 4                   ;+4 for length of next module
                                        ;length of block to copy to xms
        ; dx:ax seg:off for the source
        ; cx    length in bytes
        ; edi   destination offset
        jmp     Copy_To_Xms

sym_not_loaded:
        call    message
        db      13,10,'Not enough SYM memory allocated.'
        db      13,10,'Press any key to continue.',0
        mov     ah, 8
        int     21h
        ret

xpo_failed:
        call    message
        db      '  FAILED.',0
        ret
