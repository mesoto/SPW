public  XportLoader

DBGBRK  macro   L, i
IF DBG GE L
        int     3
ENDIF
endm

.model  small, C
.data

.code

INCLUDE SPXPO.ASM

        end
