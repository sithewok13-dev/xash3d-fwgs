/*
launcher.c - direct xash3d launcher
Copyright (C) 2015 Mittorn

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#if XASH_ENABLE_MAIN
#include "build.h"
#include "common.h"

#if XASH_SDLMAIN
#include <SDL.h>
#endif

#ifndef XASH_GAMEDIR
#define XASH_GAMEDIR "valve" // !!! Replace with your default (base) game directory !!!
#endif

static int  szArgc;
static char **szArgv;

static void Sys_ChangeGame( const char *progname )
{
	// stub
}

int main( int argc, char **argv )
{
#if XASH_PSVITA
	// inject -dev -console into args if required
	szArgc = PSVita_GetArgv( argc, argv, &szArgv );
#elif XASH_IOS
	// iOS has no way to start the app again, so Quit (a game's own, or
	// GAMES in the touch controls' tray) comes back out of Host_Main to
	// "Choose a game", and the engine runs again in the same process
	for( int run = 1; ; run++ )
	{
		IOS_Trace( "run %d: Choose a game", run );
		IOS_LaunchDialog();
		szArgc = IOS_GetArgs( &szArgv );

		char args[1024] = "";
		for( int i = 1; i < szArgc; i++ )
		{
			Q_strncat( args, " ", sizeof( args ));
			Q_strncat( args, szArgv[i], sizeof( args ));
		}
		IOS_Trace( "run %d: start engine:%s", run, args );

		Host_Main( szArgc, szArgv, XASH_GAMEDIR, 0, Sys_ChangeGame );

		IOS_Trace( "run %d: engine stopped, resetting", run );
		IOS_RelaunchReset();
		Host_ResetForRelaunch();
	}
#else
	szArgc = argc;
	szArgv = argv;
#endif // XASH_PSVITA
	return Host_Main( szArgc, szArgv, XASH_GAMEDIR, 0, Sys_ChangeGame );
}
#endif // XASH_ENABLE_MAIN
