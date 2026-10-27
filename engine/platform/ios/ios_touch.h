/*
ios_touch.h - iOS touch controls overlay (UIKit), shared with the engine glue
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
#ifndef IOS_TOUCH_H
#define IOS_TOUCH_H

// Commands held while a button or the stick is down, run as +cmd / -cmd
// so they work whatever keys the player has bound
enum
{
	IOSTOUCH_CMD_ATTACK,
	IOSTOUCH_CMD_ATTACK2,
	IOSTOUCH_CMD_DUCK,
	IOSTOUCH_CMD_USE,
	IOSTOUCH_CMD_JUMP,
	IOSTOUCH_CMD_RELOAD,
	IOSTOUCH_CMD_FORWARD,
	IOSTOUCH_CMD_BACK,
	IOSTOUCH_CMD_MOVELEFT,
	IOSTOUCH_CMD_MOVERIGHT,
	IOSTOUCH_CMD_SPEED, // walk: held while the stick is used off the run marker
	IOSTOUCH_CMD_COUNT
};

// One-shot actions, run once each
enum
{
	IOSTOUCH_ACT_NONE,
	IOSTOUCH_ACT_NEXTWEAPON,
	IOSTOUCH_ACT_FLASHLIGHT,
	IOSTOUCH_ACT_QUICKSAVE,
	IOSTOUCH_ACT_QUICKLOAD,
	IOSTOUCH_ACT_ESCAPE,
	IOSTOUCH_ACT_CONSOLE,
	IOSTOUCH_ACT_SHOWFPS,
	IOSTOUCH_ACT_HIDEFPS,
};

// Once per engine frame. window is the SDL_Window; ingame says whether the
// player is in a running game with nothing (menu, console) in front of it.
// The overlay shows only then; otherwise touches go to SDL as mouse clicks.
void IOSTouch_Frame( void *window, int ingame );

// Bits (1 << IOSTOUCH_CMD_*) of the commands held right now
unsigned int IOSTouch_HeldCommands( void );

// The next queued one-shot action, IOSTOUCH_ACT_NONE when there are none
int IOSTouch_PopAction( void );

// View turn since the last call in degrees, from look drags and the gyro
// (yaw: + turns left, pitch: + looks down)
void IOSTouch_TakeLook( float *yaw, float *pitch );

// engine side (ios_touch_glue.c)
void IOS_TouchFrame( void );
void IOS_TouchGetMove( float *pitch, float *yaw );

#endif // IOS_TOUCH_H
