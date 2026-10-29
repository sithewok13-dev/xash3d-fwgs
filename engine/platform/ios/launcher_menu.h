/*
launcher_menu.h - iOS game picker
Copyright (C) 2026 sithewok

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/
#ifndef LAUNCHER_MENU_H
#define LAUNCHER_MENU_H

// Shows the game picker and blocks until a game is chosen.
// Returns a malloc'd argv (argv[0] empty) and sets XASH3D_BASEDIR.
char **IOS_RunLauncher( const char *docsdir, int *argc );

// After a game: the picker again, the pick kept for the next launch (see
// IOS_RunLauncher), a notification to tap, and the app closes. No return.
void IOS_RunSwitch( const char *docsdir ) __attribute__(( noreturn ));

#endif // LAUNCHER_MENU_H
