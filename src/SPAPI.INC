;/**************************************************************************
;*
;* SPAPI.INC
;*
;* Copyright 1995 Mehdi Sotoodeh
;*
;* Description: Provides API and definitions for SoftProbe/W
;*
;* $Header$
;*
;* $Log$
;*
;***************************************************************************
; SPAPI interface definitions
;***************************************************************************

SPWIN_CMD_BLOCK  struc              ;*/ typedef struct {                  /*
 spapi_Command   dw 0               ;*/   unsigned short         Command; /*
 spapi_PortAddr  dw 0               ;*/   unsigned short        PortAddr; /*
 spapi_Signature db 4 dup( 0 )      ;*/   unsigned char     Signature[4]; /*
 spapi_Offset    dd 0               ;*/   unsigned long           Offset; /*
 spapi_Length    dd 0               ;*/   unsigned long           Length; /*
 spapi_Data      db 2000h dup(0)    ;*/   unsigned char     Data[0x2000]; /*
SPWIN_CMD_BLOCK  ends               ;*/ } SPWIN_CMD_BLOCK;                /*

; spapi_Command defines
SPWCMD_VERSION  equ 0
SPWCMD_LOADLOG  equ 1
SPWCMD_EMPTYLOG equ 2
SPWCMD_INTGET   equ 3
SPWCMD_INTSET   equ 4
SPWCMD_SYMINFO  equ 5
SPWCMD_SYMLOAD  equ 6
SPWCMD_SYMREMV  equ 7

;==========================================================================
; SoftProbe signature
;==========================================================================
SPAPI_CallRet   equ 1bf9a8ech           ;
;       IN      AL, DX                  ; EC        ==> GP-Fault address
;       TEST    AL,                     ; A8        ==> Here if not found
;       STC                             ; F9        ==> Here if found
;       SBB     eCX, eCX                ; 1B        ==> Signature
;                                       ; C9        ==> Not part of signature
;==========================================================================

; In:   DS:EBX = SPWIN_CMD_BLOCK
;       DX     = Any trapped I/O port
SPAPI_Call macro
        mov     esi, 'Soft'             ;Signature
        mov     edi, 'Prob'             ;Signature
        xor     eax, eax
        dd      SPAPI_CallRet
        db      0c9h                    ;second byte of sbb ecx, ecx
        endm

SPWIN_Device_ID     EQU 2               ; Same as Debug_Device_ID

IFDEF   VMM_Device_ID                   ; VMM.INC included?
IF      DBG     ; -----------------------------------------------------------
SPWDBG_Device_ID    EQU 6002h

Begin_Service_Table SPWDBG
    SPWDBG_Service SPWService_GetVersion, LOCAL
    SPWDBG_Service SPWService_Fault, LOCAL
    SPWDBG_Service SPWService_CheckFault, LOCAL
    SPWDBG_Service SPWService_LoadSyms, LOCAL
End_Service_Table SPWDBG

ELSE            ; -----------------------------------------------------------

Begin_Service_Table SPWIN
    SPWIN_Service SPWService_GetVersion, LOCAL
    SPWIN_Service SPWService_Fault, LOCAL
    SPWIN_Service SPWService_CheckFault, LOCAL
    SPWIN_Service SPWService_LoadSyms, LOCAL
End_Service_Table SPWIN

ENDIF           ; -----------------------------------------------------------
ENDIF

SYMINFO16_HEADER struc
 sh16_Size      dd 0 ; length of the symbolic info (0 if last)
                db 0 ; reserved (0)
 sh16_Type      db 0 ; type of symbolic info (follows)
 sh16_ModName   db 0 ; Lstring modname (P16) | dd export section RVA (P32)
SYMINFO16_HEADER ends

SYMINFO32_HEADER struc
 sh32_Size      dd 0 ; length of the symbolic info (0 if last)
                db 0 ; reserved (0)
 sh32_Type      db 1 ; type of symbolic info (follows)
SYMINFO32_HEADER ends

; NOTE: SYMINFO16_HEADER and SYMINFO32_HEADER strucs should match all the
;       fields upto the sh16_Type/sh32_Type.
if sh16_Size-sh32_Size
.err
endif
if sh16_Type-sh32_Type
.err
endif

; sh16_Type/sh32_Type definitions:
SYM_P16         equ 0
SYM_P32         equ 1

P16_SYMINFO     struc
 p16si_Offset   dw ? ; Offset of the symbol in the p16si_Segment
 p16si_Segment  dw ? ; Segment number of the symbol
 p16si_Ordinal  dw ? ; Symbol ordinal number
 p16si_Name     db ? ; Lstring name
P16_SYMINFO     ends

comment @
;**************************************************************************
; spapi_Command defines
;**************************************************************************/
#define SPWCMD_VERSION  0
#define SPWCMD_LOADLOG  1
#define SPWCMD_EMPTYLOG 2
#define SPWCMD_INTGET   3
#define SPWCMD_INTSET   4
#define SPWCMD_SYMINFO  5
#define SPWCMD_SYMLOAD  6
#define SPWCMD_SYMREMV  7

#ifdef  __cplusplus
extern "C" {
#endif
typedef void (pascal* PMODCALLBACK)( int n,
                                     unsigned long len,
                                     char *name,
                                     unsigned long );

int   pascal spw_version( char *verinfo );
int   pascal spw_logclear( void );
int   pascal spw_logseek( unsigned long offset );
char *pascal spw_logreadline( unsigned short *len );
int   pascal spw_modlist( unsigned long*,
                          unsigned long*,
                          PMODCALLBACK,
                          unsigned long );
int   pascal spw_modremove( char *modulename );
int   pascal spw_modload( char *filename );

#ifdef  __cplusplus
}
#endif
/***************************************************************************
@;*/
