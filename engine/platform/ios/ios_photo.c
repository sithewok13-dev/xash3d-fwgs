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
#include "studio.h"
#include "cl_tent.h"
#include "ios_touch.h"

#define PHOTO_MAX_PENDING 16
#define PHOTO_MAX_POSED   48

// HL units: the player is 72 tall, about 1.8 m
#define SELFIE_DIST      64.0f   // arm's length, a bit more for the frame
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
#define PHOTO_LIGHT_KEY  -7331   // the camera's flash (dynamic and entity light)
#define PHOTO_LIGHT_RADIUS 320.0f
#define FREEZE_MAX_PAN   256.0f

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
	float yaw, cur_yaw, prev_yaw; // ent->angles, curstate.angles, latched.prevangles

	// in selfies, characters near the player strike a pose of their own
	int seq, frame;               // -1: just face the camera
	int saved_seq, saved_prevseq;
	float saved_frame, saved_framerate, saved_prevframe, saved_seqtime;
	byte saved_blend, saved_prevblend;
} posed_t;

// characters this close to the player pose with them in selfies
#define NPC_POSE_RADIUS 320.0f

static struct
{
	cam_mode_t mode;
	qboolean paused_by_us;
	qboolean pause_pending;  // pause after this frame
	qboolean held_by_wheel;

	// the camera
	vec3_t target;     // what it looks at: the player's eyes, plus pan
	vec3_t pan;
	float yaw, pitch, dist, fov;
	float base_yaw;    // selfie: the direction found clear
	float swing;       // selfie: degrees between a burst's shots

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

	// the player's pose in selfies: a sequence of the player model held
	// on one frame (-1: as they stand)
	int pose_seq;
	int pose_frame;
	qboolean selfie_arm; // the pose holds the camera: the weapon hidden
	qboolean weapon_hidden;
	int saved_weaponmodel;
} photo;

// The player's weapon back in hand. Updates from the server are deltas
// from the last frame, so a weapon hidden there would stay hidden: always
// put back when a pose without it comes, and when the camera ends.
static void IOS_PhotoShowWeapon( void )
{
	cl_entity_t *player = CL_GetLocalPlayer( );

	if( !photo.weapon_hidden )
		return;

	photo.weapon_hidden = false;
	if( player )
		player->curstate.weaponmodel = photo.saved_weaponmodel;
	if( cl.frames[cl.parsecountmod].valid )
		cl.frames[cl.parsecountmod].playerstate[cl.playernum].weaponmodel = photo.saved_weaponmodel;
}

// "Holding the camera": the one-handed aims stretch an arm straight at the
// lens, and with the weapon hidden it's the arm holding the camera out
static const char *selfie_arm_poses[] = { "ref_aim_onehanded", "ref_aim_python" };
#define SELFIE_ARM_CHANCE 40 // percent of selfie shots

static void IOS_PhotoFlashOff( void );

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

// Whether a character is in the way of a selfie from camera: the camera
// inside or against its body, or its body between the camera and the
// player's face. Bodies are taken as upright cylinders from their models'
// bounds, where they stand now.
#define SELFIE_BODY_GAP 16.0f
static qboolean IOS_PhotoSelfieBlocked( const vec3_t camera, const vec3_t eyes )
{
	cl_entity_t *player = CL_GetLocalPlayer( );
	int i;

	for( i = 1; i < clgame.maxEntities; i++ )
	{
		cl_entity_t *ent = CL_GetEntityByIndex( i );
		float r, bottom, top, dx, dy, t, len2, px, py;

		if( !ent || ent == player || !ent->model || ent->model->type != mod_studio )
			continue;

		if( ent->curstate.messagenum != cl.parsecount || FBitSet( ent->curstate.effects, EF_NODRAW ))
			continue;

		r = Q_max( Q_max( fabs( ent->model->mins[0] ), fabs( ent->model->maxs[0] )),
			Q_max( fabs( ent->model->mins[1] ), fabs( ent->model->maxs[1] )));
		bottom = ent->origin[2] + ent->model->mins[2];
		top = ent->origin[2] + ent->model->maxs[2];

		if( r <= 0.0f || top <= bottom )
			continue;

		// the camera in or against the body
		dx = camera[0] - ent->origin[0];
		dy = camera[1] - ent->origin[1];
		if( dx * dx + dy * dy < ( r + SELFIE_BODY_GAP ) * ( r + SELFIE_BODY_GAP )
			&& camera[2] > bottom - SELFIE_BODY_GAP && camera[2] < top + SELFIE_BODY_GAP )
			return true;

		// the body across the line from the camera to the face (flat, then
		// the line's height there)
		px = eyes[0] - camera[0];
		py = eyes[1] - camera[1];
		len2 = px * px + py * py;
		if( len2 <= 0.0f )
			continue;

		t = bound( 0.0f, (( ent->origin[0] - camera[0] ) * px + ( ent->origin[1] - camera[1] ) * py ) / len2, 1.0f );
		dx = camera[0] + px * t - ent->origin[0];
		dy = camera[1] + py * t - ent->origin[1];

		if( t > 0.0f && t < 1.0f && dx * dx + dy * dy < r * r )
		{
			float z = camera[2] + ( eyes[2] - camera[2] ) * t;

			if( z > bottom && z < top )
				return true;
		}
	}

	return false;
}

// While paused the engine keeps the last frame's list of entities to draw
// (CL_EmitEntities), so the pause waits for the end of a frame drawn with
// the camera up: one that has the player's body in it.
static void IOS_PhotoPause( void )
{
	photo.pause_pending = true;
}

static void IOS_PhotoPauseNow( void )
{
	photo.pause_pending = false;

	if( !sv.paused && IOS_PhotoSinglePlayer( ))
	{
		SV_TogglePause( NULL );
		photo.paused_by_us = true;
	}
}

static void IOS_PhotoUnpause( void )
{
	photo.pause_pending = false;

	if( photo.paused_by_us && sv.paused && sv.state == ss_active && !photo.held_by_wheel )
		SV_TogglePause( NULL );

	photo.paused_by_us = false;
}

// the weapon wheel holds a single player game still while it's open
void IOS_HoldGame( int on )
{
	if( on )
	{
		if( !photo.held_by_wheel && !sv.paused && IOS_PhotoSinglePlayer( ))
		{
			SV_TogglePause( NULL );
			photo.held_by_wheel = true;
		}
		return;
	}

	if( !photo.held_by_wheel )
		return;

	photo.held_by_wheel = false;
	if( sv.paused && sv.state == ss_active && !photo.paused_by_us )
		SV_TogglePause( NULL );
}

// nearby monsters turn to face the camera, client side only (their state on
// the server is untouched); refreshed every frame while the camera is up
static int IOS_PhotoLevelBlend( model_t *model, int seq );
static const char *IOS_PhotoSequenceName( model_t *model, int seq );

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
		photo.posed[photo.num_posed].cur_yaw = ent->curstate.angles[YAW];
		photo.posed[photo.num_posed].prev_yaw = ent->latched.prevangles[YAW];
		photo.posed[photo.num_posed].seq = -1;
		photo.posed[photo.num_posed].saved_seq = ent->curstate.sequence;
		photo.posed[photo.num_posed].saved_frame = ent->curstate.frame;
		photo.posed[photo.num_posed].saved_framerate = ent->curstate.framerate;
		photo.posed[photo.num_posed].saved_prevseq = ent->latched.prevsequence;
		photo.posed[photo.num_posed].saved_prevframe = ent->latched.prevframe;
		photo.posed[photo.num_posed].saved_seqtime = ent->latched.sequencetime;
		photo.posed[photo.num_posed].saved_blend = ent->curstate.blending[0];
		photo.posed[photo.num_posed].saved_prevblend = ent->latched.prevblending[0];
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
		// the renderer blends monsters from latched.prevangles to curstate.angles,
		// stuck part way while paused: both, so they face the camera fully
		ent->angles[YAW] = angles[YAW];
		ent->curstate.angles[YAW] = angles[YAW];
		ent->latched.prevangles[YAW] = angles[YAW];

		// a pose of its own, held as the player's is
		if( photo.posed[i].seq >= 0 )
		{
			int blend = IOS_PhotoLevelBlend( ent->model, photo.posed[i].seq );

			ent->curstate.sequence = photo.posed[i].seq;
			ent->curstate.frame = photo.posed[i].frame;
			ent->curstate.framerate = 0.0f;
			ent->latched.prevsequence = photo.posed[i].seq;
			ent->latched.prevframe = photo.posed[i].frame;
			ent->latched.sequencetime = 0.0f;
			ent->curstate.blending[0] = blend;
			ent->latched.prevblending[0] = blend;
		}
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
			ent->curstate.angles[YAW] = photo.posed[i].cur_yaw;
			ent->latched.prevangles[YAW] = photo.posed[i].prev_yaw;
			ent->curstate.sequence = photo.posed[i].saved_seq;
			ent->curstate.frame = photo.posed[i].saved_frame;
			ent->curstate.framerate = photo.posed[i].saved_framerate;
			ent->latched.prevsequence = photo.posed[i].saved_prevseq;
			ent->latched.prevframe = photo.posed[i].saved_prevframe;
			ent->latched.sequencetime = photo.posed[i].saved_seqtime;
			ent->curstate.blending[0] = photo.posed[i].saved_blend;
			ent->latched.prevblending[0] = photo.posed[i].saved_prevblend;
		}
	}

	photo.num_posed = 0;
}

// Poses for selfies, from the animations every HL player model shares;
// those a model doesn't have are skipped
static const char *photo_poses[] =
{
	"jump", "long_jump", "longjump", "look_idle", "deep_idle",
	"ref_aim_crowbar", "ref_shoot_crowbar", "ref_aim_python", "ref_shoot_python",
	"ref_aim_shotgun", "ref_shoot_shotgun", "ref_aim_mp5", "crouch_aim_mp5",
	"ref_aim_bow", "ref_aim_crossbow", "ref_aim_rpg", "crouch_aim_rpg", "ref_aim_gauss",
	"ref_aim_egon", "ref_aim_squeak", "ref_aim_trip", "ref_aim_onehanded",
	"ref_shoot_onehanded", "crouch_aim_onehanded", "ref_aim_hive",
};

static int IOS_PhotoFindSequence( model_t *model, const char *name, int *numframes )
{
	studiohdr_t *hdr;
	mstudioseqdesc_t *seq;
	int i;

	if( !model || model->type != mod_studio || !( hdr = (studiohdr_t *)Mod_StudioExtradata( model )))
		return -1;

	seq = (mstudioseqdesc_t *)((byte *)hdr + hdr->seqindex );
	for( i = 0; i < hdr->numseq; i++ )
	{
		if( !Q_stricmp( seq[i].label, name ))
		{
			*numframes = seq[i].numframes;
			return i;
		}
	}

	return -1;
}

static const char *IOS_PhotoSequenceName( model_t *model, int seq )
{
	studiohdr_t *hdr;

	if( !model || model->type != mod_studio || !( hdr = (studiohdr_t *)Mod_StudioExtradata( model )) || seq < 0 || seq >= hdr->numseq )
		return "";

	return ((mstudioseqdesc_t *)((byte *)hdr + hdr->seqindex ))[seq].label;
}

// The up and down aim of a player model's move comes from its blend, set
// from the view's pitch while the legs run their own move: with the legs
// still for a pose, the blend that holds the head level, looking into the
// camera (0 is aiming at the floor)
static int IOS_PhotoLevelBlend( model_t *model, int seq )
{
	studiohdr_t *hdr;
	mstudioseqdesc_t *desc;
	float start, end;

	if( !model || model->type != mod_studio || !( hdr = (studiohdr_t *)Mod_StudioExtradata( model )) || seq < 0 || seq >= hdr->numseq )
		return 127;

	desc = (mstudioseqdesc_t *)((byte *)hdr + hdr->seqindex ) + seq;
	start = desc->blendstart[0];
	end = desc->blendend[0];

	if( desc->numblends <= 1 || end - start < 0.1f )
		return 127;

	return bound( 0, (int)( 255.0f * ( 0.0f - start ) / ( end - start )), 255 );
}

// a new random pose, different from the last
// any move of a model but dying or lying dead: a random pose
static int IOS_PhotoRandomSequence( model_t *model )
{
	studiohdr_t *hdr = model && model->type == mod_studio ? (studiohdr_t *)Mod_StudioExtradata( model ) : NULL;
	int tries;

	for( tries = 0; hdr && hdr->numseq > 1 && tries < 24; tries++ )
	{
		int seq = COM_RandomLong( 0, hdr->numseq - 1 );
		const char *name = IOS_PhotoSequenceName( model, seq );

		if( Q_stristr( name, "die" ) || Q_stristr( name, "death" ) || Q_stristr( name, "dead" )
			|| Q_stristr( name, "dummy" ) || Q_stristr( name, "sleep" ) || Q_stristr( name, "lying" ))
			continue;

		return seq;
	}

	return -1;
}

// the characters near the player: each a random pose of its own
static void IOS_PhotoPickNpcPoses( cl_entity_t *player )
{
	int i;

	for( i = 0; i < photo.num_posed; i++ )
	{
		cl_entity_t *ent = CL_GetEntityByIndex( photo.posed[i].index );

		photo.posed[i].seq = -1;
		if( !ent || !player || !ent->model )
			continue;

		// by the body's edge, so a big one counts from where it reaches
		if( VectorDistance( ent->origin, player->origin ) - Q_max( ent->model->maxs[0] - ent->model->mins[0],
			ent->model->maxs[1] - ent->model->mins[1] ) * 0.5f > NPC_POSE_RADIUS )
			continue;

		photo.posed[i].seq = IOS_PhotoRandomSequence( ent->model );
		photo.posed[i].frame = COM_RandomLong( 64, 192 );
		if( photo.posed[i].seq >= 0 )
			Con_Reportf( "iOS photo: %s poses %s\n", ent->model->name, IOS_PhotoSequenceName( ent->model, photo.posed[i].seq ));
	}
}

static void IOS_PhotoPickPose( void )
{
	cl_entity_t *player = CL_GetLocalPlayer( );
	int tries, numframes = 1;

	photo.pose_seq = -1;
	photo.selfie_arm = false;
	IOS_PhotoShowWeapon( );
	if( !player )
		return;

	if( photo.mode == CAM_SELFIE )
		IOS_PhotoPickNpcPoses( player );

	// sometimes holding the camera out
	if( photo.mode == CAM_SELFIE && COM_RandomLong( 1, 100 ) <= SELFIE_ARM_CHANCE )
	{
		int seq = IOS_PhotoFindSequence( player->model, selfie_arm_poses[COM_RandomLong( 0, ARRAYSIZE( selfie_arm_poses ) - 1 )], &numframes );

		if( seq >= 0 )
		{
			photo.pose_seq = seq;
			photo.pose_frame = COM_RandomLong( 0, 255 );
			photo.selfie_arm = true;
			Con_Reportf( "iOS photo: pose %s holding the camera\n", IOS_PhotoSequenceName( player->model, seq ));
			return;
		}
	}

	for( tries = 0; tries < 24; tries++ )
	{
		int seq = IOS_PhotoFindSequence( player->model, photo_poses[COM_RandomLong( 0, ARRAYSIZE( photo_poses ) - 1 )], &numframes );

		if( seq >= 0 && seq != player->curstate.sequence )
		{
			photo.pose_seq = seq;
			// somewhere in the middle of the move, where it's most a pose
			photo.pose_frame = COM_RandomLong( 64, 192 );
			Con_Reportf( "iOS photo: pose %s (%d) of %s\n", IOS_PhotoSequenceName( player->model, seq ), seq, player->model->name );
			return;
		}
	}

	// a model without those names: any of its moves but dying
	{
		studiohdr_t *hdr = player->model && player->model->type == mod_studio ? (studiohdr_t *)Mod_StudioExtradata( player->model ) : NULL;

		for( tries = 0; hdr && hdr->numseq > 1 && tries < 24; tries++ )
		{
			int seq = COM_RandomLong( 1, hdr->numseq - 1 );
			const char *name = IOS_PhotoSequenceName( player->model, seq );

			if( Q_stristr( name, "die" ) || Q_stristr( name, "death" ) || Q_stristr( name, "dead" )
				|| Q_stristr( name, "head" ) || Q_stristr( name, "gut" ) || Q_stristr( name, "dummy" ))
				continue;

			photo.pose_seq = seq;
			photo.pose_frame = COM_RandomLong( 64, 192 );
			Con_Reportf( "iOS photo: pose %s (%d) of %s, any move\n", name, seq, player->model->name );
			return;
		}
	}

	Con_Reportf( "iOS photo: no pose for %s\n", player->model ? player->model->name : "(no model)" );
}

// held while the camera is up: the HUD's renderer draws the player from
// the entity's sequence and the player state's gait (legs) sequence
static void IOS_PhotoApplyPose( const vec3_t camera )
{
	cl_entity_t *player = CL_GetLocalPlayer( );

	if( !player || photo.mode != CAM_SELFIE )
		return;

	// the whole body turns to the camera (the legs' own turning is off below)
	{
		vec3_t dir, angles;

		VectorSubtract( camera, player->origin, dir );
		VectorAngles( dir, angles );
		player->angles[PITCH] = player->curstate.angles[PITCH] = 0.0f;
		player->angles[YAW] = player->curstate.angles[YAW] = angles[YAW];
		player->latched.prevangles[YAW] = angles[YAW];
		player->curstate.gaitsequence = 0;

		if( cl.frames[cl.parsecountmod].valid )
			cl.frames[cl.parsecountmod].playerstate[cl.playernum].gaitsequence = 0;
	}

	// the head level, whatever the view's pitch was
	{
		int blend = IOS_PhotoLevelBlend( player->model, photo.pose_seq >= 0 ? photo.pose_seq : player->curstate.sequence );

		player->curstate.blending[0] = blend;
		player->latched.prevblending[0] = blend;
		player->latched.prevseqblending[0] = blend;

		if( cl.frames[cl.parsecountmod].valid )
			cl.frames[cl.parsecountmod].playerstate[cl.playernum].blending[0] = blend;
	}

	if( photo.pose_seq < 0 )
		return;

	player->curstate.sequence = photo.pose_seq;
	player->curstate.frame = photo.pose_frame;
	player->curstate.framerate = 0.0f;
	player->curstate.gaitsequence = 0;
	player->latched.prevsequence = photo.pose_seq;
	player->latched.prevframe = photo.pose_frame;
	player->latched.sequencetime = 0.0f; // no blending from the last move

	// holding the camera: no weapon in the hand (the server's next update
	// after the camera puts it back)
	if( photo.selfie_arm )
	{
		if( !photo.weapon_hidden )
		{
			photo.saved_weaponmodel = player->curstate.weaponmodel;
			photo.weapon_hidden = true;
		}
		player->curstate.weaponmodel = 0;
	}

	if( cl.frames[cl.parsecountmod].valid )
	{
		entity_state_t *ps = &cl.frames[cl.parsecountmod].playerstate[cl.playernum];
		if( photo.selfie_arm )
			ps->weaponmodel = 0;
		ps->sequence = photo.pose_seq;
		ps->frame = photo.pose_frame;
		ps->framerate = 0.0f;
		ps->gaitsequence = 0;
	}
}

static void IOS_PhotoBegin( cam_mode_t mode )
{
	vec3_t eyes;

	IOS_PhotoEyes( eyes );
	photo.mode = mode;
	photo.pose_seq = -1;
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
	IOS_PhotoShowWeapon( );
	IOS_PhotoFlashOff( );
	IOS_PhotoUnpause( );
	photo.mode = CAM_NONE;
}

int IOS_PhotoCameraActive( void )
{
	return photo.mode != CAM_NONE;
}

// A selfie with a big character (taller than a person: an alien grunt, the
// gonarch) nearby frames it behind the player: the camera on the far side,
// further back the bigger it is, low and looking up so it fits.
#define STAR_MIN_HEIGHT  96.0f
#define STAR_RANGE       900.0f
static cl_entity_t *IOS_PhotoFindStar( const vec3_t eyes )
{
	cl_entity_t *player = CL_GetLocalPlayer( ), *best = NULL;
	float best_size = 0.0f;
	int i;

	for( i = 1; i < clgame.maxEntities; i++ )
	{
		cl_entity_t *ent = CL_GetEntityByIndex( i );
		float height, r, size;

		if( !ent || ent == player || ent->player || !ent->model || ent->model->type != mod_studio )
			continue;

		if( ent->curstate.messagenum != cl.parsecount || ent->curstate.movetype != MOVETYPE_STEP || FBitSet( ent->curstate.effects, EF_NODRAW ))
			continue;

		height = ent->model->maxs[2] - ent->model->mins[2];
		r = Q_max( ent->model->maxs[0] - ent->model->mins[0], ent->model->maxs[1] - ent->model->mins[1] ) * 0.5f;
		if( height < STAR_MIN_HEIGHT || VectorDistance( ent->origin, eyes ) - r > STAR_RANGE )
			continue;

		size = height * r;
		if( size > best_size )
		{
			best_size = size;
			best = ent;
		}
	}

	return best;
}

static qboolean IOS_PhotoStarSelfie( const vec3_t eyes )
{
	cl_entity_t *star = IOS_PhotoFindStar( eyes );
	vec3_t dir, angles, camera;
	float height, want, clear;

	if( !star )
		return false;

	// from the star through the player, out to the camera
	VectorSubtract( eyes, star->origin, dir );
	dir[2] = 0.0f;
	if( VectorNormalizeLength( dir ) < 1.0f )
		return false;

	height = star->model->maxs[2] - star->model->mins[2];
	want = bound( 96.0f, 48.0f + height * 0.6f, 280.0f );

	VectorAngles( dir, angles );
	angles[PITCH] = 18.0f; // below the player's eyes, looking up
	AngleVectors( angles, dir, NULL, NULL );
	clear = IOS_PhotoClear( eyes, dir, want );

	// too little room this side: an ordinary selfie
	if( clear < 72.0f )
		return false;

	VectorMA( eyes, clear, dir, camera );
	if( IOS_PhotoSelfieBlocked( camera, eyes ))
		return false;

	photo.base_yaw = photo.yaw = angles[YAW];
	photo.pitch = angles[PITCH];
	photo.dist = clear;
	photo.swing = 6.0f;
	photo.fov = 90.0f;
	Con_Reportf( "iOS photo: selfie with %s, %.0f back\n", star->model->name, clear );
	return true;
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
	IOS_PhotoPickPose( );
	IOS_PhotoEyes( eyes );
	photo.base_yaw = cl.viewangles[YAW];
	photo.swing = 18.0f;

	if( IOS_PhotoStarSelfie( eyes ))
		return 1;

	// the first direction clear of walls and characters; failing that, the
	// one with the most room that no character blocks; failing that, the
	// one with the most room
	{
		float best_free = -1.0f, free_yaw = photo.base_yaw;

		for( i = 0; i < SELFIE_DIRS; i++ )
		{
			// ahead first, then alternately either side of it
			float offset = (( i + 1 ) / 2 ) * ( 360.0f / SELFIE_DIRS ) * (( i & 1 ) ? 1.0f : -1.0f );
			float yaw = cl.viewangles[YAW] + offset;
			float clear;
			vec3_t angles = { 0.0f, yaw, 0.0f }, camera;
			qboolean blocked;

			AngleVectors( angles, dir, NULL, NULL );
			clear = IOS_PhotoClear( eyes, dir, SELFIE_DIST );
			VectorMA( eyes, Q_max( clear, FREEZE_MIN_DIST ), dir, camera );
			blocked = IOS_PhotoSelfieBlocked( camera, eyes );

			if( !blocked && clear >= SELFIE_DIST - 0.5f )
			{
				best_free = clear;
				free_yaw = yaw;
				break;
			}

			if( !blocked && clear > best_free )
			{
				best_free = clear;
				free_yaw = yaw;
			}

			if( clear > best )
			{
				best = clear;
				photo.base_yaw = yaw;
			}
		}

		if( best_free >= 0.0f )
		{
			best = best_free;
			photo.base_yaw = free_yaw;
		}
	}

	photo.yaw = photo.base_yaw;
	photo.pitch = 0.0f; // at eye level: he looks straight into it
	photo.dist = Q_max( best, FREEZE_MIN_DIST );
	return 1;
}

// shot i of n of a selfie: a little to either side of the first
void IOS_PhotoSelfieShot( int i, int n )
{
	if( photo.mode != CAM_SELFIE || n <= 1 )
		return;

	photo.yaw = photo.base_yaw + ( i - ( n - 1 ) * 0.5f ) * photo.swing;

	// a swing that would put someone in the way stays straight on
	{
		vec3_t eyes, dir, camera, angles = { 0.0f, photo.yaw, 0.0f };

		IOS_PhotoEyes( eyes );
		AngleVectors( angles, dir, NULL, NULL );
		VectorMA( eyes, photo.dist, dir, camera );
		if( IOS_PhotoSelfieBlocked( camera, eyes ))
			photo.yaw = photo.base_yaw;
	}

	// a new pose for each shot after the first
	if( i > 0 )
		IOS_PhotoPickPose( );
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

	// pan in the camera's plane, as far as the view is tall at the target
	// (the moves are fractions of the screen's height)
	k = tan( DEG2RAD( photo.fov * 0.5f ));
	if( clgame.viewport[2] > 0 )
		k *= (float)clgame.viewport[3] / clgame.viewport[2];
	k *= photo.dist * 2.0f;
	VectorSet( angles, -photo.pitch, photo.yaw + 180.0f, 0.0f );
	AngleVectors( angles, forward, right, up );
	VectorMA( photo.pan, -panx * k, right, photo.pan );
	VectorMA( photo.pan, pany * k, up, photo.pan );

	if( VectorLength( photo.pan ) > FREEZE_MAX_PAN )
		VectorScale( photo.pan, FREEZE_MAX_PAN / VectorLength( photo.pan ), photo.pan );

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

// ---------------------------------------------------------------- the flash

// selfies and the cinematic burst light the scene from the camera, like a
// phone's flash: a dynamic light for the world and an entity light for the
// models (the player's face)
static void IOS_PhotoFlash( const vec3_t camera )
{
	dlight_t *dl;

	if( photo.mode != CAM_SELFIE && photo.mode != CAM_ORBIT )
		return;

	if(( dl = CL_AllocDlight( PHOTO_LIGHT_KEY )))
	{
		VectorCopy( camera, dl->origin );
		dl->radius = PHOTO_LIGHT_RADIUS;
		dl->color.r = 255; dl->color.g = 248; dl->color.b = 235;
		dl->die = cl.time + 1.0f;
		dl->decay = 0.0f;
	}

	if(( dl = CL_AllocElight( PHOTO_LIGHT_KEY )))
	{
		VectorCopy( camera, dl->origin );
		dl->radius = PHOTO_LIGHT_RADIUS;
		dl->color.r = 255; dl->color.g = 248; dl->color.b = 235;
		dl->die = cl.time + 1.0f;
		dl->decay = 0.0f;
	}
}

static void IOS_PhotoFlashOff( void )
{
	dlight_t *dl;

	if(( dl = CL_AllocDlight( PHOTO_LIGHT_KEY )))
		dl->die = dl->radius = 0.0f;
	if(( dl = CL_AllocElight( PHOTO_LIGHT_KEY )))
		dl->die = dl->radius = 0.0f;
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

	// the target moved by the pan, stopped short of walls
	IOS_PhotoEyes( photo.target );
	if( VectorLength( photo.pan ) > 0.1f )
	{
		vec3_t pandir;
		float len = VectorNormalizeLength2( photo.pan, pandir );
		clear = IOS_PhotoClear( photo.target, pandir, len );
		VectorMA( photo.target, clear, pandir, photo.target );
	}

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
	IOS_PhotoApplyPose( camera );
	IOS_PhotoFlash( camera );
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
	if( photo.pause_pending && photo.mode != CAM_NONE )
		IOS_PhotoPauseNow( );

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
