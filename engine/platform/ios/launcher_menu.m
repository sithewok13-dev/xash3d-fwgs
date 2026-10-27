/*
launcher_menu.m - iOS game picker for Half-Life, Opposing Force and Blue Shift
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

// Shown before the engine starts. Game data is never bundled: each game
// folder is copied by the user into the app's Documents folder (Files app,
// or Finder file sharing). The folders may also sit one level down, for
// example Documents/Half-Life/valve, as copied straight from Steam.

#import <UIKit/UIKit.h>
#include <stdlib.h>
#include <string.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include "launcher_menu.h"

typedef struct launcher_game_s
{
	const char *dir;      // game folder
	const char *lib;      // server library base name, see -dll @name
	const char *title;
	const char *subtitle;
	const char *marker;   // file that must exist in the game folder
	const char *source;   // where its folder comes from, NULL: Steam
} launcher_game_t;

static const launcher_game_t games[] =
{
{ "valve",   "hl",     "Half-Life",                  "1998",             "halflife.wad" },
{ "gearbox", "opfor",  "Half-Life: Opposing Force",  "Gearbox, 1999",    "pak0.pak" },
{ "bshift",  "bshift", "Half-Life: Blue Shift",      "Gearbox, 2001",    "pak0.pak" },
// cs16-client and ReGameDLL_CS (with the game's own bots); the data is the
// player's own Steam copy, as for the others
{ "cstrike", "cs",     "Counter-Strike",             "Valve, 2000",      "cstrike.wad" },
// multiplayer modes (arena, last man standing, instagib, CTF...): the
// library is ours, the folder comes from the free AG mod
{ "ag",      "ag",     "Multiplayer Modes",          "Adrenaline Gamer", "liblist.gam",
	"the free Adrenaline Gamer mod (AG 6.6 on ModDB, or OpenAG's full package at openag.pro)" },
};

#define NUM_GAMES ( sizeof( games ) / sizeof( games[0] ))

typedef enum
{
	GAME_READY,
	GAME_MISSING,        // no folder
	GAME_INCOMPLETE,     // folder without its game files
	GAME_NEEDS_VALVE,    // expansion present, Half-Life missing
} game_state_t;

static NSString *const kArgsKey = @"xashLaunchArgs";
static NSString *const kDefaultArgs = @"-log";

// case-insensitive child lookup, folders copied from Windows may differ in case
static NSString *FindChild( NSString *dir, NSString *name )
{
	NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];

	for( NSString *item in items )
	{
		if( [item caseInsensitiveCompare:name] == NSOrderedSame )
			return [dir stringByAppendingPathComponent:item];
	}

	return nil;
}

static BOOL IsDir( NSString *path )
{
	BOOL isdir = NO;
	return path && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isdir] && isdir;
}

static NSString *GameFolder( NSString *root, const launcher_game_t *g )
{
	NSString *path = FindChild( root, @( g->dir ));
	return IsDir( path ) ? path : nil;
}

static BOOL HasGameFiles( NSString *folder, const launcher_game_t *g )
{
	if( !FindChild( folder, @"liblist.gam" ) && !FindChild( folder, @"gameinfo.txt" ))
		return NO;

	if( FindChild( folder, @( g->marker )))
		return YES;

	// unpacked installs keep maps loose instead of in pak0.pak
	return IsDir( FindChild( folder, @"maps" ));
}

// Documents itself, or the first subfolder holding a valve folder
static NSString *FindDataRoot( NSString *docs )
{
	if( GameFolder( docs, &games[0] ))
		return docs;

	NSArray *items = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil]
		sortedArrayUsingSelector:@selector( caseInsensitiveCompare: )];

	for( NSString *item in items )
	{
		NSString *sub = [docs stringByAppendingPathComponent:item];

		if( IsDir( sub ) && GameFolder( sub, &games[0] ))
			return sub;
	}

	return docs;
}

static game_state_t GameState( NSString *root, const launcher_game_t *g )
{
	NSString *folder = GameFolder( root, g );

	if( !folder )
		return GAME_MISSING;

	if( !HasGameFiles( folder, g ))
		return GAME_INCOMPLETE;

	if( g != &games[0] )
	{
		NSString *valve = GameFolder( root, &games[0] );

		if( !valve || !HasGameFiles( valve, &games[0] ))
			return GAME_NEEDS_VALVE;
	}

	return GAME_READY;
}

// For multiplayer: the addresses friends can join this device at, its
// Wi-Fi one and its Tailscale one (100.64.0.0/10, on a utun interface)
static NSString *JoinAddresses( void )
{
	struct ifaddrs *list = NULL, *i;
	NSString *wifi = nil, *tailscale = nil;

	if( getifaddrs( &list ) != 0 )
		return nil;

	for( i = list; i; i = i->ifa_next )
	{
		char text[INET_ADDRSTRLEN];
		uint32_t a;

		if( !i->ifa_addr || i->ifa_addr->sa_family != AF_INET || !( i->ifa_flags & IFF_UP ))
			continue;

		a = ntohl((( struct sockaddr_in *)i->ifa_addr )->sin_addr.s_addr );
		if( !inet_ntop( AF_INET, &(( struct sockaddr_in *)i->ifa_addr )->sin_addr, text, sizeof( text )))
			continue;

		if( !wifi && !strcmp( i->ifa_name, "en0" ))
			wifi = [NSString stringWithUTF8String:text];
		else if( !tailscale && !strncmp( i->ifa_name, "utun", 4 ) && ( a & 0xFFC00000 ) == 0x64400000 )
			tailscale = [NSString stringWithUTF8String:text];
	}

	freeifaddrs( list );

	if( wifi && tailscale )
		return [NSString stringWithFormat:@"Multiplayer: friends join this %@ at %@ (Wi-Fi) or %@ (Tailscale).", [UIDevice currentDevice].model, wifi, tailscale];
	if( wifi || tailscale )
		return [NSString stringWithFormat:@"Multiplayer: friends join this %@ at %@ (%@).", [UIDevice currentDevice].model, wifi ? wifi : tailscale, wifi ? @"Wi-Fi" : @"Tailscale"];
	return nil;
}

// ---------------------------------------------------------------- AG modes

// The Multiplayer Modes card's modes. Each is a gamemode config of our own
// (gamemodes/mm_<name>.cfg in the ag folder, written by the launcher, so
// AG's own configs are never touched) that sets everything it depends on,
// so one mode's settings never leak into the next.
typedef struct
{
	const char *name;   // mm_<name>
	const char *title;
	const char *about;
	const char *settings;
} ag_mode_t;

#define AG_NO_PICKUPS \
	"sv_ag_ban_crowbar 1\nsv_ag_ban_glock 1\nsv_ag_ban_357 1\nsv_ag_ban_mp5 1\nsv_ag_ban_shotgun 1\n" \
	"sv_ag_ban_crossbow 1\nsv_ag_ban_rpg 1\nsv_ag_ban_gauss 1\nsv_ag_ban_egon 1\nsv_ag_ban_hornet 1\n" \
	"sv_ag_ban_hgrenade 1\nsv_ag_ban_satchel 1\nsv_ag_ban_tripmine 1\nsv_ag_ban_snark 1\nsv_ag_ban_m203 1\n" \
	"sv_ag_ban_9mmar 1\nsv_ag_ban_bockshot 1\nsv_ag_ban_uranium 1\nsv_ag_ban_bolts 1\nsv_ag_ban_rockets 1\n" \
	"sv_ag_ban_357ammo 1\n"
#define AG_NO_START \
	"sv_ag_start_crowbar 0\nsv_ag_start_glock 0\nsv_ag_start_9mmar 0\n"
#define AG_TEAMS "mp_teamplay 1\nmp_teamlist \"blue;red\"\n"

static const ag_mode_t ag_modes[] =
{
{ "ffa",      "Deathmatch",         "Everyone for themselves", "" },
{ "tdm",      "Team Deathmatch",    "Blue against red", AG_TEAMS },
{ "arena",    "Arena",              "One on one, the winner stays in", "sv_ag_gametype arena\n" },
{ "lms",      "Last Man Standing",  "No respawns: the last one alive wins the round", "sv_ag_gametype lms\n" },
{ "instagib", "Instagib",           "Tau cannons that kill in one hit", "sv_ag_gametype instagib\n" AG_NO_PICKUPS AG_NO_START
	"sv_ag_start_gauss 1\nsv_ag_start_uranium 100\n" },
{ "gungame",  "Gun Game",           "Each kill moves you to the next weapon; win with the crowbar", "sv_ag_gametype gungame\n" AG_NO_PICKUPS AG_NO_START },
{ "lowgrav",  "Low Gravity",        "Deathmatch on the moon", "sv_gravity 200\n" },
{ "crowbar",  "Crowbars Only",      "Deathmatch with crowbars", AG_NO_PICKUPS AG_NO_START "sv_ag_start_crowbar 1\n" },
{ "snarks",   "Snarks Only",        "Deathmatch with snarks (and a crowbar)", AG_NO_PICKUPS AG_NO_START "sv_ag_start_crowbar 1\nsv_ag_start_snark 15\n" },
{ "rockets",  "Rockets Only",       "Deathmatch with RPGs (and a crowbar)", AG_NO_PICKUPS AG_NO_START "sv_ag_start_crowbar 1\nsv_ag_start_rpg 1\nsv_ag_start_rockets 5\n" },
{ "ctf",      "Capture the Flag",   "Needs CTF maps (agctf_...)", "sv_ag_gametype ctf\n" AG_TEAMS },
{ "dom",      "Domination",         "Needs domination maps (agdom_...)", "sv_ag_gametype dom\n" AG_TEAMS },
};

#define NUM_AG_MODES ( sizeof( ag_modes ) / sizeof( ag_modes[0] ))

// what every mode starts from: AG's defaults
static NSString *const kAgBase =
	@"sv_ag_gametype \"\"\n"
	@"mp_teamplay 0\n"
	@"sv_gravity 800\n"
	@"mp_weaponstay 0\n"
	@"sv_ag_ban_crowbar 0\nsv_ag_ban_glock 0\nsv_ag_ban_357 0\nsv_ag_ban_mp5 0\nsv_ag_ban_shotgun 0\n"
	@"sv_ag_ban_crossbow 0\nsv_ag_ban_rpg 0\nsv_ag_ban_gauss 0\nsv_ag_ban_egon 0\nsv_ag_ban_hornet 0\n"
	@"sv_ag_ban_hgrenade 0\nsv_ag_ban_satchel 0\nsv_ag_ban_tripmine 0\nsv_ag_ban_snark 0\nsv_ag_ban_m203 0\n"
	@"sv_ag_ban_9mmar 0\nsv_ag_ban_bockshot 0\nsv_ag_ban_uranium 0\nsv_ag_ban_bolts 0\nsv_ag_ban_rockets 0\n"
	@"sv_ag_ban_357ammo 0\n"
	@"sv_ag_start_crowbar 1\nsv_ag_start_glock 1\nsv_ag_start_357 0\nsv_ag_start_mp5 0\nsv_ag_start_shotgun 0\n"
	@"sv_ag_start_crossbow 0\nsv_ag_start_rpg 0\nsv_ag_start_gauss 0\nsv_ag_start_egon 0\nsv_ag_start_hornet 0\n"
	@"sv_ag_start_hgrenade 0\nsv_ag_start_satchel 0\nsv_ag_start_tripmine 0\nsv_ag_start_snark 0\nsv_ag_start_m203 0\n"
	@"sv_ag_start_9mmar 68\nsv_ag_start_bockshot 0\nsv_ag_start_uranium 0\nsv_ag_start_bolts 0\nsv_ag_start_rockets 0\n"
	@"sv_ag_start_357ammo 0\nsv_ag_start_health 100\nsv_ag_start_armour 0\n";

// ---------------------------------------------------------------- co-op

// Half-Life co-op: the chapters to host from (as in LEVEL, ios_cheats.c)
static const struct { const char *title, *map; } coop_chapters[] =
{
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
};

#define NUM_COOP_CHAPTERS ( sizeof( coop_chapters ) / sizeof( coop_chapters[0] ))
#define COOP_PLAYERS "4"

// a chapter whose first map isn't there (a pak install keeps no loose
// maps, so then all of them are offered)
static BOOL HasMap( NSString *gamedir, const char *map )
{
	NSString *maps = FindChild( gamedir, @"maps" );

	if( !maps )
		return YES;

	return FindChild( maps, [NSString stringWithFormat:@"%s.bsp", map] ) != nil;
}

// (re)writes our mode configs into the ag folder's gamemodes
static BOOL WriteAgModes( NSString *agdir )
{
	NSString *dir = FindChild( agdir, @"gamemodes" ) ?: [agdir stringByAppendingPathComponent:@"gamemodes"];
	BOOL ok = YES;

	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

	for( int i = 0; i < (int)NUM_AG_MODES; i++ )
	{
		const ag_mode_t *m = &ag_modes[i];
		// AG reads the first two lines as the mode's name and description
		NSString *text = [NSString stringWithFormat:@"// %s\n// %s\n%@%s", m->title, m->about, kAgBase, m->settings];
		NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"mm_%s.cfg", m->name]];

		ok = [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil] && ok;
	}

	return ok;
}

// the co-op server library is in the app (an optional part of the build)
static BOOL HasCoopLibrary( void )
{
	NSString *lib = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"valve/dlls/hlcoop_ios_arm64.dylib"];
	return [[NSFileManager defaultManager] fileExistsAtPath:lib];
}

// The 25th anniversary update (2023) added the hldemo chapter to valve
static BOOL IsAnniversaryData( NSString *root )
{
	NSString *maps = FindChild( GameFolder( root, &games[0] ), @"maps" );
	return maps && FindChild( maps, @"hldemo1.bsp" ) != nil;
}

@interface XashLauncherController : UIViewController
{
@public
	NSString *docs;
	NSString *root;
	UIStackView *cards;
	UILabel *footer;
	int chosen;
	NSString *agmode; // the Multiplayer Modes card's mode, nil: just start
	NSString *coopmap; // Half-Life co-op: the map to host, nil: not co-op
}
@end

@implementation XashLauncherController

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskLandscape;
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	chosen = -1;
	self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:1.0];

	UILabel *title = [[UILabel alloc] init];
	title.text = @"Choose a game";
	title.textColor = [UIColor whiteColor];
	title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];

	cards = [[UIStackView alloc] init];
	cards.axis = UILayoutConstraintAxisHorizontal;
	cards.distribution = UIStackViewDistributionFillEqually;
	cards.spacing = 12;

	footer = [[UILabel alloc] init];
	footer.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
	footer.font = [UIFont systemFontOfSize:13];
	footer.numberOfLines = 4;

	UIButton *options = [UIButton buttonWithType:UIButtonTypeSystem];
	[options setTitle:@"Options" forState:UIControlStateNormal];
	[options addTarget:self action:@selector( showOptions ) forControlEvents:UIControlEventTouchUpInside];

	UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[footer, options]];
	bottom.spacing = 12;
	bottom.alignment = UIStackViewAlignmentCenter;
	[options setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	UIStackView *page = [[UIStackView alloc] initWithArrangedSubviews:@[title, cards, bottom]];
	page.axis = UILayoutConstraintAxisVertical;
	page.spacing = 16;
	page.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:page];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[page.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
		[page.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
		[page.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
		[page.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
	]];

	// files may be copied in with the Files app while we're open
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( refresh )
		name:UIApplicationDidBecomeActiveNotification object:nil];

	[self refresh];
}

- (NSString *)statusText:(game_state_t)state game:(const launcher_game_t *)g
{
	switch( state )
	{
	case GAME_READY:
		if( g == &games[0] && IsAnniversaryData( root ))
			return @"Ready · 25th anniversary data";
		return @"Ready";
	case GAME_MISSING:
		if( g->source )
			return [NSString stringWithFormat:@"Optional: copy the \"%s\" folder (tap for where from)", g->dir];
		return [NSString stringWithFormat:@"Not installed: copy the \"%s\" folder", g->dir];
	case GAME_INCOMPLETE:
		return [NSString stringWithFormat:@"The \"%s\" folder is incomplete", g->dir];
	case GAME_NEEDS_VALVE:
		return @"Also needs Half-Life (\"valve\" folder)";
	}

	return @"";
}

- (void)refresh
{
	[root release];
	root = [FindDataRoot( docs ) retain];

	for( UIView *v in [[cards.arrangedSubviews copy] autorelease] )
	{
		[cards removeArrangedSubview:v];
		[v removeFromSuperview];
	}

	for( int i = 0; i < (int)NUM_GAMES; i++ )
	{
		const launcher_game_t *g = &games[i];
		game_state_t state = GameState( root, g );
		BOOL ready = state == GAME_READY;

		UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
		card.tag = i;
		card.layer.cornerRadius = 14;
		card.layer.borderWidth = 1;
		card.layer.borderColor = ( ready ? [UIColor colorWithRed:1.0 green:0.6 blue:0.1 alpha:0.9] : [UIColor colorWithWhite:0.3 alpha:1.0] ).CGColor;
		card.backgroundColor = [UIColor colorWithWhite:ready ? 0.15 : 0.10 alpha:1.0];
		[card addTarget:self action:@selector( cardTapped: ) forControlEvents:UIControlEventTouchUpInside];

		UILabel *name = [[UILabel alloc] init];
		name.text = @( g->title );
		name.numberOfLines = 2;
		name.textColor = ready ? [UIColor whiteColor] : [UIColor colorWithWhite:0.55 alpha:1.0];
		name.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
		// five cards on a phone: the text shrinks rather than cut off
		name.adjustsFontSizeToFitWidth = YES;
		name.minimumScaleFactor = 0.6;

		UILabel *sub = [[UILabel alloc] init];
		sub.text = @( g->subtitle );
		sub.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
		sub.font = [UIFont systemFontOfSize:13];

		UILabel *status = [[UILabel alloc] init];
		status.text = [self statusText:state game:g];
		status.numberOfLines = 3;
		status.textColor = ready ? [UIColor colorWithRed:0.45 green:0.85 blue:0.45 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.65 blue:0.3 alpha:1.0];
		status.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
		status.adjustsFontSizeToFitWidth = YES;
		status.minimumScaleFactor = 0.7;

		UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[name, sub, [[UIView alloc] init], status]];
		text.axis = UILayoutConstraintAxisVertical;
		text.spacing = 4;
		text.userInteractionEnabled = NO;
		text.translatesAutoresizingMaskIntoConstraints = NO;
		[card addSubview:text];

		[NSLayoutConstraint activateConstraints:@[
			[text.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
			[text.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
			[text.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
			[text.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
		]];

		[cards addArrangedSubview:card];
	}

	NSString *where = [root isEqualToString:docs] ? @"" :
		[NSString stringWithFormat:@" (found in \"%@\")", [root lastPathComponent]];
	footer.text = [NSString stringWithFormat:@"Game files go in Files › On My %@ › %@%@.",
		[UIDevice currentDevice].model,
		[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"this app", where];

	NSString *join = JoinAddresses();
	if( join )
		footer.text = [footer.text stringByAppendingFormat:@"\n%@", join];
}

- (void)cardTapped:(UIButton *)card
{
	const launcher_game_t *g = &games[card.tag];
	game_state_t state = GameState( root, g );

	if( state == GAME_READY && !strcmp( g->dir, "ag" ))
	{
		[self pickAgMode:card];
		return;
	}

	if( state == GAME_READY && !strcmp( g->dir, "valve" ) && HasCoopLibrary( ))
	{
		[self pickHalfLife:card];
		return;
	}

	if( state == GAME_READY )
	{
		chosen = (int)card.tag;
		return;
	}

	NSString *msg;
	NSString *steam = @"On your computer it is in Steam › steamapps › common › Half-Life.";

	switch( state )
	{
	case GAME_NEEDS_VALVE:
		msg = [NSString stringWithFormat:@"%s runs on top of Half-Life, so it also needs the \"valve\" folder.\n\nCopy \"valve\" next to \"%s\". %@", g->title, g->dir, steam];
		break;
	case GAME_INCOMPLETE:
		msg = [NSString stringWithFormat:@"The \"%s\" folder is there but has no game files (liblist.gam and %s). Copy the whole folder again; a copy that is still running in the Files app also looks like this. %@", g->dir, g->marker, steam];
		break;
	default:
		if( g->source )
		{
			msg = [NSString stringWithFormat:@"%s is optional. Its \"%s\" folder comes from %s: download it on a computer and copy the \"%s\" folder next to \"valve\" in this app's folder in the Files app (On My %@ › %@). Only its data is used; the game code is already in the app.\n\nThis screen updates by itself when you come back.",
				g->title, g->dir, g->source, g->dir, [UIDevice currentDevice].model,
				[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"this app"];
			break;
		}
		msg = [NSString stringWithFormat:@"Copy the \"%s\" folder from your own copy of %s into this app's folder in the Files app (On My %@ › %@). %@\n\nThis screen updates by itself when you come back.", g->dir, g->title, [UIDevice currentDevice].model,
			[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"this app", steam];
		break;
	}

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%s isn't ready", g->title]
		message:msg preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

// Half-Life: single player, or co-op (host a chapter, or join a friend)
- (void)pickHalfLife:(UIButton *)card
{
	int index = (int)card.tag;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Half-Life"
		message:@"Co-op: up to " COOP_PLAYERS @" players through the campaign. Whoever reaches a level change takes everyone along; a fallen player comes back next to a teammate. Co-op games can't be saved: host again from the chapter you reached."
		preferredStyle:UIAlertControllerStyleActionSheet];

	[sheet addAction:[UIAlertAction actionWithTitle:@"Single player" style:UIAlertActionStyleDefault handler:^( UIAlertAction *a ) {
		chosen = index;
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Co-op: host a chapter" style:UIAlertActionStyleDefault handler:^( UIAlertAction *a ) {
		[self pickCoopChapter:card];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Co-op: join a friend (Multiplayer › Internet/LAN game)" style:UIAlertActionStyleDefault handler:^( UIAlertAction *a ) {
		chosen = index;
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

	sheet.popoverPresentationController.sourceView = card;
	sheet.popoverPresentationController.sourceRect = card.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)pickCoopChapter:(UIButton *)card
{
	int index = (int)card.tag;
	NSString *gamedir = GameFolder( root, &games[index] );
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Co-op: host a chapter"
		message:@"Friends join with Multiplayer › Internet/LAN game, or Add server with the address under the games."
		preferredStyle:UIAlertControllerStyleActionSheet];

	for( int i = 0; i < (int)NUM_COOP_CHAPTERS; i++ )
	{
		NSString *map = @( coop_chapters[i].map );

		if( !HasMap( gamedir, coop_chapters[i].map ))
			continue;

		[sheet addAction:[UIAlertAction actionWithTitle:@( coop_chapters[i].title ) style:UIAlertActionStyleDefault handler:^( UIAlertAction *a ) {
			[coopmap release];
			coopmap = [map retain];
			chosen = index;
		}]];
	}

	[sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

	sheet.popoverPresentationController.sourceView = card;
	sheet.popoverPresentationController.sourceRect = card.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

// Multiplayer Modes: which mode to host, or just start (to join a game)
- (void)pickAgMode:(UIButton *)card
{
	int index = (int)card.tag;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Multiplayer Modes"
		message:@"Pick a mode, then Multiplayer › Create game to host it. To join a friend's game, the mode is theirs."
		preferredStyle:UIAlertControllerStyleActionSheet];

	[sheet addAction:[UIAlertAction actionWithTitle:@"Join a game" style:UIAlertActionStyleDefault handler:^( UIAlertAction *a ) {
		chosen = index;
	}]];

	for( int i = 0; i < (int)NUM_AG_MODES; i++ )
	{
		const ag_mode_t *m = &ag_modes[i];

		[sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%s — %s", m->title, m->about]
			style:UIAlertActionStyleDefault handler:^( UIAlertAction *a ) {
			NSString *agdir = GameFolder( root, &games[index] );

			if( !agdir || !WriteAgModes( agdir ))
			{
				UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't set up the modes"
					message:@"The modes' settings couldn't be written into the \"ag\" folder." preferredStyle:UIAlertControllerStyleAlert];
				[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
				[self presentViewController:alert animated:YES completion:nil];
				return;
			}

			[agmode release];
			agmode = [[NSString alloc] initWithFormat:@"mm_%s", m->name];
			chosen = index;
		}]];
	}

	[sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

	// an iPad shows it as a popover from the card
	sheet.popoverPresentationController.sourceView = card;
	sheet.popoverPresentationController.sourceRect = card.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)showOptions
{
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Launch options"
		message:@"Extra engine command line, for example -dev 2 -log" preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^( UITextField *field ) {
		field.text = [[NSUserDefaults standardUserDefaults] stringForKey:kArgsKey] ?: kDefaultArgs;
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^( UIAlertAction *action ) {
		[[NSUserDefaults standardUserDefaults] setObject:alert.textFields.firstObject.text forKey:kArgsKey];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end

// iOS hides an app's folder in the Files app while it's empty, so a note
// on what goes there keeps it visible from the first launch
static void WriteHowTo( NSString *docs )
{
	NSString *path = [docs stringByAppendingPathComponent:@"Copy game folders here.txt"];
	NSString *text = @"Copy your game folders into this folder (next to this file):\n\n"
		@"  valve    - Half-Life (needed by all the others)\n"
		@"  gearbox  - Half-Life: Opposing Force\n"
		@"  bshift   - Half-Life: Blue Shift\n"
		@"  cstrike  - Counter-Strike (Steam > steamapps > common > Half-Life too)\n"
		@"  ag       - Multiplayer Modes, optional (from the free Adrenaline Gamer mod)\n\n"
		@"They are in Steam > steamapps > common > Half-Life on your computer.\n"
		@"Copying the whole Half-Life folder here also works.\n";

	if( ![[NSFileManager defaultManager] fileExistsAtPath:path] )
		[text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

char **IOS_RunLauncher( const char *docsdir, int *argc )
{
	WriteHowTo( @( docsdir ));

	UIWindow *window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	XashLauncherController *menu = [[XashLauncherController alloc] init];
	NSMutableArray *args = [NSMutableArray array];

	menu->docs = [@( docsdir ) retain];
	window.rootViewController = menu;
	[window makeKeyAndVisible];

	@autoreleasepool {
		while( menu->chosen < 0 )
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
	}

	const launcher_game_t *g = &games[menu->chosen];

	// the engine reads its base directory from here, see FS_DetermineRootDirectory
	setenv( "XASH3D_BASEDIR", [menu->root fileSystemRepresentation], 1 );

	// Pick the server library by name: liblist.gam files from different Steam
	// releases name it differently, ours are always <lib>_ios_arm64.dylib.
	// Co-op has its own (hlcoop), the vanilla one stays as it is.
	[args addObjectsFromArray:@[@"-game", @( g->dir ), @"-dll", [NSString stringWithFormat:@"@%s", menu->coopmap ? "hlcoop" : g->lib]]];

	// co-op host: a coop server on the chapter's map
	if( menu->coopmap )
		[args addObjectsFromArray:@[@"+maxplayers", @COOP_PLAYERS, @"+coop", @"1", @"+deathmatch", @"0", @"+map", menu->coopmap]];

	// Multiplayer Modes: the mode the server starts in
	if( menu->agmode )
		[args addObjectsFromArray:@[@"+sv_ag_gamemode", menu->agmode]];

	NSString *extra = [[NSUserDefaults standardUserDefaults] stringForKey:kArgsKey] ?: kDefaultArgs;
	for( NSString *arg in [extra componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] )
	{
		if( arg.length )
			[args addObject:arg];
	}

	window.hidden = YES;
	[[NSNotificationCenter defaultCenter] removeObserver:menu];

	// argv[0] is left empty like the old dialog did
	char **argv = calloc( args.count + 2, sizeof( char * ));
	for( NSUInteger i = 0; i < args.count; i++ )
		argv[i + 1] = strdup( [args[i] UTF8String] );

	*argc = (int)args.count + 1;
	return argv;
}
