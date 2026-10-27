/*
ios_weapons.c - what the iOS weapon wheel shows: weapons, ammo, HUD icons
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

// The game libraries stay vanilla, so the engine follows the same messages
// the HUD reads (WeaponList, CurWeapon, AmmoX), and the weapons owned come
// from the client data. A weapon is selected the way the HUD does it, by
// sending its name to the server. Icons are cut from the HUD sprites named
// in sprites/weapon_*.txt, so Opposing Force and Blue Shift weapons get
// their own.

#include "common.h"
#include "client.h"
#include "server.h"
#include "ios_touch.h"

#define MAX_IOS_WEAPONS 32
#define MAX_IOS_AMMO    32

typedef struct
{
	char name[32];
	int ammo1, ammo2;     // ammo type index, -1 for none
	int max1;
	int slot, pos;
	int clip;             // last known, -1 unknown
	qboolean known;

	byte *icon;           // RGBA, premultiplied
	int icon_w, icon_h;
	qboolean icon_tried;
} ios_weapon_t;

static ios_weapon_t weapons[MAX_IOS_WEAPONS];
static int ammo[MAX_IOS_AMMO];

// the flashlight, for the LIGHT button
static qboolean flash_on;
static int flash_battery = 100;
static int current_id = -1;
static char weapons_game[MAX_QPATH];

static int ReadByte( const byte **p, const byte *end )
{
	return *p < end ? *(*p)++ : 0;
}

static int ReadChar( const byte **p, const byte *end )
{
	return (signed char)ReadByte( p, end );
}

// the user messages the HUD gets, read here first
void IOS_WeaponsUserMsg( const char *name, int size, const void *data )
{
	const byte *p = data, *end = p + size;

	if( Q_stricmp( weapons_game, GI->gamefolder ))
	{
		// another game: its own weapons
		int i;
		for( i = 0; i < MAX_IOS_WEAPONS; i++ )
		{
			if( weapons[i].icon )
				Mem_Free( weapons[i].icon );
		}
		memset( weapons, 0, sizeof( weapons ));
		Q_strncpy( weapons_game, GI->gamefolder, sizeof( weapons_game ));
	}

	if( !Q_strcmp( name, "WeaponList" ))
	{
		char wname[32];
		int i = 0, id;
		ios_weapon_t w = { 0 };

		while( p < end && *p && i < (int)sizeof( wname ) - 1 )
			wname[i++] = *p++;
		wname[i] = 0;
		if( p < end )
			p++;

		w.ammo1 = ReadChar( &p, end );
		w.max1 = ReadByte( &p, end );
		w.ammo2 = ReadChar( &p, end );
		ReadByte( &p, end );
		w.slot = ReadChar( &p, end );
		w.pos = ReadChar( &p, end );
		id = ReadChar( &p, end );

		if( id <= 0 || id >= MAX_IOS_WEAPONS )
			return;

		Q_strncpy( w.name, wname, sizeof( w.name ));
		w.clip = -1;
		w.known = true;

		if( weapons[id].icon )
			Mem_Free( weapons[id].icon );
		weapons[id] = w;
	}
	else if( !Q_strcmp( name, "CurWeapon" ))
	{
		int state = ReadByte( &p, end );
		int id = ReadChar( &p, end );
		int clip = ReadChar( &p, end );

		if( state && id > 0 && id < MAX_IOS_WEAPONS )
		{
			current_id = id;
			weapons[id].clip = clip;
		}
		else if( !state && id <= 0 )
			current_id = -1;
	}
	else if( !Q_strcmp( name, "Flashlight" ))
	{
		flash_on = ReadByte( &p, end ) != 0;
		flash_battery = ReadByte( &p, end );
	}
	else if( !Q_strcmp( name, "FlashBat" ))
	{
		flash_battery = ReadByte( &p, end );
	}
	else if( !Q_strcmp( name, "AmmoX" ))
	{
		int index = ReadByte( &p, end );
		int count = ReadByte( &p, end );

		if( index < MAX_IOS_AMMO )
			ammo[index] = count;
	}
}

static qboolean IOS_WeaponOwned( int id )
{
	int bits;

	if( id <= 0 || id >= MAX_IOS_WEAPONS || !weapons[id].known )
		return false;

	if( cls.state != ca_active || !cl.frames[cl.parsecountmod].valid )
		return false;

	bits = cl.frames[cl.parsecountmod].clientdata.weapons;
	return FBitSet( bits, BIT( id )) != 0;
}

static int IOS_WeaponReserve( const ios_weapon_t *w )
{
	return w->ammo1 >= 0 && w->ammo1 < MAX_IOS_AMMO ? ammo[w->ammo1] : -1;
}

static qboolean IOS_WeaponHasAmmo( const ios_weapon_t *w )
{
	if( w->ammo1 < 0 )
		return true; // crowbar and the like

	return IOS_WeaponReserve( w ) > 0 || w->clip > 0;
}

// the owned weapons in HUD order (slot, then position)
int IOS_WeaponList( ios_wheel_item_t *out, int max )
{
	int n = 0, slot, pos, id;

	for( slot = 0; slot < 8; slot++ )
	{
		for( pos = 0; pos < 16; pos++ )
		{
			for( id = 1; id < MAX_IOS_WEAPONS && n < max; id++ )
			{
				const ios_weapon_t *w = &weapons[id];

				if( !IOS_WeaponOwned( id ) || w->slot != slot || w->pos != pos )
					continue;

				out[n].id = id;
				out[n].name = IOS_WeaponDisplayName( w->name );
				out[n].clip = id == current_id ? w->clip : -1;
				out[n].reserve = IOS_WeaponReserve( w );
				out[n].has_ammo = IOS_WeaponHasAmmo( w );
				out[n].current = id == current_id;
				n++;
			}
		}
	}

	return n;
}

void IOS_WeaponSelect( int id )
{
	if( !IOS_WeaponOwned( id ) || id == current_id )
		return;

	// unknown commands go to the server, which selects by name, as the HUD does
	Cbuf_AddTextf( "%s\n", weapons[id].name );
}

// NEXT WPN's tap: the next owned weapon with ammo, after the current one
void IOS_WeaponNext( void )
{
	ios_wheel_item_t list[MAX_IOS_WEAPONS];
	int n = IOS_WeaponList( list, MAX_IOS_WEAPONS ), i, cur = -1;

	if( n <= 0 )
		return;

	for( i = 0; i < n; i++ )
	{
		if( list[i].current )
			cur = i;
	}

	for( i = 1; i <= n; i++ )
	{
		const ios_wheel_item_t *it = &list[( cur + i + n ) % n];

		if( it->has_ammo && !it->current )
		{
			IOS_WeaponSelect( it->id );
			return;
		}
	}
}

const char *IOS_WeaponDisplayName( const char *classname )
{
	static const struct { const char *cls, *name; } names[] =
	{
	{ "weapon_crowbar", "Crowbar" },
	{ "weapon_9mmhandgun", "Glock" },
	{ "weapon_glock", "Glock" },
	{ "weapon_357", ".357 Magnum" },
	{ "weapon_python", ".357 Magnum" },
	{ "weapon_9mmAR", "MP5" },
	{ "weapon_mp5", "MP5" },
	{ "weapon_shotgun", "Shotgun" },
	{ "weapon_crossbow", "Crossbow" },
	{ "weapon_rpg", "RPG" },
	{ "weapon_gauss", "Tau Cannon" },
	{ "weapon_egon", "Gluon Gun" },
	{ "weapon_hornetgun", "Hivehand" },
	{ "weapon_handgrenade", "Grenades" },
	{ "weapon_satchel", "Satchels" },
	{ "weapon_tripmine", "Tripmines" },
	{ "weapon_snark", "Snarks" },
	// Opposing Force
	{ "weapon_pipewrench", "Pipe Wrench" },
	{ "weapon_knife", "Knife" },
	{ "weapon_grapple", "Barnacle" },
	{ "weapon_eagle", "Desert Eagle" },
	{ "weapon_m249", "M249" },
	{ "weapon_sniperrifle", "Sniper Rifle" },
	{ "weapon_displacer", "Displacer" },
	{ "weapon_sporelauncher", "Spore Launcher" },
	{ "weapon_shockrifle", "Shock Roach" },
	{ "weapon_penguin", "Penguins" },
	};
	static char fallback[32];
	int i;

	for( i = 0; i < ARRAYSIZE( names ); i++ )
	{
		if( !Q_stricmp( classname, names[i].cls ))
			return names[i].name;
	}

	Q_strncpy( fallback, Q_strnicmp( classname, "weapon_", 7 ) ? classname : classname + 7, sizeof( fallback ));
	if( fallback[0] >= 'a' && fallback[0] <= 'z' )
		fallback[0] -= 'a' - 'A';
	return fallback;
}

// ---------------------------------------------------------------- icons

// HL sprite, version 2
typedef struct
{
	int ident, version, type, texFormat;
	float boundingradius;
	int width, height, numframes;
	float beamlength;
	int synctype;
} ios_spr_header_t;

enum { SPR_FMT_NORMAL, SPR_FMT_ADDITIVE, SPR_FMT_INDEXALPHA, SPR_FMT_ALPHTEST };

// cuts x, y, w, h out of the sprite's first frame, as premultiplied RGBA
static byte *IOS_LoadSpriteRect( const char *path, int x, int y, int w, int h )
{
	fs_offset_t size;
	byte *file = FS_LoadFile( path, &size, false ), *out = NULL;
	const byte *p, *end, *pal;
	ios_spr_header_t hdr;
	int palcount, fw, fh, i, j;

	if( !file )
		return NULL;

	end = file + size;
	if( size < (fs_offset_t)sizeof( hdr ) + 2 )
		goto done;

	memcpy( &hdr, file, sizeof( hdr ));
	if( hdr.ident != (( 'P' << 24 ) + ( 'S' << 16 ) + ( 'D' << 8 ) + 'I' ) || hdr.version != 2 )
		goto done;

	p = file + sizeof( hdr );
	palcount = p[0] | ( p[1] << 8 );
	p += 2;
	pal = p;
	p += palcount * 3;

	// the first frame: its type, origin, size, then the pixels
	if( p + 20 > end )
		goto done;

	memcpy( &fw, p + 12, 4 );
	memcpy( &fh, p + 16, 4 );
	p += 20;

	if( fw <= 0 || fh <= 0 || p + fw * fh > end || x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > fw || y + h > fh )
		goto done;

	out = Mem_Malloc( host.mempool, w * h * 4 );

	for( j = 0; j < h; j++ )
	{
		for( i = 0; i < w; i++ )
		{
			int index = p[( y + j ) * fw + x + i];
			byte *o = out + ( j * w + i ) * 4;
			int r = 0, g = 0, b = 0, a = 255;

			if( index < palcount )
			{
				r = pal[index * 3 + 0];
				g = pal[index * 3 + 1];
				b = pal[index * 3 + 2];
			}

			switch( hdr.texFormat )
			{
			case SPR_FMT_ADDITIVE:
				// drawn added to the screen and tinted with the HUD's
				// orange (255 160 0): black is see-through
				a = Q_max( r, Q_max( g, b ));
				r = a;
				g = a * 160 / 255;
				b = 0;
				break;
			case SPR_FMT_INDEXALPHA:
				a = index;
				if( palcount >= 256 )
				{
					r = pal[255 * 3 + 0] * a / 255;
					g = pal[255 * 3 + 1] * a / 255;
					b = pal[255 * 3 + 2] * a / 255;
				}
				break;
			case SPR_FMT_ALPHTEST:
				if( index == 255 )
					r = g = b = a = 0;
				break;
			}

			o[0] = r;
			o[1] = g;
			o[2] = b;
			o[3] = a;
		}
	}

done:
	Mem_Free( file );
	return out;
}

// finds an entry of a HUD sprite list (sprites/hud.txt, sprites/weapon_*.txt):
// "count", then lines of: name res sprite x y w h; the largest res up to 640
static qboolean IOS_FindHudSprite( const char *txt, const char *want, char *sprite, size_t size, int *rect )
{
	char token[64], *file, *pfile;
	int count, best_res = 0;

	pfile = file = (char *)FS_LoadFile( txt, NULL, false );
	if( !file )
		return false;

	sprite[0] = 0;
	pfile = COM_ParseFile( pfile, token, sizeof( token ));
	count = Q_atoi( token );

	while( count-- > 0 && pfile )
	{
		char name[32], spr[64];
		int res, r[4], i;

		pfile = COM_ParseFile( pfile, name, sizeof( name ));
		pfile = COM_ParseFile( pfile, token, sizeof( token ));
		res = Q_atoi( token );
		pfile = COM_ParseFile( pfile, spr, sizeof( spr ));
		for( i = 0; i < 4; i++ )
		{
			pfile = COM_ParseFile( pfile, token, sizeof( token ));
			r[i] = Q_atoi( token );
		}

		if( !Q_stricmp( name, want ) && res > best_res && res <= 640 )
		{
			best_res = res;
			Q_strncpy( sprite, spr, size );
			memcpy( rect, r, sizeof( r ));
		}
	}

	Mem_Free( file );
	return sprite[0] != 0;
}

const unsigned char *IOS_WeaponIcon( int id, int *w, int *h )
{
	ios_weapon_t *wp;
	char path[MAX_QPATH], sprite[64];
	int rect[4];

	if( id <= 0 || id >= MAX_IOS_WEAPONS || !weapons[id].known )
		return NULL;

	wp = &weapons[id];
	if( wp->icon || wp->icon_tried )
	{
		*w = wp->icon_w;
		*h = wp->icon_h;
		return wp->icon;
	}

	wp->icon_tried = true;

	// the selected-weapon picture
	Q_snprintf( path, sizeof( path ), "sprites/%s.txt", wp->name );
	if( !IOS_FindHudSprite( path, "weapon_s", sprite, sizeof( sprite ), rect ))
		return NULL;

	Q_snprintf( path, sizeof( path ), "sprites/%s.spr", sprite );
	wp->icon = IOS_LoadSpriteRect( path, rect[0], rect[1], rect[2], rect[3] );
	if( wp->icon )
	{
		wp->icon_w = rect[2];
		wp->icon_h = rect[3];
	}

	*w = wp->icon_w;
	*h = wp->icon_h;
	return wp->icon;
}

// ---------------------------------------------------------------- flashlight

typedef struct
{
	char sprite[MAX_QPATH]; // sprites/<name>.spr
	int rect[4];            // x y w h
	byte *pixels;
	qboolean found;
} ios_hud_part_t;

static ios_hud_part_t flash_parts[IOSTOUCH_FLASH_PARTS];
static char flash_game[MAX_QPATH];

static void IOS_FlashLoad( void )
{
	static const char *names[IOSTOUCH_FLASH_PARTS] = { "flash_empty", "flash_full", "flash_beam" };
	int i;

	if( !Q_stricmp( flash_game, GI->gamefolder ))
		return;

	Q_strncpy( flash_game, GI->gamefolder, sizeof( flash_game ));

	for( i = 0; i < IOSTOUCH_FLASH_PARTS; i++ )
	{
		ios_hud_part_t *part = &flash_parts[i];
		char sprite[64];

		if( part->pixels )
			Mem_Free( part->pixels );
		memset( part, 0, sizeof( *part ));

		if( !IOS_FindHudSprite( "sprites/hud.txt", names[i], sprite, sizeof( sprite ), part->rect ))
			continue;

		Q_snprintf( part->sprite, sizeof( part->sprite ), "sprites/%s.spr", sprite );
		part->pixels = IOS_LoadSpriteRect( part->sprite, part->rect[0], part->rect[1], part->rect[2], part->rect[3] );
		part->found = true;
	}
}

const unsigned char *IOS_FlashlightIcon( int part, int *w, int *h )
{
	if( part < 0 || part >= IOSTOUCH_FLASH_PARTS )
		return NULL;

	IOS_FlashLoad( );
	*w = flash_parts[part].rect[2];
	*h = flash_parts[part].rect[3];
	return flash_parts[part].pixels;
}

void IOS_FlashlightState( int *on, int *battery )
{
	*on = flash_on;
	*battery = bound( 0, flash_battery, 100 );
}

// the HUD's own flashlight is left out: the LIGHT button shows it instead
int IOS_HudHidesSprite( const char *sprite, int left, int top, int right, int bottom )
{
	int i;

	if( cls.state != ca_active || !IOS_TouchShown( ))
		return 0;

	IOS_FlashLoad( );

	for( i = 0; i < IOSTOUCH_FLASH_PARTS; i++ )
	{
		const ios_hud_part_t *part = &flash_parts[i];

		if( !part->found || Q_stricmp( sprite, part->sprite ))
			continue;

		// the battery bar is drawn as a part of flash_full
		if( left >= part->rect[0] && right <= part->rect[0] + part->rect[2]
			&& top >= part->rect[1] && bottom <= part->rect[1] + part->rect[3] )
			return 1;
	}

	return 0;
}
