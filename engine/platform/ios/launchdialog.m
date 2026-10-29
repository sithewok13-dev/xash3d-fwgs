/*
 launchdialog.m - iOS lauch dialog
 Copyright (C) 2016 mittorn
 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include "launcher_menu.h"

#define XASHLIB "@rpath/libxash.dylib"

int szArgc;
char **szArgv;
float g_iOSVer;

const char *IOS_GetDocsDir( void )
{
	static const char *dir = NULL;
	
	if( dir )
		return dir;
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirctory = [paths objectAtIndex:0];
	[[NSFileManager defaultManager] createDirectoryAtPath:documentsDirctory withIntermediateDirectories:YES attributes:nil error:nil];
	
	dir = strdup( [documentsDirctory fileSystemRepresentation] ); // autoreleased storage
	NSLog(@"IOS_GetDocsDir: %s", dir);
	
	return dir;
}

const char *IOS_GetExecDir( void )
{
	static const char *dir = NULL;
	
	if( dir )
		return dir;
	
	NSString *executableDirctory = [[NSBundle mainBundle] bundlePath];
	
	dir = strdup( [executableDirctory fileSystemRepresentation] ); // autoreleased storage
	NSLog(@"IOS_GetExecDir: %s", dir);
	
	return dir;
}


void IOS_LaunchDialog( void )
{
	NSLog(@"System Version is %@",[[UIDevice currentDevice] systemVersion]);
	NSString *ver = [[UIDevice currentDevice] systemVersion];
	g_iOSVer = [ver floatValue];

	//request microphone permissions otherwise we will crash when joining an online server
	[[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted){}];

	const char *docsDir = IOS_GetDocsDir();

	//set working directory to documents so logs can be generated there
	[[NSFileManager defaultManager] 
	changeCurrentDirectoryPath:[NSString stringWithUTF8String:IOS_GetDocsDir()]];

	// game picker for HL, OF and BS replaces the launch options dialog
	szArgv = IOS_RunLauncher( docsDir, &szArgc );
}

void IOS_SwitchDialog( void )
{
	IOS_RunSwitch( IOS_GetDocsDir( ));
}

char *IOS_GetUDID( void )
{
	static char udid[256];
	NSString *id = [[[UIDevice currentDevice]identifierForVendor] UUIDString];
	strncpy( udid, [id UTF8String], 255 );
	return udid;
}

void IOS_Log( const char *text )
{
	NSLog(@"Xash: %@", [NSString stringWithUTF8String:text]);
}

int IOS_GetArgs( char ***out )
{
	*out = szArgv;
	return szArgc;
}
