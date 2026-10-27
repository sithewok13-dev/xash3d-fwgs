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

static const char *ios_touch_cmds[IOSTOUCH_CMD_COUNT] =
{
	"attack", "attack2", "duck", "use", "jump", "reload",
	"forward", "back", "moveleft", "moveright", "speed",
};

static unsigned int ios_touch_held;

static qboolean IOS_TouchInGame( void )
{
	return cls.state == ca_active && cls.key_dest == key_game && !cl.background && !Con_Visible( );
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
	}
}

void IOS_TouchFrame( void )
{
	static qboolean initialized;
	qboolean ingame = IOS_TouchInGame( );
	unsigned int held, changed;
	int action, i;

	if( !initialized )
	{
		// the overlay replaces the engine's own touch buttons
		Cvar_Set( "touch_enable", "0" );
		IOS_CheatInit( );
		initialized = true;
	}

	IOS_CheatFrame( );
	IOSTouch_Frame( host.hWnd, ingame );

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

void IOS_TouchGetMove( float *pitch, float *yaw )
{
	float dyaw = 0.0f, dpitch = 0.0f;

	IOSTouch_TakeLook( &dyaw, &dpitch );

	if( !IOS_TouchInGame( ))
		return;

	*yaw += dyaw;
	*pitch += dpitch;
}
