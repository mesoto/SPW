/**************************************************************************
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
;*************************************************************************/

/****************************************************************************
 *  01-29-95 MEHDI  Initial release.
 *
 *  SWITCHES USED:
 *      DBG
 *
 ****************************************************************************/
#include <stdio.h>
#include <string.h>
#include <fcntl.h>

char VxdName[50];
char VxdService[60];

FILE *f1;
FILE *f2;
char Buffer[512];
unsigned short VxdId, len;

/***************************************************************************
;*
;*                     EQUATES FOR REQUIRED DEVICES
;*
 ***************************************************************************/

struct {
    char *name;
    short id;
} KnownVxds[] = {
    {"VMM"      , 0x0001},
    {"DEBUG"    , 0x0002},
    {"VPICD"    , 0x0003},
    {"VDMAD"    , 0x0004},
    {"VTD"      , 0x0005},
    {"V86MMGR"  , 0x0006},
    {"PAGESWAP" , 0x0007},
    {"PARITY"   , 0x0008},
    {"REBOOT"   , 0x0009},
    {"VDD"      , 0x000A},
    {"VSD"      , 0x000B},
    {"VMD"      , 0x000C},
    {"VMOUSE"   , 0x000C},
    {"VKD"      , 0x000D},
    {"VCD"      , 0x000E},
    {"VPD"      , 0x000F},
    {"BLOCKDEV" , 0x0010},
    {"IOS"      , 0x0010},
    {"VMCPD"    , 0x0011},
    {"EBIOS"    , 0x0012},
    {"BIOSXLAT" , 0x0013},
    {"VNETBIOS" , 0x0014},
    {"DOSMGR"   , 0x0015},
    {"WINLOAD"  , 0x0016},
    {"SHELL"    , 0x0017},
    {"VMPOLL"   , 0x0018},
    {"VPROD"    , 0x0019},
    {"DOSNET"   , 0x001A},
    {"VFD"      , 0x001B},
    {"VDD2"     , 0x001C},
    {"WINDEBUG" , 0x001D},
    {"TSRLOAD"  , 0x001E},
    {"BIOSHOOK" , 0x001F},
    {"INT13"    , 0x0020},
    {"PAGEFILE" , 0x0021},
    {"SCSI"     , 0x0022},
    {"MCA_POS"  , 0x0023},
    {"SCSIFD"   , 0x0024},
    {"VPEND"    , 0x0025},
    {"APM"      , 0x0026},
    {"VPOWERD"  , 0x0026},
    {"VXDLDR"   , 0x0027},
    {"NDIS"     , 0x0028},
    {"BIOS_EXT" , 0x0029},
    {"VWIN32"   , 0x002A},
    {"VCOMM"    , 0x002B},
    {"SPOOLER"  , 0x002C},
    {"WIN32S"   , 0x002D},
    {"DEBUGCMD" , 0x002E},
    {"CONFIGMG" , 0x0033},
    {"DWCFGMG"  , 0x0034},
    {"SCSIPORT" , 0x0035},
    {"VFBACKUP" , 0x0036},
    {"ENABLE"   , 0x0037},
    {"VCOND"    , 0x0038},
    {"ISAPNP"   , 0x003C},
    {"BIOS"     , 0x003D},
    {"IFSMGR"   , 0x0040},
    {"VCDFSD"   , 0x0041},
    {"MRCI2"    , 0x0042},
    {"PCI"      , 0x0043},
    {"PELOADER" , 0x0044},
    {"EISA"     , 0x0045},
    {"DRAGCLI"  , 0x0046},
    {"DRAGSRV"  , 0x0047},
    {"PERF"     , 0x0048},
    {"AWREDIR"  , 0x0049},
    {"ETEN"     , 0x0060},
    {"CHBIOS"   , 0x0061},
    {"VMSGD"    , 0x0062},
    {"VPPID"    , 0x0063},
    {"VIME"     , 0x0064},
    {"VHBIOSD"  , 0x0065},
    {"MMDEVLDR" , 0x044A},
    {"VREDIR"   , 0x0481},
    {"VCACHE"   , 0x048B},
    {"PCCARD"   , 0x097C},
    {""         , 0x0000}};

int findLine( char *marker1, char *marker2, char *dest )
{
    char tmp[50];
    char *p;

    while( fgets( Buffer, 256, f1 ) != NULL )
    {
        for( p = Buffer; *p; p++ ) if( *p == ',' ) *p = ' ';

        tmp[0] = *dest = '\0';
        if( sscanf( Buffer, " %40s %40s ", tmp, dest ) )
        {
            _strupr( tmp );
            if( strcmp( tmp, marker1 ) == 0 ) return 1;
            if( marker2 && (strcmp( tmp, marker2 ) == 0) ) return 2;
        }
    }
    return 0;
}

int GetVxdSymbols( char *file1, char *file2 )
{
    char tmp[80];
    int n;

    if( (f1 = fopen( file1, "r" )) == NULL )
    {
        printf( "\nFile '%s' not found.", file1 );
        return( 2 );
    }

    if( findLine( "BEGIN_SERVICE_TABLE", (char *)NULL, VxdName ) != 1 )
    {
        printf("\nFile format not understood ...");
        printf("\n'BEGIN_SERVICE_TABLE' not found.");
        fclose( f1 );
        return( 3 );
    }

    if( strcmp( VxdName, "MACRO" ) == 0 )
    {
        if( findLine( "BEGIN_SERVICE_TABLE", (char *)NULL, VxdName ) != 1 )
        {
            printf("\nFile format not understood ...");
            printf("\n'BEGIN_SERVICE_TABLE' not found.");
            fclose( f1 );
            return( 4 );
        }
    }

    strcpy( VxdService, VxdName );
    _strupr( VxdService );

    if( !file2 )
    {
        for( n = 0; KnownVxds[n].id; n++ )
            if( strcmp( VxdService, KnownVxds[n].name ) == 0 ) break;

        VxdId = KnownVxds[n].id;
        if( VxdId == 0 )
        {
            printf( "\nDriver name (%s) unkown."
                    "\nEnter ID (in hex) : ", VxdName );
            scanf( "%x", &VxdId );
        }
    }
    strcat( VxdService, "_SERVICE" );

    if( file2 )
    {
        if( (f2 = fopen( file2, "a" )) == NULL )
        {
            printf( "\nError openning '%s'.", file2 );
            fclose( f1 );
            return( 2 );
        }

        fprintf( f2, "\n;** Symbolic information for '%s' **\n\n", VxdName );
        fprintf( f2, "    VxdSymHeader %s, %04Xh, %d, '%s'\n",
                 VxdName, VxdId, len, VxdName );
    }

    for( len = 0;
         (n = findLine( VxdService, "END_SERVICE_TABLE", tmp )) == 1;
         len++ )
    {
//      _strupr( tmp );
        if( file2 )
            fprintf( f2, "    VxdSymDef %s, %d, '%s'\n",
                     VxdName, len, tmp );
//      else
//          printf("\n%04X : %s %s", len, VxdName, tmp );
    }

    fclose( f1 );

    if( file2 )
    {
        fprintf( f2, "End_Of_%s label byte\n", VxdName );
        fclose( f2 );
    }
    else
    {
        if( n != 2 )
            printf("\nWarnning: End of service table not found.");
        printf("\nTotal number of %d services was found.\n", len);
    }

    return 0;
}

int main( int argc, char *argv[] )
{
    int n;

    printf( "MakeSym v1.0.\n"
            "(C) copyright 1995 Mehdi Sotoodeh.  All reights reserved." );

    if( argc < 3 )
    {
        printf("\nUSAGE: MAKESYM <vxd_definition_file> <symbol_file>");
        return( 1 );
    }
    printf( "\n'%s' => '%s'.", argv[1], argv[2] );

    n = GetVxdSymbols( argv[1], (char *)NULL );
    if( !n ) n = GetVxdSymbols( argv[1], argv[2] );
    return n;
}
