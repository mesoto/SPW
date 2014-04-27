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

;***************************************************************************
;*
;* SPAPI.ASM
;*
;* Copyright 1995 Mehdi Sotoodeh
;*
;* Description: Provides API for SoftProbe/W
;*
;* $Header$
;*
;* $Log$
;*
;***************************************************************************

INCLUDE SPAPI.INC

public  SPWIN_CALL

.model  small, C
.data

extrn   cmdPkt:byte

.code

;===========================================================================
; void SPWIN_CALL( void );
;===========================================================================
SPWIN_CALL proc
IF DBG GE 2
        int     3
ENDIF
        .386p
        pushad
        lea     ebx, cmdPkt
        movzx   edx, [ebx].spapi_PortAddr
        xor     eax, eax
        SPAPI_Call
        and     ax, cx
        mov     dword ptr cmdPkt.spapi_Signature, eax
        popad
        ret

SPWIN_CALL endp

        end
