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
#import <QuartzCore/QuartzCore.h>
#import <CoreMotion/CoreMotion.h>
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
#define KEY_SWAPPED   @"iosTouchSwapped"
#define KEY_SHOW_CHEAT @"iosTouchShowCheat"

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
	BTN_TRAY_GYRO,
	BTN_TRAY_SENS,
	BTN_TRAY_FPS,
	BTN_TRAY_CHEAT,
	BTN_TRAY_LEVEL,
	BTN_TRAY_CTRL,
	BTN_TRAY_KEYS,
	BTN_GYRO_MODE,
	BTN_GYRO_SENS,
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
} button_kind_t;

enum { ROW_MAIN, ROW_TRAY, ROW_GYRO };

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
[BTN_NEXTWPN]   = { "NEXT\nWPN",    KIND_TAP,     IOSTOUCH_ACT_NEXTWEAPON, 22, 0, ROW_MAIN },
[BTN_FLASH]     = { "LIGHT",        KIND_TAP,     IOSTOUCH_ACT_FLASHLIGHT, 22, 0, ROW_MAIN },
[BTN_QSAVE]     = { "QUICK\nSAVE",  KIND_HOLDACT, IOSTOUCH_ACT_QUICKSAVE, 22, 0, ROW_MAIN, IOSTOUCH_SAVE_HOLD },
[BTN_QLOAD]     = { "QUICK\nLOAD",  KIND_HOLDACT, IOSTOUCH_ACT_QUICKLOAD, 22, 0, ROW_MAIN, IOSTOUCH_SAVE_HOLD },
[BTN_MENU]      = { "MENU",         KIND_MENU,    IOSTOUCH_ACT_ESCAPE,    22, 0, ROW_MAIN, IOSTOUCH_MENU_HOLD },
[BTN_CHEAT]     = { "CHEAT",        KIND_CHEAT,   0,                      22, 0, ROW_MAIN, IOSTOUCH_CHEAT_HOLD },
[BTN_TRAY_GYRO] = { "GYRO",         KIND_TRAY,    0,                      20, 0, ROW_TRAY, IOSTOUCH_MENU_HOLD },
[BTN_TRAY_SENS] = { "SENS",         KIND_TRAY,    0,                      20, 0, ROW_TRAY },
[BTN_TRAY_FPS]  = { "FPS",          KIND_TRAY,    0,                      20, 0, ROW_TRAY },
[BTN_TRAY_CHEAT] = { "CHEAT",       KIND_TRAY,    0,                      20, 0, ROW_TRAY },
[BTN_TRAY_LEVEL] = { "LEVEL",       KIND_LEVEL,   0,                      20, 0, ROW_TRAY, IOSTOUCH_LEVEL_HOLD },
[BTN_TRAY_CTRL] = { "CONTROLS",     KIND_TRAY,    0,                      20, 0, ROW_TRAY },
[BTN_TRAY_KEYS] = { "KEYS",         KIND_TRAY,    IOSTOUCH_ACT_CONSOLE,   20, 0, ROW_TRAY },
[BTN_GYRO_MODE] = { "MODE",         KIND_TRAY,    0,                      20, 0, ROW_GYRO },
[BTN_GYRO_SENS] = { "SENS",         KIND_TRAY,    0,                      20, 0, ROW_GYRO },
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
static int look_sens_i = 2;
static int show_fps, swapped, show_cheat, cheat_on;
static int level_counting, level_index;
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
	show_cheat = (int)[d boolForKey:KEY_SHOW_CHEAT];
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
	UILabel *run_label;
	CAShapeLayer *run_link;
	UILabel *cheat_tags[2];      // under JUMP and USE while the cheat is on
	UILabel *toast;
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

	stick_ring = MakeCircle( IOSTOUCH_STICK_RADIUS, 0.08 );
	stick_knob = MakeCircle( IOSTOUCH_STICK_KNOB, 0.35 );
	run_marker = MakeCircle( IOSTOUCH_RUN_R, 0.12 );
	run_label = [[UILabel alloc] initWithFrame:run_marker.bounds];
	run_label.text = @"^^";
	run_label.textAlignment = NSTextAlignmentCenter;
	run_label.textColor = [UIColor whiteColor];
	run_label.font = [UIFont boldSystemFontOfSize:11];
	[run_marker addSubview:run_label];

	run_link = [[CAShapeLayer layer] retain];
	run_link.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
	run_link.lineWidth = 1.5;
	run_link.fillColor = [UIColor clearColor].CGColor;
	[self.layer addSublayer:run_link];

	[self addSubview:stick_ring];
	[self addSubview:run_marker];
	[self addSubview:stick_knob];
	stick_ring.hidden = stick_knob.hidden = run_marker.hidden = YES;
	run_link.hidden = YES;

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
	btn_lit[BTN_TRAY_CTRL] = swapped;
	btn_lit[BTN_TRAY_CHEAT] = show_cheat;
	btn_lit[BTN_CHEAT] = cheat_on;

	cheat_tags[0].hidden = cheat_tags[1].hidden = !cheat_on;
	cheat_tags[0].textColor = IOS_CheatNoclip( ) ? [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.3 blue:0.25 alpha:0.9];
	cheat_tags[1].textColor = IOS_CheatNotarget( ) ? [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.3 blue:0.25 alpha:0.9];

	// CHEAT: gold while the cheat is on
	btn_views[BTN_CHEAT].layer.borderColor = cheat_on ?
		[UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:1.0].CGColor : [UIColor colorWithWhite:0.6 alpha:0.6].CGColor;
	btn_labels[BTN_CHEAT].textColor = cheat_on ? [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:1.0] : [UIColor colorWithWhite:0.7 alpha:1.0];

	for( int i = 0; i < BTN_COUNT; i++ )
	{
		if( i == BTN_CHEAT )
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
	static const int tray[] = { BTN_TRAY_GYRO, BTN_TRAY_SENS, BTN_TRAY_FPS, BTN_TRAY_CHEAT, BTN_TRAY_LEVEL, BTN_TRAY_CTRL, BTN_TRAY_KEYS };
	CGFloat top = [self topRowY];
	int n = 0;

	for( int i = 0; i < BTN_COUNT; i++ )
	{
		int row = buttons[i].row;
		btn_shown[i] = row == ROW_MAIN || ( row == ROW_TRAY && tray_open ) || ( row == ROW_GYRO && tray_open && gyro_row_open );

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
	btn_views[i].backgroundColor = [UIColor colorWithWhite:1.0 alpha:on ? 0.4 : 0.15];

	if( !on && btn_rings[i] )
		btn_rings[i].strokeEnd = 0.0;
}

- (void)closeTray
{
	tray_open = gyro_row_open = 0;
	[self updateShown];
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
		run_marker.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
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
		run_marker.backgroundColor = [UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.8];
		return;
	}

	run_marker.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];

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
		break;
	case BTN_TRAY_FPS:
		show_fps = !show_fps;
		[[NSUserDefaults standardUserDefaults] setBool:show_fps forKey:KEY_SHOW_FPS];
		QueueAction( show_fps ? IOSTOUCH_ACT_SHOWFPS : IOSTOUCH_ACT_HIDEFPS );
		break;
	case BTN_TRAY_CTRL:
		swapped = !swapped;
		[[NSUserDefaults standardUserDefaults] setBool:swapped forKey:KEY_SWAPPED];
		[self layoutButtons];
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
		s->start = s->last = p;
		s->t0 = CACurrentMediaTime();

		b = [self buttonAt:p];

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
			[self look:s->last to:p];
			break;
		case ROLE_BUTTON:
			if( buttons[s->button].look )
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
			if( tap )
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
		case KIND_LEVEL:
			if( level_counting && !cancelled && !s->off )
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
	for( int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++ )
	{
		if( slots[i].touch )
			[self endTouch:slots[i].touch cancelled:1];
	}

	held_cmds = 0;
	look_yaw = look_pitch = 0;
	level_counting = 0;
	toast.hidden = YES;
	[self endStick];
	[self closeTray];
}

// once a frame: the hold rings, and what a finished hold does
- (void)updateHolds
{
	CFTimeInterval now = CACurrentMediaTime();

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
		case BTN_TRAY_GYRO:
			gyro_row_open = 1;
			[self updateShown];
			[self updateLabels];
			break;
		case BTN_CHEAT:
			[self setCheat:!cheat_on];
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
static int overlay_shown;

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

	ok = gyro_running && ( gyro_mode == GYRO_ALWAYS || [overlay gyroThumbDown] ) && !tray_open
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

		if( ingame != overlay_shown )
		{
			overlay_shown = ingame;
			overlay.hidden = !ingame;

			if( !ingame )
				[overlay releaseAll];
		}

		if( !CGRectEqualToRect( overlay.bounds, overlay->laid_out_for )
			|| !UIEdgeInsetsEqualToEdgeInsets( [overlay insets], overlay->laid_out_insets ))
			[overlay layoutButtons];

		if( overlay_shown )
			[overlay updateHolds];

		GyroFrame();
	}
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
