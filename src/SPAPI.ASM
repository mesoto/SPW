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
