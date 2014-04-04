/***************************************************************************
;*
;* SPCC.C
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

#include "stdio.h"
#include "stdlib.h"
#include "string.h"
#include "malloc.h"
#include "spapi.inc"

long LogRead( char *filename, int append )
{
  long linecount;
  unsigned short n;
  char *p;
  FILE *logfile;

  if( *filename == 0 ) filename = "SPWIN.LOG";

  logfile = fopen( filename, append ? "at" : "wt" );

  if( logfile == NULL )
  {
    printf( "\nCannot create log file %s.", filename );
    return 0;
  }

  spw_logseek( 0 );
  for( linecount = 0; p = spw_logreadline( &n ); linecount++ )
  {
    if( n == 0 ) break;
    fwrite( p, sizeof(char), (size_t)n, logfile );
  }
  fclose( logfile );

  printf( "\n%ld lines copied.", linecount );

  return linecount;
}

void pascal
ModLister( int n, unsigned long len, char *name, unsigned long data )
{
  printf( "\n %4d  %06ld  %s", n, len, name );
}

void SymGetModules( void )
{
  unsigned long BufferSize, BufferUsed;

  printf( "\n  No.   Size   Module Name" );
  printf( "\n ----  ------  ------------" );
  spw_modlist( &BufferSize, &BufferUsed, &ModLister, 0 );
  printf( "\n ----  ------  ------------" );
  printf( "\n %ld bytes out of %ld used.", BufferUsed, BufferSize );
  printf( "\n %ld bytes available.", BufferSize - BufferUsed );
}

int main( int argc, char *argv[] )
{
  unsigned short i, x;
  unsigned char  c, n, v[4];

  printf( "\nSPCC version 1.00  Copyright 1995 Mehdi Sotoodeh."
          "  All rights reserved." );

#if !defined( WIN32 )
  _asm
  {
        pushf
        pushf
        pop     ax
        or      ax, 0f000h
        push    ax
        popf
        pushf
        pop     ax
        and     ax, 0f000h
        mov     x, ax
        popf
  }

  if( x != 0x7000 )
  {
    printf( "\n80386 CPU or Higher needed." );
    return 1;
  }
#endif  // !defined( WIN32 )

  if( !spw_version( v ))
  {
    printf( "\nSoftProbe/W Not Loaded." );
    return 2;
  }

  printf( "\nSoftProbe/W%c%c version %d.%02d Loaded.",
          v[0], v[1], v[2], v[3] );

  if( argc < 2 )
  {
    printf( "\nType: SPCC -? for help." );
    return 1;
  }

  for( i = 1; i < argc; i++ )
  {
    if( argv[i][0] == '-' || argv[i][0] == '/' )
    {
      switch( argv[i][1] )
      {
        case 'e' :
        case 'E' : spw_logclear();
                   printf( "\nLog buffer emptied." );
                   break;
        case 's' : // Save log
        case 'S' : LogRead( &argv[i][2], 0 ); break;
        case 'a' : // Append log
        case 'A' : LogRead( &argv[i][2], 1 ); break;
        case 'd' :
        case 'D' : SymGetModules(); break;
        case 'r' :
        case 'R' : if( spw_modremove( &argv[i][2] ))
                   {
                     printf( "\nModule '%s' unloaded.", &argv[i][2] );
                     break;
                   }
                   printf( "\nModule '%s' not loaded.", &argv[i][2] );
                   break;
        case 'l' :
        case 'L' : if( spw_modload( &argv[i][2] ))
                   {
                     printf( "\nModule '%s' loaded.", &argv[i][2] );
                     break;
                   }
                   printf( "\nCould not load '%s'.", &argv[i][2] );
                   break;
        case '?' :
        case 'h' :
        case 'H' : goto display_syntax;
      }
    }
    else
      goto display_syntax;
  }

  return 0;

display_syntax:
  printf( "\nUSAGE: SPCC [options]"
    "\nWhere options can be any of:"
    "\n  -S[filename]  Copy log buffer to filename (default=SPWIN.LOG)"
    "\n  -A[filename]  Append contents of log buffer to filename"
    "\n  -E            Empty the log buffer"
    "\n  -D            Display loaded modules"
    "\n  -Lfilename    Load exported names of the filename"
    "\n  -Rmodname     Remove module modname from the list"
    "\n  -H            Displays this help screen" );
  return 1;
}
