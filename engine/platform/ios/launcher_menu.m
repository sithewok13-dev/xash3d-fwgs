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
#include "launcher_menu.h"

typedef struct launcher_game_s
{
	const char *dir;      // game folder
	const char *lib;      // server library base name, see -dll @name
	const char *title;
	const char *subtitle;
	const char *marker;   // file that must exist in the game folder
} launcher_game_t;

static const launcher_game_t games[] =
{
{ "valve",   "hl",     "Half-Life",                  "1998",             "halflife.wad" },
{ "gearbox", "opfor",  "Half-Life: Opposing Force",  "Gearbox, 1999",    "pak0.pak" },
{ "bshift",  "bshift", "Half-Life: Blue Shift",      "Gearbox, 2001",    "pak0.pak" },
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
	cards.spacing = 16;

	footer = [[UILabel alloc] init];
	footer.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
	footer.font = [UIFont systemFontOfSize:13];
	footer.numberOfLines = 2;

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

		UILabel *sub = [[UILabel alloc] init];
		sub.text = @( g->subtitle );
		sub.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
		sub.font = [UIFont systemFontOfSize:13];

		UILabel *status = [[UILabel alloc] init];
		status.text = [self statusText:state game:g];
		status.numberOfLines = 3;
		status.textColor = ready ? [UIColor colorWithRed:0.45 green:0.85 blue:0.45 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.65 blue:0.3 alpha:1.0];
		status.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];

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
}

- (void)cardTapped:(UIButton *)card
{
	const launcher_game_t *g = &games[card.tag];
	game_state_t state = GameState( root, g );

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
		msg = [NSString stringWithFormat:@"Copy the \"%s\" folder from your own copy of %s into this app's folder in the Files app (On My %@ › %@). %@\n\nThis screen updates by itself when you come back.", g->dir, g->title, [UIDevice currentDevice].model,
			[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"this app", steam];
		break;
	}

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%s isn't ready", g->title]
		message:msg preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
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
		@"  valve    - Half-Life (needed by all three games)\n"
		@"  gearbox  - Half-Life: Opposing Force\n"
		@"  bshift   - Half-Life: Blue Shift\n\n"
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
	// releases name it differently, ours are always <lib>_ios_arm64.dylib
	[args addObjectsFromArray:@[@"-game", @( g->dir ), @"-dll", [NSString stringWithFormat:@"@%s", g->lib]]];

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
