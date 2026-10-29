/*
ios_touch_glue.c - engine side of the iOS touch controls
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

#include "common.h"
#include "client.h"
#include "keydefs.h"
#include "ios_touch.h"

static qboolean ios_paused; // paused by us, for "Switch game"
static const char *ios_touch_cmds[IOSTOUCH_CMD_COUNT] =
{
	"attack", "attack2", "duck", "use", "jump", "reload",
	"forward", "back", "moveleft", "moveright", "speed",
};

static unsigned int ios_touch_held;

static qboolean IOS_TouchInGame( void )
{
	return cls.state == ca_active && cls.key_dest == key_game && !cl.background && !Con_Visible( ) && !CL_IOSScreenFaded( );
}

static void IOS_TouchRunAction( int action )
{
	switch( action )
	{
	case IOSTOUCH_ACT_NEXTWEAPON:
		// straight to the next weapon with ammo, no HUD list
		IOS_WeaponNext( );
		break;
	case IOSTOUCH_ACT_FLASHLIGHT:
		Cbuf_AddText( "impulse 100\n" );
		break;
	case IOSTOUCH_ACT_QUICKSAVE:
		Cbuf_AddText( "savequick\n" );
		break;
	case IOSTOUCH_ACT_QUICKLOAD:
		Cbuf_AddText( "loadquick\n" );
		break;
	case IOSTOUCH_ACT_ESCAPE:
		Key_Event( K_ESCAPE, true );
		Key_Event( K_ESCAPE, false );
		break;
	case IOSTOUCH_ACT_CONSOLE:
		Cbuf_AddText( "toggleconsole\n" );
		break;
	case IOSTOUCH_ACT_SHOWFPS:
		Cvar_Set( "cl_showfps", "1" );
		break;
	case IOSTOUCH_ACT_HIDEFPS:
		Cvar_Set( "cl_showfps", "0" );
		break;
	case IOSTOUCH_ACT_GAMES:
		// the engine shuts down; the picked game starts at the app's next launch
		Cbuf_AddText( "quit\n" );
		break;
	case IOSTOUCH_ACT_PAUSE:
		// pause toggles: only if it isn't paused already, and remembered
		if( !cl.paused && cl.maxclients == 1 )
		{
			Cbuf_AddText( "pause\n" );
			ios_paused = true;
		}
		break;
	case IOSTOUCH_ACT_UNPAUSE:
		if( ios_paused && cl.paused )
			Cbuf_AddText( "pause\n" );
		ios_paused = false;
		break;
	}
}

// ios_taps [0|1]: the touch debugging marks (see IOS_TouchDebugDraw)
static void IOS_Taps_f( void )
{
	int on = Cmd_Argc( ) > 1 ? Q_atoi( Cmd_Argv( 1 )) : !IOSTouch_ShowTaps( );

	IOSTouch_SetShowTaps( on );
	Con_Printf( "Touch marks %s\n", on ? "on: white ring = finger, red cross = the game's tap" : "off" );
}

static qboolean ios_touch_initialized;

void IOS_TouchFrame( void )
{
	qboolean ingame = IOS_TouchInGame( );
	unsigned int held, changed;
	int action, i;

	if( !ios_touch_initialized )
	{
		// the overlay replaces the engine's own touch buttons
		Cvar_Set( "touch_enable", "0" );
		IOS_CheatInit( );
		Cmd_AddCommand( "ios_taps", IOS_Taps_f, "touch debugging marks: white ring = finger, red cross = the game's tap" );
		ios_touch_initialized = true;
	}

	IOS_CheatFrame( );
	IOSTouch_Frame( host.hWnd, ingame );
	// a game running (not the menu's background map), or hosting one, menus
	// over it included
	IOSTouch_KeepAwake(( cls.state == ca_active && !cl.background ) || ( SV_Active( ) && SV_GetMaxClients( ) > 1 ));

	held = ingame ? IOSTouch_HeldCommands( ) : 0;
	changed = held ^ ios_touch_held;

	for( i = 0; i < IOSTOUCH_CMD_COUNT; i++ )
	{
		if( FBitSet( changed, BIT( i )))
			Cbuf_AddTextf( "%c%s\n", FBitSet( held, BIT( i )) ? '+' : '-', ios_touch_cmds[i] );
	}

	ios_touch_held = held;

	// the engine takes the look only while playing: thrown away while
	// paused, so the view doesn't jump when the game goes on
	if( cl.paused || !ingame )
	{
		float yaw, pitch;
		IOSTouch_TakeLook( &yaw, &pitch );
	}

	while(( action = IOSTouch_PopAction( )) != IOSTOUCH_ACT_NONE )
		IOS_TouchRunAction( action );
}

// TAPS: the last place each finger went down, as the game got it (0..1 of
// the screen), drawn as a red cross over everything, menus included
#define IOS_TAPS_MAX  4
#define IOS_TAPS_TIME 1.5

static struct
{
	int finger;
	float x, y;
	double up_time; // 0 while down
	qboolean used;
} ios_taps[IOS_TAPS_MAX];

void IOS_TouchDebugEvent( int down, int up, int finger, float x, float y )
{
	int i, slot = -1;

	if( !IOSTouch_ShowTaps( ))
		return;

	for( i = 0; i < IOS_TAPS_MAX; i++ )
	{
		if( ios_taps[i].used && ios_taps[i].finger == finger && !ios_taps[i].up_time )
			slot = i;
	}

	if( down || slot < 0 )
	{
		double oldest = host.realtime + 1.0;

		// a free slot, or the one let go longest ago
		for( i = 0, slot = 0; i < IOS_TAPS_MAX; i++ )
		{
			double t = ios_taps[i].used ? ( ios_taps[i].up_time ? ios_taps[i].up_time : host.realtime ) : -1.0;

			if( t < oldest )
			{
				oldest = t;
				slot = i;
			}
		}
	}

	ios_taps[slot].used = true;
	ios_taps[slot].finger = finger;
	ios_taps[slot].x = x;
	ios_taps[slot].y = y;
	ios_taps[slot].up_time = up ? host.realtime : 0.0;
}

void IOS_TouchDebugDraw( void )
{
	int i;

	if( !IOSTouch_ShowTaps( ))
		return;

	for( i = 0; i < IOS_TAPS_MAX; i++ )
	{
		const int arm = 36, thick = 4;
		float x, y;
		int alpha;
		char text[32];
		rgba_t color;

		if( !ios_taps[i].used )
			continue;

		alpha = 255;
		if( ios_taps[i].up_time )
		{
			double age = host.realtime - ios_taps[i].up_time;

			if( age >= IOS_TAPS_TIME )
			{
				ios_taps[i].used = false;
				continue;
			}
			alpha = 255 * ( 1.0 - age / IOS_TAPS_TIME );
		}

		x = ios_taps[i].x * refState.width;
		y = ios_taps[i].y * refState.height;

		ref.dllFuncs.FillRGBA( kRenderTransTexture, x - arm, y - thick / 2, arm * 2, thick, 255, 40, 40, alpha );
		ref.dllFuncs.FillRGBA( kRenderTransTexture, x - thick / 2, y - arm, thick, arm * 2, 255, 40, 40, alpha );

		Q_snprintf( text, sizeof( text ), "%d,%d", (int)x, (int)y );
		MakeRGBA( color, 255, 80, 80, alpha );
		Con_DrawString( x + 8, y + 8, text, color );
	}
}

void IOS_TouchGetMove( float *pitch, float *yaw )
{
	float dyaw = 0.0f, dpitch = 0.0f;

	IOSTouch_TakeLook( &dyaw, &dpitch );

	if( !IOS_TouchInGame( ))
		return;

	*yaw += dyaw;
	*pitch += dpitch;
}

// Before the engine runs again in the same process (back to "Choose a
// game", see launcher.c): what of ours was tied to the old engine
void IOS_RelaunchReset( void )
{
	ios_touch_initialized = false; // its commands are registered anew
	ios_touch_held = 0;
	memset( ios_taps, 0, sizeof( ios_taps ));
	IOS_WeaponsForget( );
	IOS_PhotoForget( );
	IOS_CheatForget( );
}
