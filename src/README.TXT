SoftProbe Release 1.00.
Copyright 1996 Mehdi Sotoodeh.  All rights reserved.

SETTING UP THE DEBUGGING TERMINAL
=================================
SoftProbe supports four different configurations for its debugging terminal.

1. Using a single monitor.
2. Using secondary monochrome or Hecules monitor.
3. Using a secondary PC connected via a serial cable.
4. Using a secondary PC connected via a parallel cable (InterLink cables).

1. Single monitor setup
-----------------------
SoftProbe currently supports standard VGA adaptors. The setup process for
this mode of operation includes:

a. Set up your system to use plain VGA mode (only VGA mode currently
   supported).
b. Edit SPW95.INI file and replace the "SET SCR=..." line in the [INIT]
   section with:
        SET SCR=VGA
c. Restart your system and SoftProbe.

2. Mono monitor setup
---------------------
This mode of operation is the most recommended option because it does not
require any screen switching. To setup for this mode:

a. Install a secondary display adapter (monochrome or Hecules) on your
   system and attach it to monitor.
b. Edit SPW95.INI file and replace the "SET SCR=..." line in the [INIT]
   section with:
   SET SCR=MONO
c. Restart your system and SoftProbe.

3. Dual PC setup using a serial cable
-------------------------------------
a. Connect these two PC's via a 3-wire serial cable.
b. Edit SPW95.INI file and replace "SET SCR=..." line with:
        SET SCR=COMx:baud
   Where, x=1,..4 and baud=300,..115200.
c. Copy REMOTE.EXE to the second PC and run:
        REMOTE COMx:baud
   Where COMx (x=1..4) is the serial port used and baud (300..115200)
   is its speed.
   Please note the two baud rates should be the same.
d. Restart your main PC and SoftProbe.

4. Dual PC setup using a parallel cable
---------------------------------------
The cable used here is the one known as InterLink(tm) cables. The
advantage of this mode against the serial cable is speed.
a. Connect both PC's via a parallel cable.
b. Edit SPW95.INI file and replace "SET SCR=..." line with:
        SET SCR=LPTx
   Where, x=1,2 or 3.
c. Copy REMOTE.EXE to the second PC and run:
        REMOTE LPTx
   Where LPTx (x=1,2 or 3) is the port used.
d. Restart your main PC and SoftProbe.

Printer support
===============
SoftProbe can utilize a local printer (network printers not supported)
while in debugging mode. Alternatively, you can capture the LOG buffer
using SPWCC.EXE and then print it using any printers.
The printer output is text only, however, it can contain line drawing
characters.
To select a parallel port for the printer, add the following line in the
[INIT] section of the SPW95.INI file:
        SET PRN=LPTx            Where, x=1,2 or 3.

Activating SoftProbe
====================
To activate SoftProbe, start your PC with command promt (reboot and
press F8 when "Starting Windows 95..." appears, then select the
"Command Prompt Only" from the menu) and then run SPW95.EXE.

Alternatively, you can load SoftProbe by editing the C:\AUTOEXEC.BAT
file and add following line to the end of it.
        <path>\SPW95.EXE

For a more flexible approach, add following lines to your
        CHOICE /c:NY Load SoftProbe (Y/N)?
        if errorlevel 2 <path>\SPW95.EXE

Or
        CHOICE /T:N,10 /c:NY Load SoftProbe (Y/N)?
        if errorlevel 2 <path>\SPW95.EXE

While SoftProbe is loaded, use the HOTKEY (defined in the .INI file) to
acrivate it. Default HOTKEY is ^SPACE (hold Ctrl and press space bar).

