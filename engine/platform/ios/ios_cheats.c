/*
ios_cheats.c - the iOS port's cheat mode ("sithewok") and chapter select
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

// Single player only. The cheat sets the player's flags directly on the
// local server rather than sending "god" (a toggle), so on and off are exact.

#include "common.h"
#include "client.h"
#include "server.h"
#include "ios_touch.h"

typedef struct
{
	const char *title;
	const char *map;
} ios_chapter_t;

typedef struct
{
	const char *gamedir;
	const ios_chapter_t *chapters;
	int count;
} ios_game_chapters_t;

static const ios_chapter_t hl_chapters[] =
{
{ "Hazard Course",              "t0a0" },
{ "Black Mesa Inbound",         "c0a0" },
{ "Anomalous Materials",        "c1a0" },
{ "Unforeseen Consequences",    "c1a1" },
{ "Office Complex",             "c1a2" },
{ "\"We've Got Hostiles\"",     "c1a3" },
{ "Blast Pit",                  "c1a4" },
{ "Power Up",                   "c2a1" },
{ "On A Rail",                  "c2a2" },
{ "Apprehension",               "c2a3" },
{ "Residue Processing",         "c2a4" },
{ "Questionable Ethics",        "c2a4d" },
{ "Surface Tension",            "c2a5" },
{ "\"Forget About Freeman!\"",  "c3a1" },
{ "Lambda Core",                "c3a2" },
{ "Xen",                        "c4a1" },
{ "Gonarch's Lair",             "c4a2" },
{ "Interloper",                 "c4a1a" },
{ "Nihilanth",                  "c4a3" },
{ "Uplink",                     "hldemo1" }, // 25th anniversary data only
};

static const ios_chapter_t of_chapters[] =
{
{ "Boot Camp",                  "ofboot0" },
{ "Incoming",                   "of0a0" },
{ "Welcome to Black Mesa",      "of1a1" },
{ "\"We Are Pulling Out\"",     "of1a5" },
{ "Missing in Action",          "of2a1" },
{ "Friendly Fire",              "of2a4" },
{ "We Are Not Alone",           "of3a1" },
{ "Crush Depth",                "of3a4" },
{ "Vicarious Reality",          "of4a1" },
{ "Pit Worm's Nest",            "of4a4" },
{ "Foxtrot Uniform",            "of5a1" },
{ "\"The Package\"",            "of6a1" },
{ "Worlds Collide",             "of6a4b" },
{ "Conclusion",                 "of7a0" },
};

static const ios_chapter_t bs_chapters[] =
{
{ "Hazard Course",              "ba_hazard1" },
{ "Living Quarters Outbound",   "ba_tram1" },
{ "Insecurity",                 "ba_security1" },
{ "Duty Calls",                 "ba_canal1" },
{ "Captive Freight",            "ba_yard1" },
{ "Focal Point",                "ba_teleport1" },
{ "Power Struggle",             "ba_power1" },
{ "A Leap of Faith",            "ba_teleport2" },
};

static const ios_game_chapters_t game_chapters[] =
{
{ "valve",   hl_chapters, ARRAYSIZE( hl_chapters ) },
{ "gearbox", of_chapters, ARRAYSIZE( of_chapters ) },
{ "bshift",  bs_chapters, ARRAYSIZE( bs_chapters ) },
};

// the chapters of the running game whose first map is installed
static const ios_chapter_t *chapters[32];
static int num_chapters;
static char chapters_game[MAX_QPATH];

static qboolean cheat_on;
static char saved_sv_cheats[16];
static int cheat_servercount = -1;
static qboolean give_on_load; // LEVEL's map starts with nothing: the suit and weapons

static edict_t *IOS_CheatPlayer( void )
{
	if( sv.state != ss_active || sv.background || svs.maxclients != 1 || !svs.clients )
		return NULL;

	if( svs.clients[0].state != cs_spawned || !SV_IsValidEdict( svs.clients[0].edict ))
		return NULL;

	return svs.clients[0].edict;
}

static void IOS_FindChapters( void )
{
	int i, j;

	if( !Q_stricmp( chapters_game, GI->gamefolder ))
		return;

	Q_strncpy( chapters_game, GI->gamefolder, sizeof( chapters_game ));
	num_chapters = 0;

	for( i = 0; i < ARRAYSIZE( game_chapters ); i++ )
	{
		if( Q_stricmp( game_chapters[i].gamedir, GI->gamefolder ))
			continue;

		for( j = 0; j < game_chapters[i].count && num_chapters < ARRAYSIZE( chapters ); j++ )
		{
			const ios_chapter_t *c = &game_chapters[i].chapters[j];

			if( FS_FileExists( va( "maps/%s.bsp", c->map ), false ))
				chapters[num_chapters++] = c;
			else Con_Reportf( "iOS: chapter %s skipped, no maps/%s.bsp\n", c->title, c->map );
		}
	}
}

int IOS_CheatAllowed( void )
{
	return IOS_CheatPlayer( ) != NULL;
}

int IOS_LevelCount( void )
{
	if( !IOS_CheatAllowed( ))
		return 0;

	IOS_FindChapters( );
	return num_chapters;
}

const char *IOS_LevelTitle( int i )
{
	IOS_FindChapters( );
	return i >= 0 && i < num_chapters ? chapters[i]->title : "";
}

static void IOS_ApplyCheat( edict_t *ent, qboolean give )
{
	if( !saved_sv_cheats[0] )
		Q_strncpy( saved_sv_cheats, Cvar_VariableString( "sv_cheats" ), sizeof( saved_sv_cheats ));
	Cvar_Set( "sv_cheats", "1" );
	SetBits( ent->v.flags, FL_GODMODE );

	if( give )
		Cbuf_AddText( "impulse 101\n" );
}

void IOS_CheatSet( int on )
{
	edict_t *ent = IOS_CheatPlayer( );

	cheat_on = on;

	if( !ent )
		return;

	// a sound of its own, from the game's: an energy surge on, the
	// "denied" buzz off
	S_StartLocalSound( on ? "debris/beamstart1.wav" : "buttons/button10.wav", 1.0f, false );

	if( on )
	{
		IOS_ApplyCheat( ent, true );
		cheat_servercount = cl.servercount;
		return;
	}

	ClearBits( ent->v.flags, FL_GODMODE|FL_NOTARGET );
	if( ent->v.movetype == MOVETYPE_NOCLIP )
		ent->v.movetype = MOVETYPE_WALK;
	// as it was before the cheat
	Cvar_Set( "sv_cheats", saved_sv_cheats[0] ? saved_sv_cheats : "0" );
	saved_sv_cheats[0] = 0;
}

int IOS_CheatNoclip( void )
{
	edict_t *ent = IOS_CheatPlayer( );
	return ent && ent->v.movetype == MOVETYPE_NOCLIP;
}

int IOS_CheatNotarget( void )
{
	edict_t *ent = IOS_CheatPlayer( );
	return ent && FBitSet( ent->v.flags, FL_NOTARGET );
}

void IOS_CheatSetNoclip( int on )
{
	edict_t *ent = IOS_CheatPlayer( );

	if( !ent || !cheat_on )
		return;

	ent->v.movetype = on ? MOVETYPE_NOCLIP : MOVETYPE_WALK;
}

void IOS_CheatSetNotarget( int on )
{
	edict_t *ent = IOS_CheatPlayer( );

	if( !ent || !cheat_on )
		return;

	if( on )
		SetBits( ent->v.flags, FL_NOTARGET );
	else ClearBits( ent->v.flags, FL_NOTARGET );
}

void IOS_GoToLevel( int i )
{
	IOS_FindChapters( );

	if( !IOS_CheatAllowed( ) || i < 0 || i >= num_chapters )
		return;

	Cbuf_AddTextf( "map %s\n", chapters[i]->map );
	give_on_load = true;
}

// once a frame: god mode comes back on each new level, noclip and notarget
// end there (as flying ends at each new level in the other ports)
void IOS_CheatFrame( void )
{
	edict_t *ent;

	if( !cheat_on || cl.servercount == cheat_servercount )
		return;

	ent = IOS_CheatPlayer( );
	if( !ent )
		return;

	cheat_servercount = cl.servercount;
	IOS_ApplyCheat( ent, give_on_load );
	give_on_load = false;
	ClearBits( ent->v.flags, FL_NOTARGET );
	if( ent->v.movetype == MOVETYPE_NOCLIP )
		ent->v.movetype = MOVETYPE_WALK;
}

// typing the word in the console toggles the cheat, as in the other ports
static void IOS_Sithewok_f( void )
{
	IOSTouch_ToggleCheat( );
}

void IOS_CheatInit( void )
{
	Cmd_AddCommand( "sithewok", IOS_Sithewok_f, "" );
}
