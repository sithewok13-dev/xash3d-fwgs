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

// Keeps the screen on while a game runs (a multiplayer host freezes for
// everyone if the phone locks)
void IOSTouch_KeepAwake( int on );

// The console word "sithewok": switches the cheat, and shows its button
void IOSTouch_ToggleCheat( void );

// TAPS: the touch debugging marks are on
int IOSTouch_ShowTaps( void );

// engine side (ios_touch_glue.c)
void IOS_TouchFrame( void );
void IOS_TouchGetMove( float *pitch, float *yaw );

// Photo kinds, also the bits of the PHOTO option
enum
{
	IOSTOUCH_PHOTO_CLEAN   = 1, // the scene, no HUD
	IOSTOUCH_PHOTO_HUD     = 2, // as seen, with the HUD
	IOSTOUCH_PHOTO_HUDBTNS = 4, // with the HUD and the touch buttons
};

// overlay side (ios_touch.m), for the photos
void IOSTouch_ShowMessage( const char *text );
void IOSTouch_CameraFeedback( int burst );
#ifdef __OBJC__
@class UIView;
UIView *IOSTouch_OverlayView( void );
#endif

// saving (ios_photos.m): the engine wrote one frame to path
void IOSPhotos_SaveFile( const char *path, int kind, int burst );
void IOSPhotos_SetBatch( int on );
void IOSPhotos_AskAccess( void );

// engine side (ios_photo.c)
int IOS_PhotoCameraAllowed( void );
int IOS_PhotoCameraActive( void );
void IOS_PhotoCameraEnd( void );
int IOS_PhotoSelfieBegin( void );
void IOS_PhotoSelfieShot( int i, int n );
int IOS_PhotoFreezeBegin( void );
void IOS_PhotoFreezeMove( float dx, float dy, float panx, float pany, float zoom );
int IOS_PhotoOrbitBegin( void );
void IOS_PhotoOrbitShot( int i, int n );
void IOS_PhotoCapture( int kind, int burst );
int IOS_PhotoBusy( void );

// the weapon wheel (ios_weapons.c)
typedef struct
{
	int id;
	const char *name;
	int clip;       // -1 unknown or none
	int reserve;    // -1 for weapons without ammo
	int has_ammo;
	int current;
} ios_wheel_item_t;

void IOS_WeaponsUserMsg( const char *name, int size, const void *data );
int IOS_WeaponList( ios_wheel_item_t *out, int max );
void IOS_WeaponSelect( int id );
void IOS_WeaponNext( void );
const char *IOS_WeaponDisplayName( const char *classname );
const unsigned char *IOS_WeaponIcon( int id, int *w, int *h );

// the flashlight's HUD pictures and state, for the LIGHT button
enum { IOSTOUCH_FLASH_EMPTY, IOSTOUCH_FLASH_FULL, IOSTOUCH_FLASH_BEAM, IOSTOUCH_FLASH_PARTS };
const unsigned char *IOS_FlashlightIcon( int part, int *w, int *h );
void IOS_FlashlightState( int *on, int *battery );
int IOS_HudHidesSprite( const char *sprite, int left, int top, int right, int bottom );

// whether the touch controls are up (ios_touch.m)
int IOS_TouchShown( void );

// holds a single player game still (the wheel), ios_photo.c
void IOS_HoldGame( int on );

// engine side (ios_cheats.c), single player only
void IOS_CheatInit( void );
void IOS_CheatFrame( void );
int IOS_CheatAllowed( void );
void IOS_CheatSet( int on );
int IOS_CheatNoclip( void );
int IOS_CheatNotarget( void );
void IOS_CheatSetNoclip( int on );
void IOS_CheatSetNotarget( int on );
int IOS_LevelCount( void );
const char *IOS_LevelTitle( int i );
void IOS_GoToLevel( int i );

#endif // IOS_TOUCH_H
