/*
ios_touch.m - iOS touch controls overlay
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

// The touch controls standard shared with the OpenJKDF2 (Jedi Knight) and
// Serious Sam iOS ports: a UIKit view over SDL's, shown only in a running
// game. Move stick where the left thumb lands (walks; pushed up to the ^^
// marker it runs), drag anywhere else to look, the FIRE cluster under the
// right thumb, a top row, and MENU's tray (hold 0.45 s).
// Written for manual reference counting, like the rest of the engine's
// Objective-C; the overlay lives for the whole process.

#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreMotion/CoreMotion.h>
#import <AudioToolbox/AudioToolbox.h>
#include <SDL.h>
#include <SDL_syswm.h>
#include <os/lock.h>
#include <math.h>
#include <string.h>
#include "ios_touch.h"

// Look speed: degrees of view turn per point of finger travel (the same turn
// as the Jedi Knight port at its default mouse settings), times SENS
#define IOSTOUCH_LOOK_DEG_X 0.64f
#define IOSTOUCH_LOOK_DEG_Y 0.39f
// Stick: appears where the thumb lands in this fraction of the screen
#define IOSTOUCH_STICK_ZONE 0.42f
#define IOSTOUCH_STICK_RADIUS 60.0
#define IOSTOUCH_STICK_KNOB 24.0
#define IOSTOUCH_STICK_DEADZONE 0.30f
// The run marker ("^^"): a circle above the stick; pushed to it, the player runs
#define IOSTOUCH_RUN_R 15.0
#define IOSTOUCH_RUN_DIST 100.0
#define IOSTOUCH_RUN_MIN_DIST 76.0
#define IOSTOUCH_RUN_ON 70.0
#define IOSTOUCH_RUN_OFF 60.0
#define IOSTOUCH_RUN_CONE 30.0
#define IOSTOUCH_RUN_CONE_OFF 40.0
// Looks
#define IOSTOUCH_IDLE_ALPHA 0.65
#define IOSTOUCH_CLUSTER_GAP 30.0
#define IOSTOUCH_ARC_RADIUS 115.0
#define IOSTOUCH_TOUCH_SLOP 6.0
#define IOSTOUCH_MIN_INSET 8.0
#define IOSTOUCH_TOP_ROW 26.0
#define IOSTOUCH_TRAY_STEP 50.0
#define IOSTOUCH_TRAY_DROP 52.0
// Holds
#define IOSTOUCH_SAVE_HOLD 0.3
#define IOSTOUCH_MENU_HOLD 0.45
// The cheat: CHEAT held this long switches it; while it's on, JUMP or USE
// held still (within IOSTOUCH_CHEAT_STILL points) this long switches noclip
// or notarget, and two quick taps of JUMP end noclip ("land")
#define IOSTOUCH_CHEAT_HOLD 0.5
#define IOSTOUCH_CHEAT_STILL 10.0
#define IOSTOUCH_LAND_TAP 0.25
#define IOSTOUCH_LAND_GAP 0.35
// LEVEL: held this long it shows chapter 1, then counts on every step
#define IOSTOUCH_LEVEL_HOLD 0.5
#define IOSTOUCH_LEVEL_STEP 0.4
#define IOSTOUCH_TOAST_TIME 1.6
// CAMERA: tap = photo; held still = selfie; slid sideways = burst; slid
// down = Action Freeze; slid up = the cinematic burst
#define IOSTOUCH_CAM_HOLD 0.5
#define IOSTOUCH_CAM_SLIDE 10.0
#define IOSTOUCH_CAM_FAR 36.0
#define IOSTOUCH_BURST_STEP 0.2
#define IOSTOUCH_BURST_MAX 10
#define IOSTOUCH_SEQ_SETTLE 0.35   // a camera shot: the camera moves, then...
#define IOSTOUCH_SEQ_CAPTURE 0.12  // ...a moment later the photo
#define IOSTOUCH_SEQ_SHOW 0.9      // the last view stays this long
#define IOSTOUCH_CINEMA_SHOTS 5
// NEXT WPN: tap = next weapon; slid IOSTOUCH_WHEEL_OPEN_SLIDE = the weapon
// wheel at once, to slide to a slice and lift; held IOSTOUCH_WHEEL_HOLD =
// the wheel, to tap a slice. Picking by sliding is measured from where the
// thumb went down, pointing nowhere within IOSTOUCH_WHEEL_DEAD, the point
// trailing at most IOSTOUCH_WHEEL_LEASH behind; a slice stays picked until
// the thumb points IOSTOUCH_WHEEL_HYST degrees past it. The gap at the
// bottom (IOSTOUCH_WHEEL_GAP degrees) cancels.
#define IOSTOUCH_WHEEL_OPEN_SLIDE 10.0
#define IOSTOUCH_WHEEL_HOLD 0.3
#define IOSTOUCH_WHEEL_DEAD 14.0
#define IOSTOUCH_WHEEL_LEASH 60.0
#define IOSTOUCH_WHEEL_HYST 4.0
#define IOSTOUCH_WHEEL_GAP 50.0
#define IOSTOUCH_WHEEL_R1_MAX 200.0
#define IOSTOUCH_WHEEL_R0_FRAC 0.40
#define IOSTOUCH_WHEEL_POP 8.0
#define IOSTOUCH_WHEEL_MAX 32
#define IOSTOUCH_WHEEL_CANCEL (-2)
// Gyro
#define IOSTOUCH_GYRO_HZ 100.0
#define IOSTOUCH_GYRO_MAX_DT 0.05
#define IOSTOUCH_GYRO_MAX_FRAME 0.5
#define IOSTOUCH_GYRO_TURN_HOLD 0.35
#define IOSTOUCH_GYRO_YAW_RELAX 1.41
#define IOSTOUCH_GYRO_SMOOTH 4.0 // deg/s: slower than this is smoothed
#define IOSTOUCH_GYRO_SMOOTH_N 12
#define IOSTOUCH_GYRO_SOFT 1.5 // deg/s: the soft dead zone

#define IOSTOUCH_MAX_TOUCHES 10
#define IOSTOUCH_MAX_ACTIONS 16
#define BIT_CMD( c ) ( 1U << ( c ))
#define IOSTOUCH_COUNT( a ) ( sizeof( a ) / sizeof(( a )[0] ))

// settings, the same keys as the other ports where the setting is the same
#define KEY_GYRO_MODE @"iosTouchGyroMode"
#define KEY_GYRO_LAST @"iosTouchGyroLastMode"
#define KEY_GYRO_SENS @"iosTouchGyroSens"
#define KEY_LOOK_SENS @"iosTouchLookSens"
#define KEY_SHOW_FPS  @"iosTouchShowFps"
#define KEY_SHOW_TAPS @"iosTouchShowTaps"
#define KEY_SWAPPED   @"iosTouchSwapped"
#define KEY_SHOW_CHEAT @"iosTouchShowCheat"
#define KEY_SHOW_CAMERA @"iosTouchShowCamera"
#define KEY_CAMERA_KINDS @"iosTouchCameraKinds"
#define KEY_SELFIES   @"iosTouchSelfieShots"
#define KEY_FREEZE    @"iosTouchFreeze"

enum { GYRO_OFF, GYRO_TOUCH, GYRO_ALWAYS, GYRO_NUM_MODES };
static const float gyro_sens[] = { 1.0f, 1.5f, 2.0f, 3.0f };
static const float look_sens[] = { 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f };

typedef enum
{
	BTN_FIRE,
	BTN_ALT,
	BTN_DUCK,
	BTN_USE,
	BTN_JUMP,
	BTN_RELOAD,
	BTN_NEXTWPN,
	BTN_FLASH,
	BTN_QSAVE,
	BTN_QLOAD,
	BTN_MENU,
	BTN_CHEAT,
	BTN_CAMERA,
	BTN_FREEZE_X,
	BTN_TRAY_GYRO,
	BTN_TRAY_SENS,
	BTN_TRAY_FPS,
	BTN_TRAY_TAPS,
	BTN_TRAY_CAM,
	BTN_TRAY_CHEAT,
	BTN_TRAY_LEVEL,
	BTN_TRAY_CTRL,
	BTN_TRAY_KEYS,
	BTN_GYRO_MODE,
	BTN_GYRO_SENS,
	BTN_CAM_CLEAN,
	BTN_CAM_HUD,
	BTN_CAM_BTNS,
	BTN_CAM_SELFIES,
	BTN_CAM_FREEZE,
	BTN_COUNT
} button_id_t;

typedef enum
{
	KIND_HOLD,     // holds a command while down
	KIND_TAP,      // runs an action when tapped
	KIND_HOLDACT,  // runs an action after a hold, with a ring
	KIND_MENU,     // tap: Escape, hold: tray
	KIND_TRAY,     // a tray or option row button
	KIND_CHEAT,    // held: the cheat on or off
	KIND_LEVEL,    // held: counts the chapters, lifted: goes there
	KIND_CAMERA,   // the photo mode's gestures
	KIND_WHEEL,    // tap: next weapon, slide or hold: the weapon wheel
} button_kind_t;

enum { ROW_MAIN, ROW_TRAY, ROW_GYRO, ROW_CAM, ROW_FREEZE };

typedef struct
{
	const char *label;
	button_kind_t kind;
	int arg;       // IOSTOUCH_CMD_* or IOSTOUCH_ACT_*
	CGFloat radius;
	int look;      // a drag that starts on it also looks
	int row;
	CGFloat hold;  // seconds, for holds
} button_def_t;

static const button_def_t buttons[BTN_COUNT] =
{
[BTN_FIRE]      = { "FIRE",         KIND_HOLD,    IOSTOUCH_CMD_ATTACK,    42, 1, ROW_MAIN },
[BTN_ALT]       = { "ALT",          KIND_HOLD,    IOSTOUCH_CMD_ATTACK2,   28, 1, ROW_MAIN },
[BTN_DUCK]      = { "DUCK",         KIND_HOLD,    IOSTOUCH_CMD_DUCK,      29, 1, ROW_MAIN },
[BTN_USE]       = { "USE",          KIND_HOLD,    IOSTOUCH_CMD_USE,       29, 1, ROW_MAIN },
[BTN_JUMP]      = { "JUMP",         KIND_HOLD,    IOSTOUCH_CMD_JUMP,      31, 1, ROW_MAIN },
[BTN_RELOAD]    = { "RELOAD",       KIND_HOLD,    IOSTOUCH_CMD_RELOAD,    28, 1, ROW_MAIN },
[BTN_NEXTWPN]   = { "NEXT\nWPN",    KIND_WHEEL,   IOSTOUCH_ACT_NEXTWEAPON, 22, 0, ROW_MAIN, IOSTOUCH_WHEEL_HOLD },
[BTN_FLASH]     = { "LIGHT",        KIND_TAP,     IOSTOUCH_ACT_FLASHLIGHT, 22, 0, ROW_MAIN },
[BTN_QSAVE]     = { "QUICK\nSAVE",  KIND_HOLDACT, IOSTOUCH_ACT_QUICKSAVE, 22, 0, ROW_MAIN, IOSTOUCH_SAVE_HOLD },
[BTN_QLOAD]     = { "QUICK\nLOAD",  KIND_HOLDACT, IOSTOUCH_ACT_QUICKLOAD, 22, 0, ROW_MAIN, IOSTOUCH_SAVE_HOLD },
[BTN_MENU]      = { "MENU",         KIND_MENU,    IOSTOUCH_ACT_ESCAPE,    22, 0, ROW_MAIN, IOSTOUCH_MENU_HOLD },
[BTN_CHEAT]     = { "\u03BB",      KIND_CHEAT,   0,                      22, 0, ROW_MAIN, IOSTOUCH_CHEAT_HOLD },
[BTN_CAMERA]    = { "",             KIND_CAMERA,  0,                      22, 0, ROW_MAIN, IOSTOUCH_CAM_HOLD },
[BTN_FREEZE_X]  = { "X",            KIND_TAP,     0,                      22, 0, ROW_FREEZE },
[BTN_TRAY_GYRO] = { "GYRO",         KIND_TRAY,    0,                      20, 0, ROW_TRAY, IOSTOUCH_MENU_HOLD },
[BTN_TRAY_SENS] = { "SENS",         KIND_TRAY,    0,                      20, 0, ROW_TRAY, IOSTOUCH_MENU_HOLD },
[BTN_TRAY_FPS]  = { "FPS",          KIND_TRAY,    0,                      20, 0, ROW_TRAY },
[BTN_TRAY_TAPS] = { "TAPS",         KIND_TRAY,    0,                      20, 0, ROW_TRAY },
[BTN_TRAY_CAM]  = { "CAMERA",       KIND_TRAY,    0,                      20, 0, ROW_TRAY, IOSTOUCH_MENU_HOLD },
[BTN_TRAY_CHEAT] = { "CHEAT",       KIND_TRAY,    0,                      20, 0, ROW_TRAY },
[BTN_TRAY_LEVEL] = { "LEVEL",       KIND_LEVEL,   0,                      20, 0, ROW_TRAY, IOSTOUCH_LEVEL_HOLD },
[BTN_TRAY_CTRL] = { "CONTROLS",     KIND_TRAY,    0,                      20, 0, ROW_TRAY },
[BTN_TRAY_KEYS] = { "KEYS",         KIND_TRAY,    IOSTOUCH_ACT_CONSOLE,   20, 0, ROW_TRAY },
[BTN_GYRO_MODE] = { "MODE",         KIND_TRAY,    0,                      20, 0, ROW_GYRO },
[BTN_GYRO_SENS] = { "SENS",         KIND_TRAY,    0,                      20, 0, ROW_GYRO },
[BTN_CAM_CLEAN] = { "CLEAN",        KIND_TRAY,    IOSTOUCH_PHOTO_CLEAN,   20, 0, ROW_CAM },
[BTN_CAM_HUD]   = { "HUD",          KIND_TRAY,    IOSTOUCH_PHOTO_HUD,     20, 0, ROW_CAM },
[BTN_CAM_BTNS]  = { "HUD+\nBTNS",   KIND_TRAY,    IOSTOUCH_PHOTO_HUDBTNS, 20, 0, ROW_CAM },
[BTN_CAM_SELFIES] = { "SELFIES",    KIND_TRAY,    0,                      20, 0, ROW_CAM },
[BTN_CAM_FREEZE] = { "FREEZE",      KIND_TRAY,    0,                      20, 0, ROW_CAM },
};

typedef enum { ROLE_NONE, ROLE_STICK, ROLE_LOOK, ROLE_BUTTON, ROLE_IGNORE } role_t;

typedef struct
{
	UITouch *touch;
	role_t role;
	int button;
	CGPoint start, last;
	CFTimeInterval t0;
	int done;     // a hold already fired
	int off;      // slid off its button: no tap, no hold
	CGFloat moved; // farthest it has been from where it went down
} slot_t;

// shared with the motion queue
static os_unfair_lock gyro_lock = OS_UNFAIR_LOCK_INIT;
static double gyro_yaw, gyro_pitch, gyro_last_t, gyro_side_q;
static double gyro_smooth[IOSTOUCH_GYRO_SMOOTH_N][2];
static int gyro_smooth_next;

// main thread state
static int gyro_mode = GYRO_OFF, gyro_last_mode = GYRO_TOUCH, gyro_sens_i = 1;
#define LOOK_SENS_DEFAULT 2 // 1x
static int look_sens_i = LOOK_SENS_DEFAULT;
static int show_fps, show_taps, swapped, show_cheat, cheat_on;
static int level_counting, level_index;
static int show_camera = 1, camera_kinds = IOSTOUCH_PHOTO_CLEAN, selfie_shots = 3, freeze_on = 1, cam_row_open;

// the camera: a burst while CAMERA is held, a selfie or cinematic sequence,
// or Action Freeze
enum { SEQ_NONE, SEQ_SELFIE, SEQ_CINEMA };
static int burst_on, burst_count;
static CFTimeInterval burst_next;
static int seq, seq_i, seq_n, seq_phase;
static CFTimeInterval seq_next;
static int freezing;
static int overlay_shown; // in a running game, the controls up

// the weapon wheel
static ios_wheel_item_t wheel_items[IOSTOUCH_WHEEL_MAX];
static int wheel_n, wheel_open, wheel_slide, wheel_pick = -1;
static CGPoint wheel_center, wheel_ref;
static CGFloat wheel_r0, wheel_r1;
static CFTimeInterval level_next, toast_until, jump_tap_end;
static int gyro_running, gyro_was_ok, gyro_last_side;
static CFTimeInterval gyro_turned_round, gyro_last_frame;
static CMMotionManager *motion;
static NSOperationQueue *motion_queue;

static float look_yaw, look_pitch;
static unsigned int held_cmds;
static int actions[IOSTOUCH_MAX_ACTIONS], actions_head, actions_tail;
static int tray_open, gyro_row_open;

static void QueueAction( int action )
{
	int next = ( actions_tail + 1 ) % IOSTOUCH_MAX_ACTIONS;

	if( next == actions_head )
		return;

	actions[actions_tail] = action;
	actions_tail = next;
}

static void Haptic( int selection )
{
	if( selection )
	{
		static UISelectionFeedbackGenerator *sel;
		if( !sel )
			sel = [[UISelectionFeedbackGenerator alloc] init];
		[sel selectionChanged];
	}
	else
	{
		static UIImpactFeedbackGenerator *imp;
		if( !imp )
			imp = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
		[imp impactOccurred];
	}
}

// ---------------------------------------------------------------- gyro aiming
// From the Jedi Knight port: turning is taken about world up ("player space")
// while the screen faces up, smoothed only where slow, with a soft dead zone.

static void GyroSample( double wx, double wy, double wz, double gx, double gy, double gz, NSTimeInterval t )
{
	os_unfair_lock_lock( &gyro_lock );
	double dt = gyro_last_t > 0.0 ? t - gyro_last_t : 0.0;
	double s = gyro_side_q;
	double gn = sqrt( gx * gx + gy * gy + gz * gz );

	gyro_last_t = t;

	if( s != 0.0 && dt > 0.0 && dt <= IOSTOUCH_GYRO_MAX_DT && gn > 0.1 )
	{
		double rx = s * wy, ry = -s * wx, rz = wz;
		double ux = -s * gy / gn, uy = s * gx / gn, uz = -gz / gn;
		double tilt = sqrt( ux * ux + uy * uy );

		if( tilt < 0.5 || uy > -0.5 * tilt )
		{
			double yaw = ry, pitch = rx;

			if( uz >= 0.0 && ( tilt < 0.5 || uy > 0.5 * tilt ))
			{
				double mag = sqrt( ry * ry + rz * rz );
				yaw = uy * ry + uz * rz;
				yaw = copysign( fmin( fabs( yaw ) * IOSTOUCH_GYRO_YAW_RELAX, mag ), yaw );
			}

			yaw *= 180.0 / M_PI;
			pitch *= 180.0 / M_PI;

			double m = sqrt( yaw * yaw + pitch * pitch );
			double direct = ( m - IOSTOUCH_GYRO_SMOOTH * 0.5 ) / ( IOSTOUCH_GYRO_SMOOTH * 0.5 );
			direct = direct < 0.0 ? 0.0 : ( direct > 1.0 ? 1.0 : direct );
			gyro_smooth[gyro_smooth_next][0] = yaw * ( 1.0 - direct );
			gyro_smooth[gyro_smooth_next][1] = pitch * ( 1.0 - direct );
			gyro_smooth_next = ( gyro_smooth_next + 1 ) % IOSTOUCH_GYRO_SMOOTH_N;

			double sum_yaw = 0.0, sum_pitch = 0.0;
			for( int i = 0; i < IOSTOUCH_GYRO_SMOOTH_N; i++ )
			{
				sum_yaw += gyro_smooth[i][0];
				sum_pitch += gyro_smooth[i][1];
			}
			yaw = yaw * direct + sum_yaw / IOSTOUCH_GYRO_SMOOTH_N;
			pitch = pitch * direct + sum_pitch / IOSTOUCH_GYRO_SMOOTH_N;

			m = sqrt( yaw * yaw + pitch * pitch );
			if( m < IOSTOUCH_GYRO_SOFT )
			{
				yaw *= m / IOSTOUCH_GYRO_SOFT;
				pitch *= m / IOSTOUCH_GYRO_SOFT;
			}

			gyro_yaw += yaw * dt;
			gyro_pitch += pitch * dt;
		}
	}
	os_unfair_lock_unlock( &gyro_lock );
}

static void GyroRun( int run )
{
	run = run != 0;
	if( run == gyro_running )
		return;

	gyro_running = run;

	if( !run )
	{
		[motion stopDeviceMotionUpdates];
		return;
	}

	os_unfair_lock_lock( &gyro_lock );
	gyro_last_t = 0.0;
	gyro_yaw = gyro_pitch = 0.0;
	memset( gyro_smooth, 0, sizeof( gyro_smooth ));
	os_unfair_lock_unlock( &gyro_lock );

	motion.deviceMotionUpdateInterval = 1.0 / IOSTOUCH_GYRO_HZ;
	[motion startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
		toQueue:motion_queue withHandler:^( CMDeviceMotion *dm, NSError *err ) {
		if( !dm || err )
			return;
		GyroSample( dm.rotationRate.x, dm.rotationRate.y, dm.rotationRate.z,
			dm.gravity.x, dm.gravity.y, dm.gravity.z, dm.timestamp );
	}];
}

static void LoadSettings( void )
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

	if( [d objectForKey:KEY_GYRO_MODE] )
	{
		NSInteger m = [d integerForKey:KEY_GYRO_MODE];
		gyro_mode = ( m >= 0 && m < GYRO_NUM_MODES ) ? (int)m : GYRO_OFF;
	}

	if( [d objectForKey:KEY_GYRO_LAST] )
		gyro_last_mode = [d integerForKey:KEY_GYRO_LAST] == GYRO_ALWAYS ? GYRO_ALWAYS : GYRO_TOUCH;

	if( gyro_mode != GYRO_OFF )
		gyro_last_mode = gyro_mode;

	if( [d objectForKey:KEY_GYRO_SENS] )
	{
		float k = [d floatForKey:KEY_GYRO_SENS];
		for( int i = 0; i < (int)IOSTOUCH_COUNT( gyro_sens ); i++ )
		{
			if( fabsf( gyro_sens[i] - k ) < fabsf( gyro_sens[gyro_sens_i] - k ))
				gyro_sens_i = i;
		}
	}

	if( [d objectForKey:KEY_LOOK_SENS] )
	{
		float k = [d floatForKey:KEY_LOOK_SENS];
		for( int i = 0; i < (int)IOSTOUCH_COUNT( look_sens ); i++ )
		{
			if( fabsf( look_sens[i] - k ) < fabsf( look_sens[look_sens_i] - k ))
				look_sens_i = i;
		}
	}

	show_fps = (int)[d boolForKey:KEY_SHOW_FPS];
	show_taps = (int)[d boolForKey:KEY_SHOW_TAPS];
	show_cheat = (int)[d boolForKey:KEY_SHOW_CHEAT];

	if( [d objectForKey:KEY_SHOW_CAMERA] )
		show_camera = (int)[d boolForKey:KEY_SHOW_CAMERA];
	if( [d objectForKey:KEY_CAMERA_KINDS] )
		camera_kinds = (int)[d integerForKey:KEY_CAMERA_KINDS] & 7;
	if( !camera_kinds )
		camera_kinds = IOSTOUCH_PHOTO_CLEAN;
	if( [d objectForKey:KEY_SELFIES] )
	{
		NSInteger n = [d integerForKey:KEY_SELFIES];
		selfie_shots = n == 1 || n == 5 ? (int)n : 3;
	}
	if( [d objectForKey:KEY_FREEZE] )
		freeze_on = (int)[d boolForKey:KEY_FREEZE];
	swapped = (int)[d boolForKey:KEY_SWAPPED];
}

static void SaveGyro( void )
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setInteger:gyro_mode forKey:KEY_GYRO_MODE];
	[d setInteger:gyro_last_mode forKey:KEY_GYRO_LAST];
	[d setFloat:gyro_sens[gyro_sens_i] forKey:KEY_GYRO_SENS];
}

// ---------------------------------------------------------------- the overlay

@interface IOSTouchOverlay : UIView
{
@public
	UIView *btn_views[BTN_COUNT];
	UILabel *btn_labels[BTN_COUNT];
	CAShapeLayer *btn_rings[BTN_COUNT];
	CGPoint btn_pos[BTN_COUNT];
	int btn_shown[BTN_COUNT];
	int btn_lit[BTN_COUNT];      // a switch that is on

	UIView *stick_ring, *stick_knob, *run_marker;
	CAShapeLayer *run_chevrons, *run_link;
	int run_lit;                 // what run_marker shows (-1: not yet set)
	UILabel *cheat_tags[2];      // under JUMP and USE while the cheat is on
	UILabel *toast;
	UIView *flash;
	UIView *wheel;               // the weapon wheel, made each time it opens
	UILabel *wheel_title, *wheel_ammo;
	UIImageView *wheel_big;              // the picked weapon's icon, in the middle
	CAShapeLayer *wheel_slices[IOSTOUCH_WHEEL_MAX];
	UIView *wheel_cells[IOSTOUCH_WHEEL_MAX];
	NSMutableDictionary *icon_cache;

	// LIGHT: the game's flashlight picture, filled to the battery, the
	// beam lit while it's on
	UIView *flash_group;
	UIImageView *flash_empty, *flash_full, *flash_beam;
	CAShapeLayer *flash_mask;
	int flash_shown_on, flash_shown_bat;
	CGPoint stick_center;
	CGFloat run_dist;            // 0: no marker
	int running;

	slot_t slots[IOSTOUCH_MAX_TOUCHES];
	CGRect laid_out_for;
	UIEdgeInsets laid_out_insets;
	int laid_out_swapped;
}
- (UIEdgeInsets)insets;
- (void)layoutButtons;
- (void)releaseAll;
- (void)updateHolds;
- (int)gyroThumbDown;
- (void)showToast:(NSString *)text;
- (void)setCheat:(int)on;
- (void)updateShown;
- (void)updateLabels;
- (void)flash:(int)burst;
- (void)endCamera;
- (void)closeWheel:(int)select;
@end

static UIView *MakeCircle( CGFloat radius, CGFloat alpha )
{
	UIView *v = [[UIView alloc] initWithFrame:CGRectMake( 0, 0, radius * 2, radius * 2 )];
	v.backgroundColor = [UIColor colorWithWhite:1.0 alpha:alpha];
	v.layer.cornerRadius = radius;
	v.layer.borderWidth = 1.5;
	v.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
	v.userInteractionEnabled = NO;
	return v;
}

static CGFloat FontSize( const char *label, CGFloat radius )
{
	if( strchr( label, '\n' ))
		return radius >= 28 ? 10 : 9;
	if( strlen( label ) > 6 )
		return 8;
	return radius >= 40 ? 16 : ( radius >= 25 ? 13 : 10 );
}

static CAShapeLayer *MakeHoldRing( CGFloat r )
{
	CAShapeLayer *ring = [CAShapeLayer layer];
	ring.frame = CGRectMake( 0, 0, r * 2, r * 2 );
	ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake( r, r ) radius:r - 2.5
		startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES].CGPath;
	ring.fillColor = [UIColor clearColor].CGColor;
	ring.strokeColor = [UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.95].CGColor;
	ring.lineWidth = 3.0;
	ring.strokeEnd = 0.0;
	return ring;
}

static CGFloat Dist( CGPoint a, CGPoint b )
{
	return hypot( a.x - b.x, a.y - b.y );
}

@implementation IOSTouchOverlay

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if( !self )
		return nil;

	self.multipleTouchEnabled = YES;
	self.backgroundColor = [UIColor clearColor];
	self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

	for( int i = 0; i < BTN_COUNT; i++ )
	{
		const button_def_t *b = &buttons[i];
		UIView *v = MakeCircle( b->radius, 0.15 );
		UILabel *l = [[UILabel alloc] initWithFrame:v.bounds];

		l.text = @( b->label );
		l.numberOfLines = 2;
		l.textAlignment = NSTextAlignmentCenter;
		l.textColor = [UIColor whiteColor];
		l.font = [UIFont boldSystemFontOfSize:FontSize( b->label, b->radius )];
		l.adjustsFontSizeToFitWidth = YES;
		l.minimumScaleFactor = 0.6;
		[v addSubview:l];

		if( b->kind == KIND_HOLDACT || b->kind == KIND_MENU || b->hold > 0 || i == BTN_JUMP || i == BTN_USE )
		{
			btn_rings[i] = [MakeHoldRing( b->radius ) retain];
			[v.layer addSublayer:btn_rings[i]];
		}

		v.alpha = IOSTOUCH_IDLE_ALPHA;
		btn_views[i] = v;
		btn_labels[i] = l;
		[self addSubview:v];
	}

	for( int i = 0; i < 2; i++ )
	{
		UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake( 0, 0, 70, 12 )];
		l.text = i ? @"NOTARGET" : @"NOCLIP";
		l.textAlignment = NSTextAlignmentCenter;
		l.font = [UIFont boldSystemFontOfSize:8];
		l.textColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.25 alpha:0.9];
		l.hidden = YES;
		cheat_tags[i] = l;
		[self addSubview:l];
	}

	toast = [[UILabel alloc] init];
	toast.textAlignment = NSTextAlignmentCenter;
	toast.textColor = [UIColor whiteColor];
	toast.font = [UIFont boldSystemFontOfSize:14];
	toast.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
	toast.layer.cornerRadius = 8;
	toast.layer.masksToBounds = YES;
	toast.hidden = YES;
	[self addSubview:toast];

	// PHOTO: a camera; CHEAT: the lambda, big
	if( @available( iOS 13.0, * ))
	{
		UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold];
		UIImageView *cam = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"camera.fill" withConfiguration:cfg]];
		cam.tintColor = [UIColor whiteColor];
		cam.contentMode = UIViewContentModeCenter;
		cam.frame = btn_views[BTN_CAMERA].bounds;
		[btn_views[BTN_CAMERA] addSubview:cam];
	}
	else btn_labels[BTN_CAMERA].text = @"PHOTO";

	btn_labels[BTN_CHEAT].font = [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy];
	icon_cache = [[NSMutableDictionary alloc] init];

	flash = [[UIView alloc] initWithFrame:self.bounds];
	flash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	flash.backgroundColor = [UIColor whiteColor];
	flash.userInteractionEnabled = NO;
	flash.alpha = 0.0;
	[self addSubview:flash];

	stick_ring = MakeCircle( IOSTOUCH_STICK_RADIUS, 0.08 );
	stick_knob = MakeCircle( IOSTOUCH_STICK_KNOB, 0.30 );
	// The run marker, as in the Jedi Knight port: a small circle in the
	// buttons' style with two chevrons in it, joined to the stick's ring by
	// a line; the knob sits on it while running and it lights up blue
	{
		const CGFloat rr = IOSTOUCH_RUN_R;
		UIBezierPath *chev = [UIBezierPath bezierPath];

		run_marker = MakeCircle( rr, 0.0 );
		run_chevrons = [[CAShapeLayer layer] retain];
		run_chevrons.frame = CGRectMake( 0, 0, rr * 2, rr * 2 );
		for( int i = 0; i < 2; i++ )
		{
			// two chevrons, 12 pt wide, 5.5 pt apart, centred
			CGFloat tip = rr - 5.5 + 5.5 * i;
			[chev moveToPoint:CGPointMake( rr - 6.0, tip + 5.0 )];
			[chev addLineToPoint:CGPointMake( rr, tip )];
			[chev addLineToPoint:CGPointMake( rr + 6.0, tip + 5.0 )];
		}
		run_chevrons.path = chev.CGPath;
		run_chevrons.lineWidth = 2.0;
		run_chevrons.lineCap = kCALineCapRound;
		run_chevrons.lineJoin = kCALineJoinRound;
		run_chevrons.fillColor = [UIColor clearColor].CGColor;
		[run_marker.layer addSublayer:run_chevrons];
	}

	run_link = [[CAShapeLayer layer] retain];
	run_link.lineWidth = 1.5;
	run_link.lineCap = kCALineCapRound;
	run_link.fillColor = [UIColor clearColor].CGColor;
	[self.layer addSublayer:run_link];
	run_lit = -1;

	[self addSubview:stick_ring];
	[self addSubview:run_marker];
	[self addSubview:stick_knob];
	stick_ring.hidden = stick_knob.hidden = run_marker.hidden = YES;
	run_link.hidden = YES;
	[self setRunLit:0];

	return self;
}

- (UIEdgeInsets)insets
{
	UIEdgeInsets in = UIEdgeInsetsZero;

	if( @available( iOS 11.0, * ))
		in = self.safeAreaInsets;

	in.left = MAX( in.left, IOSTOUCH_MIN_INSET );
	in.right = MAX( in.right, IOSTOUCH_MIN_INSET );
	in.top = MAX( in.top, IOSTOUCH_MIN_INSET );
	in.bottom = MAX( in.bottom, IOSTOUCH_MIN_INSET );
	return in;
}

- (CGFloat)topRowY
{
	return [self insets].top + IOSTOUCH_TOP_ROW;
}

- (void)place:(int)i at:(CGPoint)p
{
	btn_pos[i] = p;
	btn_views[i].center = p;
}

- (void)updateLabels
{
	static const char *modes[GYRO_NUM_MODES] = { "OFF", "TOUCH", "ALWAYS" };

	btn_labels[BTN_TRAY_GYRO].text = [NSString stringWithFormat:@"GYRO\n%s", modes[gyro_mode]];
	btn_labels[BTN_TRAY_SENS].text = [NSString stringWithFormat:@"SENS\n%gx", look_sens[look_sens_i]];
	btn_labels[BTN_TRAY_CTRL].text = swapped ? @"CTRL\nSWAP" : @"CTRL\nNORMAL";
	btn_labels[BTN_GYRO_MODE].text = [NSString stringWithFormat:@"MODE\n%s", modes[gyro_last_mode]];
	btn_labels[BTN_GYRO_SENS].text = [NSString stringWithFormat:@"GYRO\n%gx", gyro_sens[gyro_sens_i]];

	btn_lit[BTN_TRAY_GYRO] = gyro_mode != GYRO_OFF;
	btn_lit[BTN_TRAY_FPS] = show_fps;
	btn_lit[BTN_TRAY_TAPS] = show_taps;
	btn_lit[BTN_TRAY_CTRL] = swapped;
	btn_lit[BTN_TRAY_CHEAT] = show_cheat;
	btn_lit[BTN_TRAY_CAM] = show_camera;
	btn_lit[BTN_CAM_CLEAN] = ( camera_kinds & IOSTOUCH_PHOTO_CLEAN ) != 0;
	btn_lit[BTN_CAM_HUD] = ( camera_kinds & IOSTOUCH_PHOTO_HUD ) != 0;
	btn_lit[BTN_CAM_BTNS] = ( camera_kinds & IOSTOUCH_PHOTO_HUDBTNS ) != 0;
	btn_lit[BTN_CAM_FREEZE] = freeze_on;
	btn_labels[BTN_CAM_SELFIES].text = [NSString stringWithFormat:@"SELFIES\n%d", selfie_shots];
	btn_labels[BTN_CAM_FREEZE].text = freeze_on ? @"FREEZE\nON" : @"FREEZE\nOFF";
	btn_lit[BTN_CHEAT] = cheat_on;

	cheat_tags[0].hidden = cheat_tags[1].hidden = !cheat_on || freezing || seq != SEQ_NONE;
	cheat_tags[0].textColor = IOS_CheatNoclip( ) ? [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.3 blue:0.25 alpha:0.9];
	cheat_tags[1].textColor = IOS_CheatNotarget( ) ? [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.3 blue:0.25 alpha:0.9];

	// CHEAT: gold while the cheat is on
	btn_views[BTN_CHEAT].layer.borderColor = cheat_on ?
		[UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:1.0].CGColor : [UIColor colorWithWhite:0.6 alpha:0.6].CGColor;
	btn_labels[BTN_CHEAT].textColor = cheat_on ? [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:1.0] : [UIColor colorWithWhite:0.7 alpha:1.0];
	btn_views[BTN_CHEAT].layer.borderWidth = cheat_on ? 2.5 : 1.5;
	btn_views[BTN_CHEAT].layer.shadowColor = [UIColor colorWithRed:1.0 green:0.75 blue:0.1 alpha:1.0].CGColor;
	btn_views[BTN_CHEAT].layer.shadowRadius = 6;
	btn_views[BTN_CHEAT].layer.shadowOffset = CGSizeZero;
	btn_views[BTN_CHEAT].layer.shadowOpacity = cheat_on ? 0.9 : 0.0;

	for( int i = 0; i < BTN_COUNT; i++ )
	{
		if( i == BTN_CHEAT || ( i == BTN_FLASH && flash_group ))
			continue;

		btn_views[i].layer.borderColor = btn_lit[i] ?
			[UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.95].CGColor :
			[UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
	}
}

- (void)layoutButtons
{
	CGSize size = self.bounds.size;
	UIEdgeInsets in = [self insets];
	CGFloat right = size.width - in.right;
	CGFloat bottom = size.height - in.bottom;
	CGFloat top = [self topRowY];
	CGPoint fire;

	fire.x = right - ( in.right < 20 ? 100 : 76 );
	fire.y = bottom - 58;

	// the arc round FIRE: DUCK left, USE up-left, JUMP up
	static const int arc[] = { BTN_DUCK, BTN_USE, BTN_JUMP };
	static const CGFloat arc_deg[] = { 180, 135, 90 };

	[self place:BTN_FIRE at:fire];
	for( int i = 0; i < 3; i++ )
	{
		CGFloat a = arc_deg[i] * M_PI / 180.0;
		[self place:arc[i] at:CGPointMake( fire.x + IOSTOUCH_ARC_RADIUS * cos( a ), fire.y - IOSTOUCH_ARC_RADIUS * sin( a ))];
	}

	// ALT up and to the right of FIRE, RELOAD up and to the right of JUMP,
	// each a cluster gap clear and kept on screen
	CGFloat d = buttons[BTN_FIRE].radius + IOSTOUCH_CLUSTER_GAP + buttons[BTN_ALT].radius;
	CGPoint p = CGPointMake( fire.x + d * cos( 40 * M_PI / 180 ), fire.y - d * sin( 40 * M_PI / 180 ));
	p.x = MIN( p.x, right - buttons[BTN_ALT].radius );
	[self place:BTN_ALT at:p];

	CGPoint jump = btn_pos[BTN_JUMP];
	d = buttons[BTN_JUMP].radius + IOSTOUCH_CLUSTER_GAP + buttons[BTN_RELOAD].radius;
	p = CGPointMake( jump.x + d * cos( 30 * M_PI / 180 ), jump.y - d * sin( 30 * M_PI / 180 ));
	p.x = MIN( p.x, right - buttons[BTN_RELOAD].radius );
	p.y = MAX( p.y, top + 22 + IOSTOUCH_CLUSTER_GAP * 0.5 + buttons[BTN_RELOAD].radius );
	[self place:BTN_RELOAD at:p];

	// CONTROLS: SWAPPED mirrors the cluster to the left
	if( swapped )
	{
		static const int cluster[] = { BTN_FIRE, BTN_ALT, BTN_DUCK, BTN_USE, BTN_JUMP, BTN_RELOAD };
		for( int i = 0; i < (int)IOSTOUCH_COUNT( cluster ); i++ )
			[self place:cluster[i] at:CGPointMake( size.width - btn_pos[cluster[i]].x, btn_pos[cluster[i]].y )];
	}

	// the top row
	[self place:BTN_NEXTWPN at:CGPointMake( in.left + 24, top )];
	[self place:BTN_FLASH at:CGPointMake( in.left + 84, top )];
	[self place:BTN_QSAVE at:CGPointMake( right - 156, top )];
	[self place:BTN_QLOAD at:CGPointMake( right - 90, top )];
	[self place:BTN_MENU at:CGPointMake( right - 24, top )];
	[self place:BTN_CAMERA at:CGPointMake( size.width * 0.5, top )];
	[self place:BTN_FREEZE_X at:CGPointMake( right - 24, top )];
	// CHEAT between the middle of the top row (CAMERA's place) and QUICK SAVE
	[self place:BTN_CHEAT at:CGPointMake(( size.width * 0.5 + btn_pos[BTN_QSAVE].x ) * 0.5, top )];

	cheat_tags[0].center = CGPointMake( btn_pos[BTN_JUMP].x, btn_pos[BTN_JUMP].y + buttons[BTN_JUMP].radius + 7 );
	cheat_tags[1].center = CGPointMake( btn_pos[BTN_USE].x, btn_pos[BTN_USE].y + buttons[BTN_USE].radius + 7 );
	toast.frame = CGRectMake( 0, 0, MIN( 360, size.width - 2 * ( in.left + 140 )), 28 );
	toast.center = CGPointMake( size.width * 0.5, top + IOSTOUCH_TRAY_DROP * 2 + 10 );

	laid_out_for = self.bounds;
	laid_out_insets = in;
	laid_out_swapped = swapped;
	[self updateShown];
	[self updateLabels];
}

- (void)updateShown
{
	static const int tray[] = { BTN_TRAY_GYRO, BTN_TRAY_SENS, BTN_TRAY_FPS, BTN_TRAY_TAPS, BTN_TRAY_CAM, BTN_TRAY_CHEAT, BTN_TRAY_LEVEL, BTN_TRAY_CTRL, BTN_TRAY_KEYS };
	static const int camrow[] = { BTN_CAM_CLEAN, BTN_CAM_HUD, BTN_CAM_BTNS, BTN_CAM_SELFIES, BTN_CAM_FREEZE };
	CGFloat top = [self topRowY];
	int n = 0;

	for( int i = 0; i < BTN_COUNT; i++ )
	{
		int row = buttons[i].row;
		btn_shown[i] = row == ROW_MAIN || ( row == ROW_TRAY && tray_open ) || ( row == ROW_GYRO && tray_open && gyro_row_open )
			|| ( row == ROW_CAM && tray_open && cam_row_open );

		if( i == BTN_CAMERA && !show_camera )
			btn_shown[i] = 0;

		// a camera sequence shows nothing; Action Freeze only CAMERA and X
		if( seq != SEQ_NONE )
			btn_shown[i] = 0;
		else if( freezing )
			btn_shown[i] = i == BTN_CAMERA || i == BTN_FREEZE_X;
		else if( row == ROW_FREEZE )
			btn_shown[i] = 0;

		// no gyro on this device: no gyro buttons
		if(( i == BTN_TRAY_GYRO || row == ROW_GYRO ) && !motion.deviceMotionAvailable )
			btn_shown[i] = 0;

		if( i == BTN_CHEAT && !show_cheat )
			btn_shown[i] = 0;

		// LEVEL only while the cheat is on, in single player
		if( i == BTN_TRAY_LEVEL && ( !cheat_on || IOS_LevelCount( ) <= 0 ))
			btn_shown[i] = 0;

		btn_views[i].hidden = !btn_shown[i];
	}

	// MENU's tray, the buttons shown in it ending under MENU, and the gyro
	// options under its GYRO
	for( int i = 0; i < (int)IOSTOUCH_COUNT( tray ); i++ )
		n += btn_shown[tray[i]] || !tray_open;

	CGFloat x = btn_pos[BTN_MENU].x - ( n - 1 ) * IOSTOUCH_TRAY_STEP;
	for( int i = 0; i < (int)IOSTOUCH_COUNT( tray ); i++ )
	{
		if( tray_open && !btn_shown[tray[i]] )
			continue;

		[self place:tray[i] at:CGPointMake( x, top + IOSTOUCH_TRAY_DROP )];
		x += IOSTOUCH_TRAY_STEP;
	}

	// the camera options, ending under the tray's CAMERA
	x = btn_pos[BTN_TRAY_CAM].x - ( IOSTOUCH_COUNT( camrow ) - 1 ) * IOSTOUCH_TRAY_STEP;
	for( int i = 0; i < (int)IOSTOUCH_COUNT( camrow ); i++ )
		[self place:camrow[i] at:CGPointMake( MAX( x + i * IOSTOUCH_TRAY_STEP, [self insets].left + 24 + i * IOSTOUCH_TRAY_STEP ), top + 2 * IOSTOUCH_TRAY_DROP )];

	[self place:BTN_GYRO_MODE at:CGPointMake( btn_pos[BTN_TRAY_GYRO].x, top + 2 * IOSTOUCH_TRAY_DROP )];
	[self place:BTN_GYRO_SENS at:CGPointMake( btn_pos[BTN_TRAY_GYRO].x + IOSTOUCH_TRAY_STEP, top + 2 * IOSTOUCH_TRAY_DROP )];
}

- (void)showToast:(NSString *)text
{
	toast.text = text;
	toast.hidden = NO;
	toast_until = CACurrentMediaTime() + IOSTOUCH_TOAST_TIME;
}

- (void)setCheat:(int)on
{
	if( on && !IOS_CheatAllowed( ))
	{
		[self showToast:@"Cheats are for single player games"];
		return;
	}

	cheat_on = on;
	IOS_CheatSet( on );
	Haptic( 0 );
	[self showToast:on ? @"Cheat on: god mode, all weapons" : @"Cheat off"];
	[self updateShown];
	[self updateLabels];
}

- (int)buttonAt:(CGPoint)p
{
	int best = -1;
	CGFloat best_d = 0;

	for( int i = 0; i < BTN_COUNT; i++ )
	{
		CGFloat d;

		if( !btn_shown[i] )
			continue;

		d = Dist( p, btn_pos[i] ) - buttons[i].radius;
		if( d <= IOSTOUCH_TOUCH_SLOP && ( best < 0 || d < best_d ))
		{
			best = i;
			best_d = d;
		}
	}

	return best;
}

- (int)inStickZone:(CGPoint)p
{
	CGFloat w = self.bounds.size.width;
	return swapped ? p.x > w * ( 1.0 - IOSTOUCH_STICK_ZONE ) : p.x < w * IOSTOUCH_STICK_ZONE;
}

- (slot_t *)slotFor:(UITouch *)t
{
	for( int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++ )
	{
		if( slots[i].touch == t )
			return &slots[i];
	}

	return NULL;
}

- (int)stickTaken
{
	for( int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++ )
	{
		if( slots[i].touch && slots[i].role == ROLE_STICK )
			return 1;
	}

	return 0;
}

- (void)setPressed:(int)i on:(int)on
{
	btn_views[i].alpha = on ? 1.0 : IOSTOUCH_IDLE_ALPHA;
	if( !( i == BTN_FLASH && flash_group ))
		btn_views[i].backgroundColor = [UIColor colorWithWhite:1.0 alpha:on ? 0.4 : 0.15];

	if( !on && btn_rings[i] )
		btn_rings[i].strokeEnd = 0.0;
}

- (void)closeTray
{
	tray_open = gyro_row_open = cam_row_open = 0;
	level_counting = 0;
	[self updateShown];
}

// The run marker's look: as an idle button (a little darker inside, so its
// chevrons show over bright walls too), or lit blue at full strength while
// the thumb is on it
- (void)setRunLit:(int)lit
{
	lit = lit != 0;
	if( run_lit == lit )
		return;

	run_lit = lit;
	run_marker.alpha = lit ? 1.0 : IOSTOUCH_IDLE_ALPHA;
	run_marker.backgroundColor = lit ? [UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.55] : [UIColor colorWithWhite:0.0 alpha:0.35];
	run_marker.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:lit ? 0.85 : 0.45].CGColor;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	run_chevrons.strokeColor = [UIColor colorWithWhite:1.0 alpha:lit ? 1.0 : 0.85].CGColor;
	run_link.strokeColor = lit ? [UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.95].CGColor : [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
	run_link.opacity = lit ? 1.0 : IOSTOUCH_IDLE_ALPHA;
	[CATransaction commit];
}

// the run marker above a stick at c, as high as fits under the top row
- (void)placeStick:(CGPoint)c
{
	CGFloat limit = [self topRowY] + 22 + 4 + IOSTOUCH_RUN_R;

	stick_center = c;
	run_dist = IOSTOUCH_RUN_DIST;

	if( c.y - run_dist < limit )
		run_dist = c.y - limit;

	if( run_dist < IOSTOUCH_RUN_MIN_DIST )
		run_dist = 0;

	stick_ring.center = c;
	stick_knob.center = c;
	stick_ring.hidden = stick_knob.hidden = NO;
	run_marker.hidden = run_dist <= 0;
	run_link.hidden = run_dist <= 0;
	running = 0;

	if( run_dist > 0 )
	{
		CGPoint m = CGPointMake( c.x, c.y - run_dist );
		UIBezierPath *path = [UIBezierPath bezierPath];

		run_marker.center = m;
		[self setRunLit:0];
		[path moveToPoint:CGPointMake( c.x, c.y - IOSTOUCH_STICK_RADIUS )];
		[path addLineToPoint:CGPointMake( c.x, m.y + IOSTOUCH_RUN_R )];
		run_link.path = path.CGPath;
	}
}

- (void)moveStick:(CGPoint)p
{
	CGFloat dx = p.x - stick_center.x, dy = p.y - stick_center.y;
	CGFloat d = hypot( dx, dy );
	CGFloat up = d > 0 ? acos( fmax( -1.0, fmin( 1.0, -dy / d ))) * 180.0 / M_PI : 180.0;
	CGFloat vx, vy;

	if( run_dist > 0 )
	{
		if( running && ( d < IOSTOUCH_RUN_OFF || up > IOSTOUCH_RUN_CONE_OFF ))
			running = 0;
		else if( !running && d >= IOSTOUCH_RUN_ON && up <= IOSTOUCH_RUN_CONE )
		{
			running = 1;
			Haptic( 1 );
		}
	}

	held_cmds &= ~( BIT_CMD( IOSTOUCH_CMD_FORWARD ) | BIT_CMD( IOSTOUCH_CMD_BACK ) |
		BIT_CMD( IOSTOUCH_CMD_MOVELEFT ) | BIT_CMD( IOSTOUCH_CMD_MOVERIGHT ) | BIT_CMD( IOSTOUCH_CMD_SPEED ));

	if( running )
	{
		// straight ahead at running speed, the knob on the marker
		held_cmds |= BIT_CMD( IOSTOUCH_CMD_FORWARD );
		stick_knob.center = CGPointMake( stick_center.x, stick_center.y - run_dist );
		[self setRunLit:1];
		return;
	}

	[self setRunLit:0];

	vx = dx / IOSTOUCH_STICK_RADIUS;
	vy = dy / IOSTOUCH_STICK_RADIUS;
	if( d > IOSTOUCH_STICK_RADIUS )
	{
		vx = dx / d;
		vy = dy / d;
	}

	stick_knob.center = CGPointMake( stick_center.x + vx * IOSTOUCH_STICK_RADIUS, stick_center.y + vy * IOSTOUCH_STICK_RADIUS );

	// walks, however far it is pushed
	held_cmds |= BIT_CMD( IOSTOUCH_CMD_SPEED );
	if( vy < -IOSTOUCH_STICK_DEADZONE ) held_cmds |= BIT_CMD( IOSTOUCH_CMD_FORWARD );
	if( vy > IOSTOUCH_STICK_DEADZONE ) held_cmds |= BIT_CMD( IOSTOUCH_CMD_BACK );
	if( vx < -IOSTOUCH_STICK_DEADZONE ) held_cmds |= BIT_CMD( IOSTOUCH_CMD_MOVELEFT );
	if( vx > IOSTOUCH_STICK_DEADZONE ) held_cmds |= BIT_CMD( IOSTOUCH_CMD_MOVERIGHT );
}

- (void)endStick
{
	held_cmds &= ~( BIT_CMD( IOSTOUCH_CMD_FORWARD ) | BIT_CMD( IOSTOUCH_CMD_BACK ) |
		BIT_CMD( IOSTOUCH_CMD_MOVELEFT ) | BIT_CMD( IOSTOUCH_CMD_MOVERIGHT ) | BIT_CMD( IOSTOUCH_CMD_SPEED ));
	stick_ring.hidden = stick_knob.hidden = run_marker.hidden = YES;
	run_link.hidden = YES;
	running = 0;
}

- (void)look:(CGPoint)from to:(CGPoint)to
{
	float k = look_sens[look_sens_i];
	look_yaw -= ( to.x - from.x ) * IOSTOUCH_LOOK_DEG_X * k;
	look_pitch += ( to.y - from.y ) * IOSTOUCH_LOOK_DEG_Y * k;
}

- (void)tapTray:(int)i
{
	switch( i )
	{
	case BTN_TRAY_GYRO:
		if( gyro_mode != GYRO_OFF )
		{
			gyro_last_mode = gyro_mode;
			gyro_mode = GYRO_OFF;
		}
		else gyro_mode = gyro_last_mode;
		SaveGyro();
		break;
	case BTN_GYRO_MODE:
		gyro_last_mode = gyro_last_mode == GYRO_TOUCH ? GYRO_ALWAYS : GYRO_TOUCH;
		if( gyro_mode != GYRO_OFF )
			gyro_mode = gyro_last_mode;
		SaveGyro();
		break;
	case BTN_GYRO_SENS:
		gyro_sens_i = ( gyro_sens_i + 1 ) % IOSTOUCH_COUNT( gyro_sens );
		SaveGyro();
		break;
	case BTN_TRAY_SENS:
		look_sens_i = ( look_sens_i + 1 ) % IOSTOUCH_COUNT( look_sens );
		[[NSUserDefaults standardUserDefaults] setFloat:look_sens[look_sens_i] forKey:KEY_LOOK_SENS];
		[self showToast:[NSString stringWithFormat:@"Look sensitivity %gx%@", look_sens[look_sens_i],
			look_sens_i == LOOK_SENS_DEFAULT ? @" (default)" : @" — hold SENS for the default"]];
		break;
	case BTN_TRAY_FPS:
		show_fps = !show_fps;
		[[NSUserDefaults standardUserDefaults] setBool:show_fps forKey:KEY_SHOW_FPS];
		QueueAction( show_fps ? IOSTOUCH_ACT_SHOWFPS : IOSTOUCH_ACT_HIDEFPS );
		break;
	case BTN_TRAY_TAPS:
		show_taps = !show_taps;
		[[NSUserDefaults standardUserDefaults] setBool:show_taps forKey:KEY_SHOW_TAPS];
		[self showToast:show_taps ? @"Taps shown: white ring = your finger, red cross = the game's tap" : @"Taps hidden"];
		break;
	case BTN_TRAY_CTRL:
		swapped = !swapped;
		[[NSUserDefaults standardUserDefaults] setBool:swapped forKey:KEY_SWAPPED];
		[self layoutButtons];
		break;
	case BTN_TRAY_CAM:
		show_camera = !show_camera;
		[[NSUserDefaults standardUserDefaults] setBool:show_camera forKey:KEY_SHOW_CAMERA];
		if( show_camera )
			IOSPhotos_AskAccess();
		[self updateShown];
		break;
	case BTN_CAM_CLEAN:
	case BTN_CAM_HUD:
	case BTN_CAM_BTNS:
		// at least one kind stays ticked
		if(( camera_kinds ^ buttons[i].arg ) != 0 )
			camera_kinds ^= buttons[i].arg;
		[[NSUserDefaults standardUserDefaults] setInteger:camera_kinds forKey:KEY_CAMERA_KINDS];
		break;
	case BTN_CAM_SELFIES:
		selfie_shots = selfie_shots == 1 ? 3 : ( selfie_shots == 3 ? 5 : 1 );
		[[NSUserDefaults standardUserDefaults] setInteger:selfie_shots forKey:KEY_SELFIES];
		break;
	case BTN_CAM_FREEZE:
		freeze_on = !freeze_on;
		[[NSUserDefaults standardUserDefaults] setBool:freeze_on forKey:KEY_FREEZE];
		break;
	case BTN_TRAY_CHEAT:
		// shows the CHEAT button and switches the cheat on; again, hides it
		show_cheat = !show_cheat;
		[[NSUserDefaults standardUserDefaults] setBool:show_cheat forKey:KEY_SHOW_CHEAT];
		if( show_cheat != cheat_on )
			[self setCheat:show_cheat];
		[self updateShown];
		break;
	case BTN_TRAY_KEYS:
		[self closeTray];
		QueueAction( IOSTOUCH_ACT_CONSOLE );
		break;
	}

	[self updateLabels];
}

- (void)flash:(int)burst
{
	[flash.layer removeAllAnimations];
	flash.alpha = burst ? 0.35 : 0.85;
	[UIView animateWithDuration:burst ? 0.12 : 0.3 animations:^{ flash.alpha = 0.0; }];
}

// a photo of each kind ticked (in Action Freeze and camera shots: clean)
- (void)takePhoto:(int)burst
{
	int kinds = ( freezing || seq != SEQ_NONE ) ? IOSTOUCH_PHOTO_CLEAN : camera_kinds;

	IOSPhotos_AskAccess();

	for( int k = IOSTOUCH_PHOTO_CLEAN; k <= IOSTOUCH_PHOTO_HUDBTNS; k <<= 1 )
	{
		if( kinds & k )
			IOS_PhotoCapture( k, burst );
	}
}

// everything held lets go, so the player stands still for the camera
- (void)letGoExcept:(slot_t *)keep
{
	for( int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++ )
	{
		slot_t *s = &slots[i];

		if( !s->touch || s == keep )
			continue;

		if( s->role == ROLE_BUTTON )
			[self setPressed:s->button on:0];
		s->role = ROLE_IGNORE;
	}

	held_cmds = 0;
	[self endStick];
	[self closeTray];
}

- (void)startSequence:(int)type
{
	int ok = type == SEQ_SELFIE ? IOS_PhotoSelfieBegin() : IOS_PhotoOrbitBegin();

	if( !ok )
	{
		[self showToast:@"Selfies are for single player games"];
		return;
	}

	seq = type;
	seq_i = 0;
	seq_n = type == SEQ_SELFIE ? selfie_shots : IOSTOUCH_CINEMA_SHOTS;
	seq_phase = 0;
	seq_next = CACurrentMediaTime() + IOSTOUCH_SEQ_SETTLE;
	IOSPhotos_SetBatch( seq_n > 1 );
	[self letGoExcept:NULL];
	[self updateShown];
	[self updateLabels];
}

- (void)startFreeze:(slot_t *)keep
{
	if( !IOS_PhotoFreezeBegin() )
	{
		[self showToast:@"Action Freeze is for single player games"];
		return;
	}

	freezing = 1;
	[self letGoExcept:keep];
	[self showToast:@"One finger: orbit. Two: move and zoom. X: back"];
	[self updateShown];
	[self updateLabels];
}

- (void)endCamera
{
	IOS_PhotoCameraEnd();
	look_yaw = look_pitch = 0;
	if( burst_on || seq != SEQ_NONE )
		IOSPhotos_SetBatch( 0 );
	freezing = 0;
	seq = SEQ_NONE;
	burst_on = 0;
	[self updateShown];
	[self updateLabels];
}

// once a frame: the burst and the camera sequences
- (void)cameraFrame
{
	CFTimeInterval now = CACurrentMediaTime();

	if( burst_on && now >= burst_next && burst_count < IOSTOUCH_BURST_MAX )
	{
		[self takePhoto:1];
		burst_count++;
		burst_next = now + IOSTOUCH_BURST_STEP;
	}

	if( seq == SEQ_NONE || now < seq_next )
		return;

	if( seq_phase == 0 )
	{
		// the camera to the shot's place, then a moment to settle
		if( seq == SEQ_SELFIE )
			IOS_PhotoSelfieShot( seq_i, seq_n );
		else IOS_PhotoOrbitShot( seq_i, seq_n );
		seq_phase = 1;
		seq_next = now + IOSTOUCH_SEQ_CAPTURE;
	}
	else if( seq_phase == 1 )
	{
		[self takePhoto:seq_n > 1];
		if( ++seq_i < seq_n )
		{
			seq_phase = 0;
			seq_next = now + IOSTOUCH_SEQ_SETTLE;
		}
		else
		{
			seq_phase = 2;
			seq_next = now + IOSTOUCH_SEQ_SHOW;
		}
	}
	else
	{
		IOSPhotos_SetBatch( 0 );
		[self endCamera];
	}
}

// Action Freeze: one finger orbits, two pan and pinch
- (void)freezeMoved:(NSSet<UITouch *> *)touches
{
	slot_t *f[2] = { NULL, NULL };
	int n = 0;

	for( int i = 0; i < IOSTOUCH_MAX_TOUCHES && n < 2; i++ )
	{
		if( slots[i].touch && slots[i].role == ROLE_LOOK )
			f[n++] = &slots[i];
	}

	if( n == 1 && [touches containsObject:f[0]->touch] )
	{
		CGPoint p = [f[0]->touch locationInView:self];
		IOS_PhotoFreezeMove( p.x - f[0]->last.x, p.y - f[0]->last.y, 0, 0, 0 );
	}
	else if( n == 2 )
	{
		CGPoint a0 = f[0]->last, b0 = f[1]->last;
		CGPoint a1 = [f[0]->touch locationInView:self], b1 = [f[1]->touch locationInView:self];
		CGFloat h = MAX( self.bounds.size.height, 1.0 );
		CGFloat d0 = Dist( a0, b0 ), d1 = Dist( a1, b1 );

		IOS_PhotoFreezeMove( 0, 0,
			(( a1.x + b1.x ) - ( a0.x + b0.x )) * 0.5 / h,
			(( a1.y + b1.y ) - ( a0.y + b0.y )) * 0.5 / h,
			d0 > 1.0 ? d1 / d0 : 0.0 );
	}
}

// ---------------------------------------------------------------- weapon wheel

static UIColor *HudOrange( CGFloat a )
{
	return [UIColor colorWithRed:1.0 green:160.0 / 255.0 blue:0.0 alpha:a];
}

// a weapon's HUD icon as a UIImage, made once
- (UIImage *)iconFor:(const ios_wheel_item_t *)it
{
	NSString *key = [NSString stringWithFormat:@"%d %s", it->id, it->name];
	UIImage *img = icon_cache[key];
	const unsigned char *rgba;
	int w = 0, h = 0;

	if( img )
		return [img isKindOfClass:[UIImage class]] ? img : nil;

	rgba = IOS_WeaponIcon( it->id, &w, &h );
	if( rgba && w > 0 && h > 0 )
	{
		CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
		CFDataRef data = CFDataCreate( NULL, rgba, (CFIndex)w * h * 4 );
		CGDataProviderRef prov = CGDataProviderCreateWithCFData( data );
		CGImageRef cg = CGImageCreate( w, h, 8, 32, (size_t)w * 4, cs,
			(CGBitmapInfo)kCGImageAlphaPremultipliedLast, prov, NULL, false, kCGRenderingIntentDefault );

		if( cg )
		{
			img = [UIImage imageWithCGImage:cg];
			CGImageRelease( cg );
		}
		CGDataProviderRelease( prov );
		CFRelease( data );
		CGColorSpaceRelease( cs );
	}

	icon_cache[key] = img ? img : (id)[NSNull null];
	return img;
}

// slice i's angles in degrees, clockwise from the right, the gap at the bottom
static void WheelSlice( int i, CGFloat *a0, CGFloat *a1 )
{
	CGFloat span = ( 360.0 - IOSTOUCH_WHEEL_GAP ) / MAX( wheel_n, 1 );
	CGFloat start = 90.0 + IOSTOUCH_WHEEL_GAP * 0.5;

	*a0 = start + i * span;
	*a1 = *a0 + span;
}

static CGFloat AngleDiff( CGFloat a, CGFloat b )
{
	CGFloat d = fmod( a - b, 360.0 );
	if( d < 0 )
		d += 360.0;
	return d;
}

// which slice a direction (degrees) points at; the gap cancels
static int WheelSliceAt( CGFloat deg, int keep )
{
	CGFloat a0, a1;

	if( keep >= 0 )
	{
		WheelSlice( keep, &a0, &a1 );
		if( AngleDiff( deg, a0 - IOSTOUCH_WHEEL_HYST ) <= a1 - a0 + 2 * IOSTOUCH_WHEEL_HYST )
			return keep;
	}

	for( int i = 0; i < wheel_n; i++ )
	{
		WheelSlice( i, &a0, &a1 );
		if( AngleDiff( deg, a0 ) < a1 - a0 )
			return i;
	}

	return IOSTOUCH_WHEEL_CANCEL;
}

static UIBezierPath *SectorPath( CGPoint c, CGFloat r0, CGFloat r1, CGFloat a0, CGFloat a1 )
{
	UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:c radius:r1 startAngle:a0 * M_PI / 180.0 endAngle:a1 * M_PI / 180.0 clockwise:YES];
	[path addArcWithCenter:c radius:r0 startAngle:a1 * M_PI / 180.0 endAngle:a0 * M_PI / 180.0 clockwise:NO];
	[path closePath];
	return path;
}

- (void)showWheelPick
{
	int shown = wheel_pick;

	for( int i = 0; i < wheel_n; i++ )
	{
		CGFloat a0, a1, mid, pop = i == wheel_pick ? IOSTOUCH_WHEEL_POP : 0.0;
		CGFloat rm = ( wheel_r0 + wheel_r1 ) * 0.5 + pop;
		const ios_wheel_item_t *it = &wheel_items[i];

		WheelSlice( i, &a0, &a1 );
		mid = ( a0 + a1 ) * 0.5 * M_PI / 180.0;

		wheel_slices[i].path = SectorPath( CGPointMake( wheel_center.x + pop * cos( mid ), wheel_center.y + pop * sin( mid )),
			wheel_r0, wheel_r1, a0 + 0.8, a1 - 0.8 ).CGPath;
		wheel_slices[i].fillColor = ( i == wheel_pick ? HudOrange( 0.38 ) :
			( it->current ? HudOrange( 0.14 ) : [UIColor colorWithWhite:1.0 alpha:0.05] )).CGColor;
		wheel_slices[i].strokeColor = ( i == wheel_pick ? HudOrange( 1.0 ) : [UIColor colorWithWhite:1.0 alpha:0.14] ).CGColor;
		wheel_slices[i].lineWidth = i == wheel_pick ? 2.0 : 1.0;
		wheel_cells[i].center = CGPointMake( wheel_center.x + rm * cos( mid ), wheel_center.y + rm * sin( mid ));
		wheel_cells[i].transform = i == wheel_pick ? CGAffineTransformMakeScale( 1.12, 1.12 ) : CGAffineTransformIdentity;

		if( shown < 0 && it->current )
			shown = i;
	}

	// the middle: the picked weapon (or the one in hand) big, its name, its ammo
	if( wheel_pick == IOSTOUCH_WHEEL_CANCEL )
	{
		wheel_big.image = nil;
		wheel_title.text = @"Cancel";
		wheel_ammo.text = @"";
		return;
	}

	if( shown >= 0 )
	{
		const ios_wheel_item_t *it = &wheel_items[shown];

		wheel_big.image = [self iconFor:it];
		wheel_big.alpha = it->has_ammo ? 1.0 : 0.4;
		wheel_title.text = @( it->name );
		if( it->clip >= 0 && it->reserve >= 0 )
			wheel_ammo.text = [NSString stringWithFormat:@"%d  |  %d", it->clip, it->reserve];
		else if( it->reserve >= 0 )
			wheel_ammo.text = it->has_ammo ? [NSString stringWithFormat:@"%d", it->reserve] : @"No ammo";
		else wheel_ammo.text = @"";
	}
}

- (void)setWheelPick:(int)pick
{
	if( pick == wheel_pick )
		return;

	wheel_pick = pick;
	Haptic( 1 );
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	[self showWheelPick];
	[CATransaction commit];
}

- (void)openWheel:(int)slide from:(CGPoint)start
{
	CGSize size = self.bounds.size;

	wheel_n = IOS_WeaponList( wheel_items, IOSTOUCH_WHEEL_MAX );
	if( wheel_n <= 0 )
	{
		[self showToast:@"No weapons"];
		return;
	}

	wheel_open = 1;
	wheel_slide = slide;
	wheel_pick = -1;
	wheel_ref = start;
	wheel_center = CGPointMake( size.width * 0.5, size.height * 0.5 );
	wheel_r1 = MIN( IOSTOUCH_WHEEL_R1_MAX, size.height * 0.47 );
	wheel_r0 = wheel_r1 * IOSTOUCH_WHEEL_R0_FRAC;

	[wheel removeFromSuperview];
	[wheel release];
	wheel = [[UIView alloc] initWithFrame:self.bounds];
	wheel.userInteractionEnabled = NO;

	// frosted glass under the ring, a dark disc in the middle
	UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:wheel_center radius:wheel_r1 + 6 startAngle:0 endAngle:2 * M_PI clockwise:YES];
	UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
	UIVisualEffectView *glass = [[[UIVisualEffectView alloc] initWithEffect:blur] autorelease];
	CAShapeLayer *mask = [CAShapeLayer layer];

	glass.frame = wheel.bounds;
	mask.path = ring.CGPath;
	glass.layer.mask = mask;
	[wheel addSubview:glass];

	CAShapeLayer *tint = [CAShapeLayer layer];
	tint.path = ring.CGPath;
	tint.fillColor = [UIColor colorWithWhite:0.0 alpha:0.35].CGColor;
	tint.strokeColor = HudOrange( 0.55 ).CGColor;
	tint.lineWidth = 1.5;
	[wheel.layer addSublayer:tint];

	CAShapeLayer *hub = [CAShapeLayer layer];
	hub.path = [UIBezierPath bezierPathWithArcCenter:wheel_center radius:wheel_r0 - 4 startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;
	hub.fillColor = [UIColor colorWithWhite:0.0 alpha:0.45].CGColor;
	hub.strokeColor = HudOrange( 0.35 ).CGColor;
	hub.lineWidth = 1.0;
	[wheel.layer addSublayer:hub];

	for( int i = 0; i < wheel_n; i++ )
	{
		const ios_wheel_item_t *it = &wheel_items[i];
		CGFloat a0, a1, cw, ch, chord;
		UIImage *icon = [self iconFor:it];
		UIView *cell;
		NSString *count = nil;

		wheel_slices[i] = [CAShapeLayer layer];
		[wheel.layer addSublayer:wheel_slices[i]];

		// the icon as big as the slice allows (HUD icons are wide, about
		// 4:1), the ammo under it
		WheelSlice( i, &a0, &a1 );
		chord = 2.0 * ( wheel_r0 + wheel_r1 ) * 0.5 * sin(( a1 - a0 ) * 0.5 * M_PI / 180.0 );
		cw = MIN( wheel_r1 - wheel_r0 - 8.0, chord * 1.15 );
		ch = MIN( cw * 0.42, chord * 0.62 );
		cell = [[[UIView alloc] initWithFrame:CGRectMake( 0, 0, cw, ch + 14 )] autorelease];
		cell.alpha = it->has_ammo ? 1.0 : 0.35;

		if( icon )
		{
			UIImageView *iv = [[[UIImageView alloc] initWithImage:icon] autorelease];
			iv.contentMode = UIViewContentModeScaleAspectFit;
			iv.frame = CGRectMake( 0, 0, cw, ch );
			iv.layer.shadowColor = HudOrange( 1.0 ).CGColor;
			iv.layer.shadowRadius = 4;
			iv.layer.shadowOpacity = 0.5;
			iv.layer.shadowOffset = CGSizeZero;
			[cell addSubview:iv];
		}
		else
		{
			UILabel *name = [[[UILabel alloc] initWithFrame:CGRectMake( 0, 0, cw, ch )] autorelease];
			name.text = @( it->name );
			name.textColor = HudOrange( 1.0 );
			name.font = [UIFont boldSystemFontOfSize:13];
			name.textAlignment = NSTextAlignmentCenter;
			name.adjustsFontSizeToFitWidth = YES;
			name.minimumScaleFactor = 0.5;
			[cell addSubview:name];
		}

		if( it->reserve >= 0 )
			count = [NSString stringWithFormat:@"%d", it->reserve + ( it->clip > 0 ? it->clip : 0 )];

		if( count )
		{
			UILabel *ammo = [[[UILabel alloc] initWithFrame:CGRectMake( 0, ch, cw, 14 )] autorelease];
			ammo.text = count;
			ammo.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
			ammo.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
			ammo.textAlignment = NSTextAlignmentCenter;
			[cell addSubview:ammo];
		}

		wheel_cells[i] = cell;
		[wheel addSubview:cell];
	}

	// the middle
	wheel_big = [[[UIImageView alloc] initWithFrame:CGRectMake( 0, 0, wheel_r0 * 1.6, wheel_r0 * 0.55 )] autorelease];
	wheel_big.center = CGPointMake( wheel_center.x, wheel_center.y - wheel_r0 * 0.22 );
	wheel_big.contentMode = UIViewContentModeScaleAspectFit;
	wheel_big.layer.shadowColor = HudOrange( 1.0 ).CGColor;
	wheel_big.layer.shadowRadius = 8;
	wheel_big.layer.shadowOpacity = 0.7;
	wheel_big.layer.shadowOffset = CGSizeZero;
	[wheel addSubview:wheel_big];

	wheel_title = [[[UILabel alloc] initWithFrame:CGRectMake( 0, 0, wheel_r0 * 1.7, 20 )] autorelease];
	wheel_title.center = CGPointMake( wheel_center.x, wheel_center.y + wheel_r0 * 0.25 );
	wheel_title.textAlignment = NSTextAlignmentCenter;
	wheel_title.textColor = HudOrange( 1.0 );
	wheel_title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightHeavy];
	wheel_title.adjustsFontSizeToFitWidth = YES;
	wheel_title.minimumScaleFactor = 0.6;
	[wheel addSubview:wheel_title];

	wheel_ammo = [[[UILabel alloc] initWithFrame:CGRectMake( 0, 0, wheel_r0 * 1.7, 16 )] autorelease];
	wheel_ammo.center = CGPointMake( wheel_center.x, wheel_center.y + wheel_r0 * 0.5 );
	wheel_ammo.textAlignment = NSTextAlignmentCenter;
	wheel_ammo.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
	wheel_ammo.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
	[wheel addSubview:wheel_ammo];

	[self insertSubview:wheel belowSubview:toast];
	[self showWheelPick];

	// the game holds still while the wheel is open
	IOS_HoldGame( 1 );
	Haptic( 0 );
}

// sliding to pick: the direction from where the thumb went down
- (void)slideWheel:(CGPoint)p
{
	CGFloat dx = p.x - wheel_ref.x, dy = p.y - wheel_ref.y, d = hypot( dx, dy );

	if( d > IOSTOUCH_WHEEL_LEASH )
	{
		wheel_ref.x = p.x - dx / d * IOSTOUCH_WHEEL_LEASH;
		wheel_ref.y = p.y - dy / d * IOSTOUCH_WHEEL_LEASH;
	}

	if( d < IOSTOUCH_WHEEL_DEAD )
		return;

	[self setWheelPick:WheelSliceAt( atan2( dy, dx ) * 180.0 / M_PI, wheel_pick )];
}

// tapping: the slice under the finger, -1 for none
- (int)wheelSliceUnder:(CGPoint)p
{
	CGFloat dx = p.x - wheel_center.x, dy = p.y - wheel_center.y, d = hypot( dx, dy );

	if( d < wheel_r0 || d > wheel_r1 + IOSTOUCH_WHEEL_POP )
		return -1;

	return WheelSliceAt( atan2( dy, dx ) * 180.0 / M_PI, -1 );
}

- (void)closeWheel:(int)select
{
	if( !wheel_open )
		return;

	if( select && wheel_pick >= 0 && wheel_pick < wheel_n )
		IOS_WeaponSelect( wheel_items[wheel_pick].id );

	wheel_open = 0;
	wheel_pick = -1;
	[wheel removeFromSuperview];
	[wheel release];
	wheel = nil;
	IOS_HoldGame( 0 );
}

// ---------------------------------------------------------------- LIGHT

static UIImage *TemplateImage( const unsigned char *rgba, int w, int h )
{
	UIImage *img = nil;
	CGColorSpaceRef cs;
	CFDataRef data;
	CGDataProviderRef prov;
	CGImageRef cg;

	if( !rgba || w <= 0 || h <= 0 )
		return nil;

	cs = CGColorSpaceCreateDeviceRGB();
	data = CFDataCreate( NULL, rgba, (CFIndex)w * h * 4 );
	prov = CGDataProviderCreateWithCFData( data );
	cg = CGImageCreate( w, h, 8, 32, (size_t)w * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast, prov, NULL, false, kCGRenderingIntentDefault );
	if( cg )
	{
		// drawn in the button's colour from its shape alone
		img = [[UIImage imageWithCGImage:cg] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		CGImageRelease( cg );
	}
	CGDataProviderRelease( prov );
	CFRelease( data );
	CGColorSpaceRelease( cs );
	return img;
}

// made once the game's pictures can be read; until then LIGHT is a word
- (void)setupFlashlight
{
	const unsigned char *px[IOSTOUCH_FLASH_PARTS];
	int w[IOSTOUCH_FLASH_PARTS] = { 0 }, h[IOSTOUCH_FLASH_PARTS] = { 0 };
	CGFloat r = buttons[BTN_FLASH].radius, k, total;

	if( flash_group )
		return;

	for( int i = 0; i < IOSTOUCH_FLASH_PARTS; i++ )
		px[i] = IOS_FlashlightIcon( i, &w[i], &h[i] );

	if( !px[IOSTOUCH_FLASH_EMPTY] || !px[IOSTOUCH_FLASH_FULL] )
		return;

	// the lamp and its beam, fitted round the button
	total = w[IOSTOUCH_FLASH_EMPTY] + ( px[IOSTOUCH_FLASH_BEAM] ? w[IOSTOUCH_FLASH_BEAM] : 0 );
	k = MIN( r * 2.6 / total, r * 1.3 / MAX( h[IOSTOUCH_FLASH_EMPTY], 1 ));

	flash_group = [[UIView alloc] initWithFrame:CGRectMake( 0, 0, total * k, h[IOSTOUCH_FLASH_EMPTY] * k )];
	flash_group.center = CGPointMake( r, r );
	flash_group.userInteractionEnabled = NO;

	// the beam shines out of the lamp's head, on its right, as on the HUD
	CGRect lamp = CGRectMake( 0, 0, w[IOSTOUCH_FLASH_EMPTY] * k, h[IOSTOUCH_FLASH_EMPTY] * k );

	flash_empty = [[UIImageView alloc] initWithImage:TemplateImage( px[IOSTOUCH_FLASH_EMPTY], w[IOSTOUCH_FLASH_EMPTY], h[IOSTOUCH_FLASH_EMPTY] )];
	flash_empty.frame = lamp;
	flash_empty.alpha = 0.45;
	[flash_group addSubview:flash_empty];

	flash_full = [[UIImageView alloc] initWithImage:TemplateImage( px[IOSTOUCH_FLASH_FULL], w[IOSTOUCH_FLASH_FULL], h[IOSTOUCH_FLASH_FULL] )];
	flash_full.frame = lamp;
	flash_mask = [[CAShapeLayer layer] retain];
	flash_full.layer.mask = flash_mask;
	[flash_group addSubview:flash_full];

	if( px[IOSTOUCH_FLASH_BEAM] )
	{
		flash_beam = [[UIImageView alloc] initWithImage:TemplateImage( px[IOSTOUCH_FLASH_BEAM], w[IOSTOUCH_FLASH_BEAM], h[IOSTOUCH_FLASH_BEAM] )];
		flash_beam.frame = CGRectMake( w[IOSTOUCH_FLASH_EMPTY] * k, ( h[IOSTOUCH_FLASH_EMPTY] - h[IOSTOUCH_FLASH_BEAM] ) * 0.5 * k, w[IOSTOUCH_FLASH_BEAM] * k, h[IOSTOUCH_FLASH_BEAM] * k );
		[flash_group addSubview:flash_beam];
	}

	// no ring: the lamp itself is the button, glowing like the HUD's
	flash_group.layer.shadowColor = HudOrange( 1.0 ).CGColor;
	flash_group.layer.shadowRadius = 5;
	flash_group.layer.shadowOpacity = 0.85;
	flash_group.layer.shadowOffset = CGSizeZero;
	btn_views[BTN_FLASH].backgroundColor = [UIColor clearColor];
	btn_views[BTN_FLASH].layer.borderWidth = 0.0;
	btn_labels[BTN_FLASH].hidden = YES;
	[btn_views[BTN_FLASH] addSubview:flash_group];
	flash_shown_on = flash_shown_bat = -1;
}

- (void)updateFlashlight
{
	int on = 0, bat = 100;
	UIColor *color;

	[self setupFlashlight];
	if( !flash_group )
		return;

	IOS_FlashlightState( &on, &bat );
	if( on == flash_shown_on && bat == flash_shown_bat )
		return;

	flash_shown_on = on;
	flash_shown_bat = bat;

	// as on the HUD: red under 20%, the charge filling from the right
	color = bat < 20 ? [UIColor colorWithRed:1.0 green:0.2 blue:0.15 alpha:1.0] : HudOrange( 1.0 );
	flash_empty.tintColor = flash_full.tintColor = flash_beam.tintColor = color;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	CGFloat w = flash_full.bounds.size.width, h = flash_full.bounds.size.height;
	flash_mask.path = [UIBezierPath bezierPathWithRect:CGRectMake( w * ( 1.0 - bat / 100.0 ), 0, w * bat / 100.0, h )].CGPath;
	[CATransaction commit];

	flash_beam.hidden = !on;
	flash_group.layer.shadowOpacity = on ? 1.0 : 0.6;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	for( UITouch *t in touches )
	{
		CGPoint p = [t locationInView:self];
		slot_t *s = [self slotFor:nil];
		int b;

		if( !s )
			continue;

		memset( s, 0, sizeof( *s ));
		s->touch = t;

		// the grace after the overlay went: swallowed
		if( !overlay_shown )
		{
			s->role = ROLE_IGNORE;
			continue;
		}
		s->start = s->last = p;
		s->t0 = CACurrentMediaTime();

		b = [self buttonAt:p];

		// the wheel opened to tap: a slice picks, anywhere else closes it
		if( wheel_open && !wheel_slide )
		{
			int i = [self wheelSliceUnder:p];
			if( i >= 0 )
				wheel_pick = i;
			[self closeWheel:i >= 0];
			s->role = ROLE_IGNORE;
			continue;
		}

		// a camera sequence takes no touches; Action Freeze takes them all
		if( seq != SEQ_NONE )
		{
			s->role = ROLE_IGNORE;
			continue;
		}

		if( freezing && b < 0 )
		{
			s->role = ROLE_LOOK;
			continue;
		}

		// a touch off the open tray closes it, and does nothing else
		if( tray_open && ( b < 0 || buttons[b].row == ROW_MAIN ) && b != BTN_MENU )
		{
			[self closeTray];
			s->role = ROLE_IGNORE;
			continue;
		}

		if( b >= 0 )
		{
			s->role = ROLE_BUTTON;
			s->button = b;
			[self setPressed:b on:1];

			if( buttons[b].kind == KIND_HOLD )
				held_cmds |= BIT_CMD( buttons[b].arg );
		}
		else if( [self inStickZone:p] && ![self stickTaken] )
		{
			s->role = ROLE_STICK;
			[self placeStick:p];
		}
		else
		{
			s->role = ROLE_LOOK;
		}
	}
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if( freezing )
		[self freezeMoved:touches];

	for( UITouch *t in touches )
	{
		slot_t *s = [self slotFor:t];
		CGPoint p = [t locationInView:self];

		if( !s )
			continue;

		s->moved = MAX( s->moved, Dist( p, s->start ));

		switch( s->role )
		{
		case ROLE_STICK:
			[self moveStick:p];
			break;
		case ROLE_LOOK:
			if( !freezing )
				[self look:s->last to:p];
			break;
		case ROLE_BUTTON:
			if( buttons[s->button].kind == KIND_WHEEL )
			{
				if( wheel_open && wheel_slide )
					[self slideWheel:p];
				else if( !wheel_open && !s->done && Dist( p, s->start ) >= IOSTOUCH_WHEEL_OPEN_SLIDE )
				{
					s->done = 1;
					[self setPressed:s->button on:0];
					[self openWheel:1 from:s->start];
					[self slideWheel:p];
				}
			}
			else if( buttons[s->button].kind == KIND_CAMERA && !freezing )
			{
				CGFloat dx = p.x - s->start.x, dy = p.y - s->start.y;

				if( s->done || burst_on )
					break;

				// sideways: a burst while held; down: Action Freeze; up: the cinematic burst
				if( fabs( dx ) >= IOSTOUCH_CAM_SLIDE && fabs( dx ) > fabs( dy ))
				{
					s->done = 1;
					burst_on = 1;
					burst_count = 0;
					burst_next = 0;
					IOSPhotos_SetBatch( 1 );
				}
				else if( dy >= IOSTOUCH_CAM_FAR && freeze_on )
				{
					s->done = 1;
					[self setPressed:s->button on:0];
					[self startFreeze:s];
				}
				else if( dy <= -IOSTOUCH_CAM_FAR )
				{
					s->done = 1;
					[self setPressed:s->button on:0];
					[self startSequence:SEQ_CINEMA];
				}
			}
			else if( buttons[s->button].look )
				[self look:s->last to:p];
			else if( !s->off && Dist( p, btn_pos[s->button] ) > buttons[s->button].radius + IOSTOUCH_TOUCH_SLOP * 2 )
			{
				// slid off: cancels a tap or a hold
				s->off = 1;
				[self setPressed:s->button on:0];
				if( buttons[s->button].kind == KIND_LEVEL && level_counting )
				{
					level_counting = 0;
					toast_until = 0;
				}
			}
			break;
		default:
			break;
		}

		s->last = p;
	}
}

- (void)endTouch:(UITouch *)t cancelled:(int)cancelled
{
	slot_t *s = [self slotFor:t];

	if( !s )
		return;

	if( s->role == ROLE_STICK )
		[self endStick];
	else if( s->role == ROLE_BUTTON )
	{
		int b = s->button;
		const button_def_t *def = &buttons[b];
		int tap = !cancelled && !s->off && !s->done;

		[self setPressed:b on:0];

		switch( def->kind )
		{
		case KIND_HOLD:
			held_cmds &= ~BIT_CMD( def->arg );
			break;
		case KIND_TAP:
			if( tap && b == BTN_FREEZE_X )
				[self endCamera];
			else if( tap )
				QueueAction( def->arg );
			break;
		case KIND_MENU:
			if( tap )
			{
				if( tray_open )
					[self closeTray];
				else
					QueueAction( def->arg );
			}
			break;
		case KIND_TRAY:
			if( tap )
				[self tapTray:b];
			break;
		case KIND_WHEEL:
			if( wheel_open && wheel_slide )
				[self closeWheel:!cancelled];
			else if( tap )
				QueueAction( def->arg );
			break;
		case KIND_CAMERA:
			if( burst_on )
			{
				burst_on = 0;
				IOSPhotos_SetBatch( 0 );
			}
			else if( tap )
				[self takePhoto:0];
			break;
		case KIND_LEVEL:
			if( level_counting && !cancelled && !s->off && btn_shown[b] )
			{
				IOS_GoToLevel( level_index );
				[self closeTray];
			}
			else if( tap )
				[self showToast:@"Hold LEVEL to count chapters"];
			level_counting = 0;
			toast_until = 0;
			break;
		default:
			break;
		}

		// cheat on and flying: two quick taps of JUMP land
		if( b == BTN_JUMP && cheat_on && !cancelled )
		{
			CFTimeInterval now = CACurrentMediaTime();

			if( now - s->t0 < IOSTOUCH_LAND_TAP && !s->done )
			{
				if( jump_tap_end > 0 && s->t0 - jump_tap_end < IOSTOUCH_LAND_GAP && IOS_CheatNoclip( ))
				{
					IOS_CheatSetNoclip( 0 );
					Haptic( 0 );
					[self updateLabels];
					jump_tap_end = 0;
				}
				else jump_tap_end = now;
			}
			else jump_tap_end = 0;
		}
	}

	memset( s, 0, sizeof( *s ));
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	for( UITouch *t in touches )
		[self endTouch:t cancelled:0];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	for( UITouch *t in touches )
		[self endTouch:t cancelled:1];
}

- (void)releaseAll
{
	[self closeWheel:0];

	for( int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++ )
	{
		if( slots[i].touch )
			[self endTouch:slots[i].touch cancelled:1];
	}

	held_cmds = 0;
	look_yaw = look_pitch = 0;
	level_counting = 0;
	toast.hidden = YES;
	if( freezing || seq != SEQ_NONE || burst_on )
		[self endCamera];
	[self endStick];
	[self closeTray];
}

// once a frame: the hold rings, and what a finished hold does
- (void)updateHolds
{
	CFTimeInterval now = CACurrentMediaTime();

	[self cameraFrame];

	if( level_counting )
	{
		int count = IOS_LevelCount( );

		if( count <= 0 )
			level_counting = 0;
		else
		{
			if( now >= level_next )
			{
				level_index = ( level_index + 1 ) % count;
				level_next = now + IOSTOUCH_LEVEL_STEP;
				Haptic( 1 );
			}

			toast.text = [NSString stringWithFormat:@"Chapter %d of %d: %s", level_index + 1, count, IOS_LevelTitle( level_index )];
			toast.hidden = NO;
			toast_until = now + IOSTOUCH_LEVEL_STEP;
		}
	}

	if( !toast.hidden && now > toast_until )
		toast.hidden = YES;

	for( int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++ )
	{
		slot_t *s = &slots[i];
		const button_def_t *def;
		CGFloat f;

		if( !s->touch || s->role != ROLE_BUTTON || s->off || s->done )
			continue;

		def = &buttons[s->button];

		// cheat on: JUMP or USE held still switch noclip or notarget
		if(( s->button == BTN_JUMP || s->button == BTN_USE ) && cheat_on )
		{
			if( s->moved > IOSTOUCH_CHEAT_STILL )
			{
				btn_rings[s->button].strokeEnd = 0.0;
				continue;
			}

			f = ( now - s->t0 ) / IOSTOUCH_CHEAT_HOLD;
			[CATransaction begin];
			[CATransaction setDisableActions:YES];
			btn_rings[s->button].strokeEnd = fmin( f, 1.0 );
			[CATransaction commit];

			if( f >= 1.0 )
			{
				s->done = 1;
				Haptic( 0 );
				if( s->button == BTN_JUMP )
				{
					IOS_CheatSetNoclip( !IOS_CheatNoclip( ));
					[self showToast:IOS_CheatNoclip( ) ? @"Noclip on: double-tap JUMP to land" : @"Noclip off"];
				}
				else
				{
					IOS_CheatSetNotarget( !IOS_CheatNotarget( ));
					[self showToast:IOS_CheatNotarget( ) ? @"Notarget on: enemies ignore you" : @"Notarget off"];
				}
				[self updateLabels];
			}
			continue;
		}

		if( def->hold <= 0 )
			continue;

		f = ( now - s->t0 ) / def->hold;
		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		btn_rings[s->button].strokeEnd = fmin( f, 1.0 );
		[CATransaction commit];

		if( f < 1.0 )
			continue;

		s->done = 1;
		Haptic( 0 );

		switch( s->button )
		{
		case BTN_MENU:
			tray_open = 1;
			gyro_row_open = 0;
			[self updateShown];
			[self updateLabels];
			break;
		case BTN_TRAY_SENS:
			// held: back to the default
			look_sens_i = LOOK_SENS_DEFAULT;
			[[NSUserDefaults standardUserDefaults] setFloat:look_sens[look_sens_i] forKey:KEY_LOOK_SENS];
			[self showToast:[NSString stringWithFormat:@"Look sensitivity back to the default, %gx", look_sens[look_sens_i]]];
			[self updateLabels];
			break;
		case BTN_TRAY_GYRO:
			gyro_row_open = 1;
			cam_row_open = 0;
			[self updateShown];
			[self updateLabels];
			break;
		case BTN_CHEAT:
			[self setCheat:!cheat_on];
			break;
		case BTN_NEXTWPN:
			[self setPressed:BTN_NEXTWPN on:0];
			if( !wheel_open )
				[self openWheel:0 from:s->start];
			break;
		case BTN_CAMERA:
			if( freezing )
				break;
			[self setPressed:BTN_CAMERA on:0];
			if( s->moved < IOSTOUCH_CAM_SLIDE )
				[self startSequence:SEQ_SELFIE];
			break;
		case BTN_TRAY_CAM:
			cam_row_open = 1;
			gyro_row_open = 0;
			[self updateShown];
			[self updateLabels];
			break;
		case BTN_TRAY_LEVEL:
			level_counting = 1;
			level_index = 0;
			level_next = now + IOSTOUCH_LEVEL_STEP;
			break;
		default:
			QueueAction( def->arg );
			break;
		}
	}
}

// for the gyro's TOUCH mode: a thumb on the stick, on the look area, or on
// a button a drag looks through
- (int)gyroThumbDown
{
	for( int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++ )
	{
		slot_t *s = &slots[i];

		if( !s->touch )
			continue;

		if( s->role == ROLE_STICK || s->role == ROLE_LOOK || ( s->role == ROLE_BUTTON && buttons[s->button].look ))
			return 1;
	}

	return 0;
}

@end

// ---------------------------------------------------------------- per frame

static IOSTouchOverlay *overlay;

// Just after the overlay goes (MENU opened the game menu), it keeps taking
// touches for a moment, so a second tap on MENU can't land on the menu's
// own buttons under it (its quit X sits right there)
#define IOSTOUCH_HIDE_GRACE 0.5
#define IOSTOUCH_SHOW_TIME  0.35
static CFTimeInterval hide_grace_until;

// TAPS: where each touch really went down (a white ring, here) next to
// where the game got it (a red cross, drawn by the engine), to check that
// taps land where they should, in the menus above all. A recognizer on
// the window sees every touch without taking any from SDL or the buttons.
static UIView *taps_view;

@interface IOSTapProbe : UIGestureRecognizer <UIGestureRecognizerDelegate>
@end

@implementation IOSTapProbe
- (instancetype)init
{
	if(( self = [super initWithTarget:nil action:NULL] ))
	{
		self.cancelsTouchesInView = NO;
		self.delaysTouchesBegan = NO;
		self.delaysTouchesEnded = NO;
		self.delegate = self;
	}
	return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other
{
	return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[super touchesBegan:touches withEvent:event];

	if( !show_taps || !taps_view )
		return;

	for( UITouch *t in touches )
	{
		CGPoint p = [t locationInView:taps_view];
		CAShapeLayer *ring = [CAShapeLayer layer];
		CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];

		ring.frame = CGRectMake( p.x - 22, p.y - 22, 44, 44 );
		ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake( 2, 2, 40, 40 )].CGPath;
		ring.fillColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
		ring.strokeColor = [UIColor whiteColor].CGColor;
		ring.lineWidth = 2.5;
		ring.opacity = 0.0;

		fade.fromValue = @1.0;
		fade.toValue = @0.0;
		fade.duration = 1.5;

		[CATransaction begin];
		[CATransaction setCompletionBlock:^{ [ring removeFromSuperlayer]; }];
		[taps_view.layer addSublayer:ring];
		[ring addAnimation:fade forKey:@"fade"];
		[CATransaction commit];
	}
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[super touchesEnded:touches withEvent:event];
	[self allUp:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[super touchesCancelled:touches withEvent:event];
	[self allUp:event];
}

// never a gesture: once every finger is up it gives up, to start again
- (void)allUp:(UIEvent *)event
{
	for( UITouch *t in [event allTouches] )
	{
		if( t.phase != UITouchPhaseEnded && t.phase != UITouchPhaseCancelled )
			return;
	}
	self.state = UIGestureRecognizerStateFailed;
}
@end

int IOSTouch_ShowTaps( void )
{
	return show_taps;
}

static UIView *HostView( void *window )
{
	SDL_SysWMinfo info;

	SDL_VERSION( &info.version );
	if( !window || !SDL_GetWindowWMInfo( window, &info ) || info.subsystem != SDL_SYSWM_UIKIT )
		return nil;

	return info.info.uikit.window.rootViewController.view;
}

static void GyroFrame( void )
{
	UIInterfaceOrientation o = UIInterfaceOrientationUnknown;
	CFTimeInterval now = CACurrentMediaTime();
	int active = [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
	int side, ok, use;
	double yaw, pitch;

	if( @available( iOS 13.0, * ))
	{
		UIWindowScene *scene = overlay.window.windowScene;
		o = scene ? scene.interfaceOrientation : UIInterfaceOrientationUnknown;
	}
	else
	{
		o = [UIApplication sharedApplication].statusBarOrientation;
	}

	side = o == UIInterfaceOrientationLandscapeLeft ? 1 : ( o == UIInterfaceOrientationLandscapeRight ? -1 : 0 );
	if( side != 0 && gyro_last_side != 0 && side != gyro_last_side )
		gyro_turned_round = now;
	if( side != 0 )
		gyro_last_side = side;

	GyroRun( overlay_shown && active && side != 0 && gyro_mode != GYRO_OFF && motion.deviceMotionAvailable );

	os_unfair_lock_lock( &gyro_lock );
	gyro_side_q = side;
	yaw = gyro_yaw;
	pitch = gyro_pitch;
	gyro_yaw = gyro_pitch = 0.0;
	os_unfair_lock_unlock( &gyro_lock );

	ok = gyro_running && ( gyro_mode == GYRO_ALWAYS || [overlay gyroThumbDown] ) && !tray_open && !freezing && seq == SEQ_NONE
		&& now - gyro_turned_round >= IOSTOUCH_GYRO_TURN_HOLD;
	use = ok && gyro_was_ok && now - gyro_last_frame <= IOSTOUCH_GYRO_MAX_FRAME;
	gyro_was_ok = ok;
	gyro_last_frame = now;

	if( !use )
		return;

	// 1.0x turns the view exactly as far as the phone turned
	look_yaw += yaw * gyro_sens[gyro_sens_i];
	look_pitch -= pitch * gyro_sens[gyro_sens_i];
}

void IOSTouch_Frame( void *window, int ingame )
{
	@autoreleasepool
	{
		UIView *host = HostView( window );

		if( !host )
			return;

		if( !overlay )
		{
			LoadSettings();
			motion = [[CMMotionManager alloc] init];
			motion_queue = [[NSOperationQueue alloc] init];
			motion_queue.maxConcurrentOperationCount = 1;
			motion_queue.qualityOfService = NSQualityOfServiceUserInteractive;

			overlay = [[IOSTouchOverlay alloc] initWithFrame:host.bounds];
			overlay.hidden = YES;

			// the FPS counter is the engine's, as the player last left it
			QueueAction( show_fps ? IOSTOUCH_ACT_SHOWFPS : IOSTOUCH_ACT_HIDEFPS );
		}

		// SDL may make its view again
		if( overlay.superview != host )
		{
			[overlay removeFromSuperview];
			overlay.frame = host.bounds;
			[host addSubview:overlay];
		}
		[host bringSubviewToFront:overlay];

		if( !taps_view )
		{
			taps_view = [[UIView alloc] initWithFrame:host.bounds];
			taps_view.userInteractionEnabled = NO;
			taps_view.backgroundColor = [UIColor clearColor];
		}
		if( taps_view.superview != host )
		{
			[taps_view removeFromSuperview];
			[host addSubview:taps_view];
		}
		taps_view.frame = host.bounds;
		[host bringSubviewToFront:taps_view];

		if( host.window )
		{
			static UIWindow *probed;

			if( probed != host.window )
			{
				IOSTapProbe *probe = [[IOSTapProbe alloc] init];
				[host.window addGestureRecognizer:probe];
				[probe release];
				probed = host.window;
			}
		}

		if( ingame != overlay_shown )
		{
			overlay_shown = ingame;

			if( !ingame )
			{
				[overlay releaseAll];
				hide_grace_until = CACurrentMediaTime() + IOSTOUCH_HIDE_GRACE;
				overlay.alpha = 0.02; // (still takes touches, all ignored)
			}
			else
			{
				// back in: the buttons fade in (after a fade-in from black,
				// a chapter's start, they come up as the scene does)
				hide_grace_until = 0;
				if( overlay.hidden )
					overlay.alpha = 0.0;
				overlay.hidden = NO;
				[UIView animateWithDuration:IOSTOUCH_SHOW_TIME delay:0 options:UIViewAnimationOptionBeginFromCurrentState
					animations:^{ overlay.alpha = 1.0; } completion:nil];
			}
		}

		if( !overlay_shown && !overlay.hidden && CACurrentMediaTime() >= hide_grace_until )
		{
			overlay.hidden = YES;
			overlay.alpha = 1.0;
		}

		if( !CGRectEqualToRect( overlay.bounds, overlay->laid_out_for )
			|| !UIEdgeInsetsEqualToEdgeInsets( [overlay insets], overlay->laid_out_insets ))
			[overlay layoutButtons];

		if( overlay_shown )
		{
			[overlay updateHolds];
			[overlay updateFlashlight];
		}

		GyroFrame();
	}
}

void IOSTouch_KeepAwake( int on )
{
	static int awake = -1;

	if( on == awake )
		return;

	awake = on;
	[UIApplication sharedApplication].idleTimerDisabled = on ? YES : NO;
}

int IOS_TouchShown( void )
{
	return overlay_shown;
}

unsigned int IOSTouch_HeldCommands( void )
{
	return overlay_shown ? held_cmds : 0;
}

int IOSTouch_PopAction( void )
{
	int action;

	if( actions_head == actions_tail )
		return IOSTOUCH_ACT_NONE;

	action = actions[actions_head];
	actions_head = ( actions_head + 1 ) % IOSTOUCH_MAX_ACTIONS;
	return action;
}

void IOSTouch_ShowMessage( const char *text )
{
	if( overlay )
		[overlay showToast:@( text )];
}

void IOSTouch_CameraFeedback( int burst )
{
	if( !overlay )
		return;

	[overlay flash:burst];
	AudioServicesPlaySystemSound( burst ? 1104 : 1108 );
	Haptic( 0 );
}

UIView *IOSTouch_OverlayView( void )
{
	return overlay;
}

void IOSTouch_ToggleCheat( void )
{
	if( !overlay )
		return;

	if( !cheat_on && !show_cheat )
	{
		show_cheat = 1;
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:KEY_SHOW_CHEAT];
	}

	[overlay setCheat:!cheat_on];
}

void IOSTouch_TakeLook( float *yaw, float *pitch )
{
	*yaw = look_yaw;
	*pitch = look_pitch;
	look_yaw = look_pitch = 0.0f;
}
