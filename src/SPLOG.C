/***************************************************************************
;*
;* SPLOG.C
;*
;* Copyright 1995 Mehdi Sotoodeh
;*
;* Description:
;*
;* $Header$
;*
;* $Log$
;*
;***************************************************************************/
#include <string.h>
#include <malloc.h>
#include "spapi.inc"

unsigned short  IoPorts[] = { 0x21, 0x40, 0x41, 0x01, 0x42, 0x3bc, 0 };
SPWIN_CMD_BLOCK cmdPkt    = { 0, 0 };
unsigned short  PortFound = 0;
unsigned char   lineLen   = 0;
unsigned long   pktIndex  = 0;
char            Line[512];
int             Status;

extern void SPWIN_CALL( void );
extern unsigned short _far pascal
XportLoader( char _far *syminfo,
             char _far *buff64k,
             char _far *buff512,
             char _far *filename );

int Call_SPWin( unsigned short command )
{
  if( cmdPkt.PortAddr == 0 ) return 0;

  cmdPkt.Command      = command;
  cmdPkt.Signature[2] = 0;
  SPWIN_CALL();
  if( cmdPkt.Signature[3] == 'S' && cmdPkt.Signature[2] == 'P' ) return 1;
  return 0;
}

int spw_connect( void )
{
  int i;
  if( PortFound ) return 1;
  for( i = 0; cmdPkt.PortAddr = IoPorts[ i ]; i++ )
  {
    if( Call_SPWin( SPWCMD_VERSION ))
    {
      PortFound = 1;
      return 1;
    }
  }
  return 0;
}

int pascal spw_version( char *verinfo )
{
  if( !spw_connect() ) return 0;
  if( !Call_SPWin( SPWCMD_VERSION )) return 0;
  verinfo[0] = cmdPkt.Signature[1];
  verinfo[1] = cmdPkt.Signature[0];
  verinfo[2] = cmdPkt.Data[1];
  verinfo[3] = cmdPkt.Data[0];
  return 1;
}

int pascal spw_logclear( void )
{
  if( !spw_connect() ) return 0;
  return Call_SPWin( SPWCMD_EMPTYLOG );
}

unsigned char GetAChar( void )
{
  if( lineLen == 0 )
  {
    Status = 0;
    return 0;
  }
  lineLen--;

  if( pktIndex >= (unsigned short)cmdPkt.Length )
  { // Refill the buffer
    if( cmdPkt.Length != 0x2000 )
    { // No more data left
      Status = 0;
      return 0;
    }
    Call_SPWin( SPWCMD_LOADLOG );
    cmdPkt.Offset  += cmdPkt.Length;
    pktIndex        = 0;
  }
  return cmdPkt.Data[ pktIndex++ ];
}

int pascal spw_logseek( unsigned long offset )
{
  if( !spw_connect() ) return 0;
  // Initialize for log load
  cmdPkt.Offset = offset;
  cmdPkt.Length = 0x2000;
  pktIndex      = 0x2000;          // To force refill
  Status        = 1;

  return 1;
}

// Read upto the end of line
char * pascal spw_logreadline( unsigned short *len )
{
  unsigned short x;
  unsigned char  i, c, n;

  for( x = 0; x < 256; Line[x++] = ' ' );

  lineLen = 1;
  lineLen = GetAChar();       // 1st char is the length

  for( i = 0; lineLen && Status; )
  {
    c = GetAChar();
    switch( c )
    {
      case 0x00 : // s_el
      case 0x05 : // s_wtop
      case 0x07 : // s_row
      case 0x0a : // s_lf
      case 0x0c : // s_window
      case 0x0d : // s_clreol
        // Unexpected byte
        Status = 0;

      case 0x01 : // s_norm
      case 0x02 : // s_bold
      case 0x03 : // s_rvrs
      case 0x04 : // s_fram
        // Ignore the char
        break;

      case 0x06 : // s_col
        i = GetAChar();
        break;

      case 0x09 : // s_tab
        do Line[i++] = ' '; while( i & 7 );
        break;

      case 0x0b : // s_spc
        for( n = GetAChar(); n--; Line[i++] = ' ' );
        break;

      case 0x08 : // s_dup
        n = GetAChar();
        c = GetAChar();
        while( n-- ) Line[i++] = c;
        break;

      case 0x0e : // s_chr
        c = GetAChar();
        if( c < 0x20 ) c = '.';
        Line[i++] = c;
        break;

      default :
        if( c >= 0x20 ) Line[i++] = c;
        break;
    }
  }
  for( x = 256; x; ) if( Line[--x] != ' ' ) break;
  Line[++x] = '\n';
  Line[++x] = '\0';
  *len      = Status ? x : 0;

  return Line;
}

// **************************************************************************
// Module reference routines
// **************************************************************************
typedef  union
{
  unsigned char   *c;
  unsigned short  *w;
  unsigned long   *d;
} MIXEDPTR;

int pascal spw_modlist( unsigned long *BufferSize,
                        unsigned long *BufferUsed,
                        PMODCALLBACK   callback,
                        unsigned long  data )
{
  unsigned long  len;
  unsigned short i, n;
  MIXEDPTR p;
  int      m;

  if( !spw_connect() ) return 0;

  Call_SPWin( SPWCMD_SYMINFO );
  p.c = (char *)&cmdPkt.Data[0];
  *BufferSize = *p.d++;
  for( m = 0; len = *p.d++; m++ )
  {
    n = *p.c++;
    for( i = 0; i < n; i++ ) Line[i] = *p.c++;
    Line[n] = 0;
    callback( m, len, Line, data );
  }
  *BufferUsed = *p.d;
}

int pascal spw_modremove( char *modulename )
{
  unsigned short i, n, m;
  MIXEDPTR p;

  strupr( modulename );
  Call_SPWin( SPWCMD_SYMINFO );
  p.c = (char *)&cmdPkt.Data[0];
  p.d++;
  for( m = 0; *p.d++; m++ )
  {
    n = *p.c++;
    for( i = 0; i < n; i++ ) Line[i] = *p.c++;
    Line[n] = 0;
    strupr( Line );
    if( strcmp( Line, modulename ) == 0 )
    {
      p.c  = (char *)&cmdPkt.Data[0];
      *p.d = (unsigned long)m;
      Call_SPWin( SPWCMD_SYMREMV );
      return 1;
    }
  }
  return 0;
}

int pascal spw_modload( char *filename )
{
  char _far *buffer64k;
  char _far *syminfo;
  unsigned short len, n, m;
  int status;

  buffer64k = (char _far *)halloc( 0x10000L, sizeof(char) );
  syminfo   = (char _far *)halloc( 0x10000L, sizeof(char) );

  len = XportLoader( syminfo, buffer64k, Line, filename );
  if( len )
  {
    // Fill the symbolic buffer from the end because:
    // 1. Insufficient memory will be reported on the first call
    // 2. The incomplete symbolic data will not be included until last part
    for( n = len+4; n > 0; )  // len+4 to include the terminating 0.
    {
      cmdPkt.Length = (n > 0x2000) ? 0x2000 : n;
      n            -= (unsigned short)cmdPkt.Length;
      cmdPkt.Offset = n;
      for( m = 0; m < (unsigned short)cmdPkt.Length; m++ )
        cmdPkt.Data[m] = syminfo[n+m];
      if( !(status  = Call_SPWin( SPWCMD_SYMLOAD ))) break;
    }
  }
  _hfree( buffer64k );
  _hfree( syminfo );
  return ( len == 0 || status == 0 ) ? 0 : 1;
}
