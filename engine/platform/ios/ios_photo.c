/*
ios_photo.c - the iOS port's photo mode: photos, selfies, Action Freeze
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

// All in the engine, so the three game libraries stay vanilla: the camera
// is moved after the game client has set up its view (pfnCalcRefdef), the
// player's body is drawn and the weapon hidden by answering "third person",
// and the HUD is left out of clean shots. A camera shot pauses a single
// player game and turns nearby monsters to face the camera; everything is
// put back afterwards. Saving to Photos is in ios_photos.m.

#include "common.h"
#include "client.h"
#include "server.h"
#include "pm_defs.h"
#include "ios_touch.h"

#define PHOTO_MAX_PENDING 16
#define PHOTO_MAX_POSED   48

// HL units: the player is 72 tall, about 1.8 m
#define SELFIE_DIST      56.0f   // arm's length, a bit more for the frame
#define SELFIE_DIRS      16
#define SELFIE_FOV       75.0f
#define POSE_RADIUS      800.0f
#define FREEZE_MIN_DIST  16.0f
#define FREEZE_MAX_DIST  1200.0f
#define FREEZE_WALL_GAP  6.0f
#define FREEZE_ORBIT_DEG 0.3f    // per point of finger travel
#define FREEZE_MAX_PITCH 80.0f
#define PHOTO_FOV_MIN    15.0f
#define PHOTO_FOV_MAX    110.0f

typedef enum
{
	CAM_NONE,
	CAM_SELFIE,
	CAM_FREEZE,
	CAM_ORBIT,
} cam_mode_t;

typedef struct
{
	int index;
	float yaw;
} posed_t;

static struct
{
	cam_mode_t mode;
	qboolean paused_by_us;

	// the camera
	vec3_t target;     // what it looks at: the player's eyes, plus pan
	vec3_t pan;
	float yaw, pitch, dist, fov;
	float base_yaw;    // selfie: the direction found clear

	// fov: the client's, put back after each frame
	float saved_fov;
	qboolean fov_overridden;

	// captures, one per frame
	int pending[PHOTO_MAX_PENDING];
	int num_pending;
	int current;       // IOSTOUCH_PHOTO_* being taken this frame, 0 for none
	int counter;
	int burst;         // a burst's shot: a lighter flash

	posed_t posed[PHOTO_MAX_POSED];
	int num_posed;
} photo;

static qboolean IOS_PhotoSinglePlayer( void )
{
	return sv.state == ss_active && !sv.background && svs.maxclients == 1 && cls.state == ca_active;
}

int IOS_PhotoCameraAllowed( void )
{
	cl_entity_t *player = CL_GetLocalPlayer( );

	return IOS_PhotoSinglePlayer( ) && player && !cl.intermission && cl.local.health > 0;
}

static void IOS_PhotoEyes( vec3_t out )
{
	VectorAdd( cl.simorg, cl.viewheight, out );
}

// how far the camera can go from start toward dir before a wall
static float IOS_PhotoClear( const vec3_t start, const vec3_t dir, float dist )
{
	vec3_t end;
	pmtrace_t tr;

	VectorMA( start, dist + FREEZE_WALL_GAP, dir, end );
	tr = CL_TraceLine( (float *)start, end, PM_WORLD_ONLY );

	return Q_max( 0.0f, tr.fraction * ( dist + FREEZE_WALL_GAP ) - FREEZE_WALL_GAP );
}

static void IOS_PhotoPause( void )
{
	if( !sv.paused && IOS_PhotoSinglePlayer( ))
	{
		SV_TogglePause( NULL );
		photo.paused_by_us = true;
	}
}

static void IOS_PhotoUnpause( void )
{
	if( photo.paused_by_us && sv.paused && sv.state == ss_active )
		SV_TogglePause( NULL );

	photo.paused_by_us = false;
}

// nearby monsters turn to face the camera, client side only (their state on
// the server is untouched); refreshed every frame while the camera is up
static void IOS_PhotoFindPosed( void )
{
	vec3_t eyes;
	int i;

	photo.num_posed = 0;
	IOS_PhotoEyes( eyes );

	for( i = 1; i < clgame.maxEntities && photo.num_posed < PHOTO_MAX_POSED; i++ )
	{
		cl_entity_t *ent = CL_GetEntityByIndex( i );

		if( !ent || !ent->model || ent->model->type != mod_studio || ent->player )
			continue;

		if( ent->curstate.messagenum != cl.parsecount || ent->curstate.movetype != MOVETYPE_STEP )
			continue;

		if( VectorDistance( ent->origin, eyes ) > POSE_RADIUS )
			continue;

		photo.posed[photo.num_posed].index = i;
		photo.posed[photo.num_posed].yaw = ent->angles[YAW];
		photo.num_posed++;
	}
}

static void IOS_PhotoPose( const vec3_t camera )
{
	int i;

	for( i = 0; i < photo.num_posed; i++ )
	{
		cl_entity_t *ent = CL_GetEntityByIndex( photo.posed[i].index );
		vec3_t dir, angles;

		if( !ent )
			continue;

		VectorSubtract( camera, ent->origin, dir );
		VectorAngles( dir, angles );
		ent->angles[YAW] = angles[YAW];
		ent->curstate.angles[YAW] = angles[YAW];
	}
}

static void IOS_PhotoUnpose( void )
{
	int i;

	for( i = 0; i < photo.num_posed; i++ )
	{
		cl_entity_t *ent = CL_GetEntityByIndex( photo.posed[i].index );

		if( ent )
		{
			ent->angles[YAW] = photo.posed[i].yaw;
			ent->curstate.angles[YAW] = photo.posed[i].yaw;
		}
	}

	photo.num_posed = 0;
}

static void IOS_PhotoBegin( cam_mode_t mode )
{
	vec3_t eyes;

	IOS_PhotoEyes( eyes );
	photo.mode = mode;
	photo.fov = mode == CAM_FREEZE ? cl.local.scr_fov : SELFIE_FOV;
	VectorClear( photo.pan );
	VectorCopy( eyes, photo.target );
	IOS_PhotoPause( );
	IOS_PhotoFindPosed( );
}

void IOS_PhotoCameraEnd( void )
{
	if( photo.mode == CAM_NONE )
		return;

	IOS_PhotoUnpose( );
	IOS_PhotoUnpause( );
	photo.mode = CAM_NONE;
}

int IOS_PhotoCameraActive( void )
{
	return photo.mode != CAM_NONE;
}

// a selfie: the camera at arm's length in front of the player, in the
// clearest of SELFIE_DIRS directions starting from straight ahead
int IOS_PhotoSelfieBegin( void )
{
	vec3_t eyes, dir;
	float best = -1.0f;
	int i;

	if( !IOS_PhotoCameraAllowed( ))
		return 0;

	IOS_PhotoBegin( CAM_SELFIE );
	IOS_PhotoEyes( eyes );
	photo.base_yaw = cl.viewangles[YAW];

	for( i = 0; i < SELFIE_DIRS; i++ )
	{
		// ahead first, then alternately either side of it
		float offset = (( i + 1 ) / 2 ) * ( 360.0f / SELFIE_DIRS ) * (( i & 1 ) ? 1.0f : -1.0f );
		float yaw = cl.viewangles[YAW] + offset;
		float clear;
		vec3_t angles = { -10.0f, yaw, 0.0f };

		AngleVectors( angles, dir, NULL, NULL );
		clear = IOS_PhotoClear( eyes, dir, SELFIE_DIST );

		if( clear >= SELFIE_DIST - 0.5f )
		{
			photo.base_yaw = yaw;
			best = clear;
			break;
		}

		if( clear > best )
		{
			best = clear;
			photo.base_yaw = yaw;
		}
	}

	photo.yaw = photo.base_yaw;
	photo.pitch = -10.0f;
	photo.dist = Q_max( best, FREEZE_MIN_DIST );
	return 1;
}

// shot i of n of a selfie: a little to either side of the first
void IOS_PhotoSelfieShot( int i, int n )
{
	if( photo.mode != CAM_SELFIE || n <= 1 )
		return;

	photo.yaw = photo.base_yaw + ( i - ( n - 1 ) * 0.5f ) * 18.0f;
}

int IOS_PhotoFreezeBegin( void )
{
	if( !IOS_PhotoCameraAllowed( ))
		return 0;

	IOS_PhotoBegin( CAM_FREEZE );

	// behind the player and a little above, looking where they look
	photo.yaw = cl.viewangles[YAW] + 180.0f;
	photo.pitch = -15.0f;
	photo.dist = 96.0f;
	return 1;
}

// one finger orbits (points), two pan (fractions of the screen height)
// and pinch (scale > 1 zooms in)
void IOS_PhotoFreezeMove( float dx, float dy, float panx, float pany, float zoom )
{
	vec3_t angles, forward, right, up;
	float k;

	if( photo.mode != CAM_FREEZE )
		return;

	photo.yaw -= dx * FREEZE_ORBIT_DEG;
	photo.pitch = bound( -FREEZE_MAX_PITCH, photo.pitch + dy * FREEZE_ORBIT_DEG, FREEZE_MAX_PITCH );

	// pan in the camera's plane, as far as the view is wide at the target
	k = photo.dist * 2.0f * tan( DEG2RAD( photo.fov * 0.5f ));
	VectorSet( angles, -photo.pitch, photo.yaw + 180.0f, 0.0f );
	AngleVectors( angles, forward, right, up );
	VectorMA( photo.pan, -panx * k, right, photo.pan );
	VectorMA( photo.pan, pany * k, up, photo.pan );

	if( zoom > 0.0f )
		photo.fov = bound( PHOTO_FOV_MIN, photo.fov / zoom, PHOTO_FOV_MAX );
}

// the cinematic burst: shot i of n swings round the front of the player
int IOS_PhotoOrbitBegin( void )
{
	if( !IOS_PhotoCameraAllowed( ))
		return 0;

	IOS_PhotoBegin( CAM_ORBIT );
	photo.base_yaw = cl.viewangles[YAW];
	photo.pitch = -8.0f;
	photo.dist = 80.0f;
	return 1;
}

void IOS_PhotoOrbitShot( int i, int n )
{
	if( photo.mode != CAM_ORBIT )
		return;

	photo.yaw = photo.base_yaw + ( n > 1 ? ( -60.0f + 120.0f * i / ( n - 1 )) : 0.0f );
	photo.dist = 64.0f + 24.0f * ( i % 2 );
}

// ---------------------------------------------------------------- captures

void IOS_PhotoCapture( int kind, int burst )
{
	photo.burst = burst;

	if( photo.num_pending < PHOTO_MAX_PENDING )
		photo.pending[photo.num_pending++] = kind;

	if( !photo.current )
	{
		photo.current = photo.pending[0];
		memmove( photo.pending, photo.pending + 1, --photo.num_pending * sizeof( photo.pending[0] ));
	}
}

int IOS_PhotoBusy( void )
{
	return photo.current || photo.num_pending;
}

// ---------------------------------------------------------------- engine hooks

// after the game client's pfnCalcRefdef: the photo camera's view
void IOS_PhotoCalcRefdef( ref_params_t *rp )
{
	vec3_t angles, dir, camera;
	float clear;

	if( photo.mode == CAM_NONE )
		return;

	if( !IOS_PhotoCameraAllowed( ) && !photo.paused_by_us )
	{
		IOS_PhotoCameraEnd( );
		return;
	}

	IOS_PhotoEyes( photo.target );
	VectorAdd( photo.target, photo.pan, photo.target );

	// from the target out to the camera, stopped short of walls
	VectorSet( angles, photo.pitch, photo.yaw, 0.0f );
	AngleVectors( angles, dir, NULL, NULL );
	clear = IOS_PhotoClear( photo.target, dir, photo.dist );
	VectorMA( photo.target, Q_max( clear, 4.0f ), dir, camera );

	// looking back at the target
	VectorScale( dir, -1.0f, dir );
	VectorAngles( dir, angles );
	angles[PITCH] = -angles[PITCH];

	VectorCopy( camera, rp->vieworg );
	VectorCopy( angles, rp->viewangles );
	VectorClear( rp->punchangle );

	if( !photo.fov_overridden )
	{
		photo.saved_fov = cl.local.scr_fov;
		photo.fov_overridden = true;
	}
	cl.local.scr_fov = photo.fov;

	IOS_PhotoPose( camera );
}

int IOS_PhotoThirdPerson( void )
{
	return photo.mode != CAM_NONE;
}

// no HUD, console notices or overlays in camera views and clean shots
int IOS_PhotoHideHUD( void )
{
	return photo.mode != CAM_NONE || photo.current == IOSTOUCH_PHOTO_CLEAN;
}

// at the end of the frame, before it's shown: the frame's photo
void IOS_PhotoPostRender( void )
{
	if( photo.fov_overridden )
	{
		cl.local.scr_fov = photo.saved_fov;
		photo.fov_overridden = false;
	}

	if( !photo.current )
		return;

	if( cls.state == ca_active )
	{
		char name[64];
		const char *path;

		Q_snprintf( name, sizeof( name ), "iosphoto%d.bmp", photo.counter++ % 8 );

		if( ref.dllFuncs.VID_ScreenShot( name, VID_SNAPSHOT ) && ( path = FS_GetDiskPath( name, true )))
			IOSPhotos_SaveFile( path, photo.current, photo.burst );
	}

	photo.current = 0;

	if( photo.num_pending )
	{
		photo.current = photo.pending[0];
		memmove( photo.pending, photo.pending + 1, --photo.num_pending * sizeof( photo.pending[0] ));
	}
}
