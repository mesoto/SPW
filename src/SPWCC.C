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

#include <windows.h>
#include <commdlg.h>
#include <stdio.h>
#include "stdlib.h"
#include "SPWCC.h"
#include "spapi.inc"

#define MAXFILENAME 256         /* maximum length of file pathname      */

/* Globals */
HANDLE      ghInst;                     // app's instance handle
char        gszAppName[] = "SoftProbe"; // for title bar, etc.
char        Buffer[0x2000];
char        filename[MAXFILENAME];
BOOL        bAppend = TRUE;

OPENFILENAME ofn;
char szLogFiles[] = "Log Files (*.LOG)\0*.LOG\0"
                    "All Files (*.*)\0*.*\0";
char szExeFiles[] = "DLLs\0*.DLL\0EXEs\0*.EXE\0"
                    "All Files (*.*)\0*.*\0";

/****************************************************************************/
/* Internal Function Prototypes                                             */
/****************************************************************************/
BOOL CALLBACK SprobeAboutProc( HWND, unsigned, WORD, LONG );
BOOL CALLBACK SprobeLogProc( HWND, unsigned, WORD, LONG );

/**************************************************************************
;*
;* Name        : WinMain
;*
;* Purpose     : Start up routine
;*
;* Inputs      : 
;*
;* Outputs     : 
;*
;* Errors      : None
;*
;* Description : Brings up the INSTALL/UNINSTALL/STATUS dialog box.
;*
;*************************************************************************/

int PASCAL WinMain( HINSTANCE hInst, 
                    HINSTANCE hPrev, 
                    LPSTR lpszCmdLine, 
                    int nCmdShow )
{
  FARPROC fpfn;

  if( hPrev ) return FALSE;

  ghInst = hInst;           // Save instance handle for dialog boxes.

  if( !spw_version( Buffer ))
  {
    MessageBox( NULL,
                (LPSTR)"SoftProbe not loaded.",
                gszAppName,
                MB_OK | MB_APPLMODAL | MB_ICONHAND );
    return FALSE;
  }

  /* Display our dialog box. */
  fpfn = MakeProcInstance( (FARPROC)SprobeLogProc, ghInst );
  DialogBox( ghInst,
             "SYMLOGDLG",
             NULL,
             (DLGPROC)fpfn );
  FreeProcInstance( fpfn );

  return TRUE;
}

/**************************************************************************
;*
;* Name        : SprobeAboutProc
;*
;* Purpose     : Displays the ABOUT dialog box.
;*
;* Inputs      : 
;*
;* Outputs     : 
;*
;* Errors      : None
;*
;* Description : Dialog procedure function for ABOUTBOX dialog box.
;*
;*************************************************************************/

BOOL CALLBACK SprobeAboutProc( HWND hWnd,
                               unsigned wMsg,
                               WORD wParam,
                               LONG lParam )
{
  switch (wMsg)
  {
    case WM_INITDIALOG:
      return TRUE;

    case WM_COMMAND:
      if( wParam == IDOK || wParam == IDCANCEL )
          EndDialog(hWnd, TRUE);
      break;
  }
  return FALSE;
}

/**************************************************************************
;*
;* Name        : UpdateModuleList
;*
;* Purpose     : Displays the list of loaded modules
;*
;* Inputs      : 
;*
;* Outputs     : 
;*
;* Errors      : None
;*
;* Description :
;*
;*************************************************************************/

void pascal
ModLister( int n, unsigned long len, char *name, unsigned long data )
{
  sprintf( Buffer, "%06ld  %s", len, name );
  SendMessage( (HWND)data, LB_ADDSTRING, 0, (LPARAM)(LPCSTR)Buffer );
}

void UpdateModuleList( HWND hWnd )
{
  unsigned long BufferSize, BufferUsed;
  HWND hListBox;

  hListBox = GetDlgItem( hWnd, IDC_MODLIST );
  SendMessage( hListBox, LB_RESETCONTENT, 0, 0L );

  spw_modlist( &BufferSize,
               &BufferUsed,
               &ModLister,
               (unsigned long)hListBox );

  sprintf( Buffer, "%8ld\n"
                   "%8ld\n"
                   "%8ld",
                   BufferSize,
                   BufferUsed,
                   BufferSize - BufferUsed );
  SetDlgItemText( hWnd, IDC_SYMINFO, Buffer );
}

/**************************************************************************
;*
;* Name        : SprobeLogProc
;*
;* Purpose     : Manages the INSTALL dialog box.
;*
;* Inputs      : 
;*
;* Outputs     : 
;*
;* Errors      : None
;*
;* Description : Dialog procedure for LOGGING operations
;*
;*************************************************************************/

BOOL CALLBACK
SprobeLogProc( HWND hWnd, unsigned wMsg, WORD wParam, LONG lParam )
{
  FARPROC fpfn;
  HMENU   hmenuSystem;    // system menu
  unsigned short n;
  unsigned long  linecount;
  char    *p;
  FILE    *logfile;

  switch (wMsg)
  {
    case WM_INITDIALOG:
      // Append "About" menu item to system menu.
      hmenuSystem = GetSystemMenu( hWnd, FALSE );
      AppendMenu( hmenuSystem, MF_SEPARATOR, 0, NULL );
      AppendMenu( hmenuSystem, MF_STRING, IDM_ABOUT, "&About SPWCC..." );
      SetDlgItemText( hWnd, IDC_FILENAME, "SPWIN.LOG" );
      SendDlgItemMessage( hWnd, IDC_APPEND, BM_SETCHECK, bAppend, NULL );
      UpdateModuleList( hWnd );
      return TRUE;

    case WM_SYSCOMMAND:
      switch (wParam)
      {
        case IDM_ABOUT:
          // Display "About" dialog box.
          fpfn = MakeProcInstance( (FARPROC)SprobeAboutProc, ghInst );
          DialogBox( ghInst, "ABOUTBOX", hWnd, (DLGPROC)fpfn );
          FreeProcInstance( fpfn );
          break;
      }
      break;

    case WM_COMMAND:
      switch (wParam)
      {
        case IDC_APPEND:   // Append checkbox is hit
          bAppend ^= TRUE;
          return TRUE;

        case IDC_BROWSE:

          /* Use standard open dialog */
          ofn.lStructSize       = sizeof(OPENFILENAME);
          ofn.hwndOwner         = hWnd;
          ofn.hInstance         = ghInst;
          ofn.lpstrFilter       = szLogFiles;
          ofn.lpstrCustomFilter = NULL;
          ofn.nMaxCustFilter    = 0;
          ofn.nFilterIndex      = 1;
          ofn.lpstrFile         = filename;
          ofn.nMaxFile          = MAXFILENAME;
          ofn.lpstrInitialDir   = NULL;
          ofn.lpstrFileTitle    = "Open Log file";
          ofn.nMaxFileTitle     = MAXFILENAME;
          ofn.lpstrTitle        = "Open Log file";
          ofn.lpstrDefExt       = "LOG";
          ofn.Flags             = OFN_HIDEREADONLY;

          if (!GetOpenFileName ((LPOPENFILENAME)&ofn)) return FALSE;

          SetDlgItemText( hWnd, IDC_FILENAME, filename );
          break;

        case IDC_VIEW:
          GetDlgItemText( hWnd, IDC_FILENAME, filename, MAXFILENAME );
          sprintf( Buffer, "NOTEPAD %s", filename );
          WinExec( (LPCSTR)Buffer, SW_SHOW );
          break;

        case IDC_MOVE:
        case IDC_LOAD:
          GetDlgItemText( hWnd, IDC_FILENAME, filename, MAXFILENAME );
          logfile = fopen( filename, bAppend ? "at" : "wt" );

          if( logfile == NULL )
          {
            sprintf( Buffer, "Cannot create log file %s.", filename );
            MessageBox( hWnd,
                        (LPSTR)Buffer,
                        gszAppName,
                        MB_OK | MB_APPLMODAL | MB_ICONHAND );
            break;
          }

          spw_logseek( 0 );
          for( linecount = 0; p = spw_logreadline( &n ); linecount++ )
          {
            if( n == 0 ) break;
            fwrite( p, sizeof(char), (size_t)n, logfile );
          }
          fclose( logfile );

          if( wParam == IDC_MOVE ) spw_logclear();
          sprintf( Buffer, (wParam == IDC_MOVE) ?
                           "%ld lines moved to file %s." :
                           "%ld lines loaded into file %s.",
                           linecount, filename );
          MessageBox( hWnd,
                      (LPSTR)Buffer,
                      gszAppName,
                      MB_OK | MB_APPLMODAL | MB_ICONINFORMATION );
          break;

        // ------------------------------------------------------------------
        // Exported names support.
        // ------------------------------------------------------------------
        case IDC_REMOVE:    // Remove a module
          n = (unsigned short)SendDlgItemMessage( hWnd,
                                                  IDC_MODLIST,
                                                  LB_GETCURSEL,
                                                  0,
                                                  0 );
          if( n != LB_ERR )
          {
            SendDlgItemMessage( hWnd,
                                IDC_MODLIST,
                                LB_GETTEXT,
                                (WPARAM)n,
                                (LPARAM)(LPSTR)Buffer );
            spw_modremove( &Buffer[8] );
            UpdateModuleList( hWnd );
          }
          return TRUE;

        case IDC_ADD:       // Add a new module
          /* Use standard open dialog */
          ofn.lStructSize       = sizeof(OPENFILENAME);
          ofn.hwndOwner         = hWnd;
          ofn.hInstance         = ghInst;
          ofn.lpstrFilter       = szExeFiles;
          ofn.lpstrCustomFilter = NULL;
          ofn.nMaxCustFilter    = 0;
          ofn.nFilterIndex      = 1;
          ofn.lpstrFile         = filename;
          ofn.nMaxFile          = MAXFILENAME;
          ofn.lpstrInitialDir   = NULL;
          ofn.lpstrFileTitle    = "Load exports";
          ofn.nMaxFileTitle     = MAXFILENAME;
          ofn.lpstrTitle        = "Load exports";
          ofn.lpstrDefExt       = "DLL";
          ofn.Flags             = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;

          if( !GetOpenFileName( (LPOPENFILENAME)&ofn )) return FALSE;

          if( spw_modload( filename ))
          {
            UpdateModuleList( hWnd );
            break;
          }
          sprintf( Buffer, "Could not load exported names of %s.", filename );
          MessageBox( hWnd,
                      (LPSTR)Buffer,
                      gszAppName,
                      MB_OK | MB_APPLMODAL | MB_ICONINFORMATION );
          break;

        case IDC_EXIT:      // "Done"
          EndDialog(hWnd, TRUE);
          break;

        case IDCANCEL:      // "Done"
          EndDialog(hWnd, FALSE);
          break;
      }
      break;
  }
  return FALSE;
}
