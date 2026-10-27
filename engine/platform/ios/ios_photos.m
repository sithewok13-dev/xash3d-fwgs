/*
ios_photos.m - saves the photo mode's shots to Photos
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

// From the Jedi Knight port's iosPhotos.m: PNG on a serial queue, saved to
// Photos with add-only access, or to Files (Documents/Screenshots) when that
// access is off or the save fails. The engine writes each frame as a BMP
// (fast, uncompressed); it's read back here and the file removed at once.
// The HUD+BTNS kind draws the touch overlay over the frame.

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#include "ios_touch.h"

static dispatch_queue_t IOSPhotos_Queue( void )
{
	static dispatch_queue_t q;
	static dispatch_once_t once;

	dispatch_once( &once, ^{
		q = dispatch_queue_create( "xash3d.photos", dispatch_queue_attr_make_with_qos_class( DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0 ));
	});

	return q;
}

// counts for the one line said once nothing more is being saved
static int num_pending, batch, num_photos, num_files, num_failed, photos_off, batch_shot;

static void IOSPhotos_Report( void )
{
	NSMutableArray *parts = [NSMutableArray array];

	if( num_pending > 0 || batch )
		return;

	if( num_photos )
		[parts addObject:num_photos == 1 ? @"1 photo saved" : [NSString stringWithFormat:@"%d photos saved", num_photos]];
	if( num_files )
		[parts addObject:[NSString stringWithFormat:@"%d saved to Files (%@)", num_files, photos_off ? @"Photos access is off" : @"Photos didn't take them"]];
	if( num_failed )
		[parts addObject:[NSString stringWithFormat:@"%d couldn't be saved", num_failed]];

	if( parts.count )
		IOSTouch_ShowMessage( [[parts componentsJoinedByString:@", "] UTF8String] );

	num_photos = num_files = num_failed = photos_off = 0;
}

static void IOSPhotos_Finish( int to_photos, int to_files, int failed, int off )
{
	dispatch_async( dispatch_get_main_queue( ), ^{
		num_photos += to_photos;
		num_files += to_files;
		num_failed += failed;
		photos_off |= off;
		if( num_pending > 0 )
			num_pending--;
		IOSPhotos_Report( );
	});
}

void IOSPhotos_SetBatch( int on )
{
	batch = on != 0;
	if( on )
		batch_shot = 0;
	IOSPhotos_Report( );
}

void IOSPhotos_AskAccess( void )
{
	if( @available( iOS 14.0, * ))
	{
		if( [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly] == PHAuthorizationStatusNotDetermined )
			[PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^( PHAuthorizationStatus status ) {}];
	}
}

static NSString *IOSPhotos_BaseName( NSDate *when )
{
	static NSString *last;
	static int same;
	NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
	NSString *app = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	NSString *base;

	f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	f.dateFormat = @"yyyy-MM-dd HH.mm.ss";

	if( ![app isKindOfClass:[NSString class]] || !app.length )
		app = @"Xash3D";

	base = [NSString stringWithFormat:@"%@ %@", app, [f stringFromDate:when]];

	// a second photo in the same second gets "-2", "-3"...
	if( last && [last isEqualToString:base] )
		same++;
	else
	{
		[last release];
		last = [base retain];
		same = 1;
	}

	return same > 1 ? [NSString stringWithFormat:@"%@-%d", base, same] : base;
}

static int IOSPhotos_SaveToFiles( NSData *data, NSString *name )
{
	NSString *docs = NSSearchPathForDirectoriesInDomains( NSDocumentDirectory, NSUserDomainMask, YES ).firstObject;
	NSString *dir;

	if( !docs )
		return 0;

	dir = [docs stringByAppendingPathComponent:@"Screenshots"];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return [data writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES] ? 1 : 0;
}

static NSData *IOSPhotos_Png( CGImageRef img )
{
	NSMutableData *data = [NSMutableData data];
	CGImageDestinationRef dst = CGImageDestinationCreateWithData( (CFMutableDataRef)data, CFSTR( "public.png" ), 1, NULL );
	BOOL ok;

	if( !dst )
		return nil;

	CGImageDestinationAddImage( dst, img, NULL );
	ok = CGImageDestinationFinalize( dst );
	CFRelease( dst );
	return ok ? data : nil;
}

static CGImageRef IOSPhotos_WithOverlay( CGImageRef frame )
{
	UIView *overlay = IOSTouch_OverlayView( );
	size_t w = CGImageGetWidth( frame ), h = CGImageGetHeight( frame );
	UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
	UIGraphicsImageRenderer *r;
	UIImage *out;

	fmt.scale = 1.0;
	fmt.opaque = YES;
	fmt.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
	r = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake( w, h ) format:fmt] autorelease];

	out = [r imageWithActions:^( UIGraphicsImageRendererContext *ctx ) {
		CGContextRef c = ctx.CGContext;
		[[UIImage imageWithCGImage:frame] drawInRect:CGRectMake( 0, 0, w, h )];
		if( overlay && !overlay.hidden && overlay.bounds.size.width > 0 && overlay.bounds.size.height > 0 )
		{
			CGContextSaveGState( c );
			CGContextScaleCTM( c, w / overlay.bounds.size.width, h / overlay.bounds.size.height );
			[overlay.layer renderInContext:c];
			CGContextRestoreGState( c );
		}
	}];

	return CGImageRetain( out.CGImage );
}

// main thread, from the engine at the end of the frame it wrote to path
void IOSPhotos_SaveFile( const char *path, int kind, int burst )
{
	@autoreleasepool
	{
		NSString *file = @( path );
		NSData *bmp = [NSData dataWithContentsOfFile:file];
		CGImageSourceRef src;
		CGImageRef img = NULL;
		NSString *suffix, *name;

		[[NSFileManager defaultManager] removeItemAtPath:file error:nil];

		if( bmp && ( src = CGImageSourceCreateWithData( (CFDataRef)bmp, NULL )))
		{
			NSDictionary *opts = @{ (NSString *)kCGImageSourceShouldCacheImmediately: @YES };
			img = CGImageSourceCreateImageAtIndex( src, 0, (CFDictionaryRef)opts );
			CFRelease( src );
		}

		num_pending++;

		if( !img )
		{
			IOSPhotos_Finish( 0, 0, 1, 0 );
			return;
		}

		if( kind == IOSTOUCH_PHOTO_HUDBTNS )
		{
			CGImageRef with = IOSPhotos_WithOverlay( img );
			CGImageRelease( img );
			img = with;
		}

		// the flash, the shutter and a tap, now the frame is taken
		IOSTouch_CameraFeedback( burst );

		suffix = kind == IOSTOUCH_PHOTO_CLEAN ? @"clean" : ( kind == IOSTOUCH_PHOTO_HUD ? @"hud" : @"hud+buttons" );
		name = IOSPhotos_BaseName( [NSDate date] );
		if( batch )
			name = [name stringByAppendingFormat:@" %02d", ++batch_shot];
		name = [[NSString stringWithFormat:@"%@ %@.png", name, suffix] retain];

		dispatch_async( IOSPhotos_Queue( ), ^{
			@autoreleasepool
			{
				NSData *png = IOSPhotos_Png( img );
				NSDate *when = [NSDate date];
				int allowed = 0;

				CGImageRelease( img );

				if( !png )
				{
					IOSPhotos_Finish( 0, 0, 1, 0 );
					[name release];
					return;
				}

				// add-only access is iOS 14 and later; before that, Files
				if( @available( iOS 14.0, * ))
				{
					PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
					allowed = st == PHAuthorizationStatusAuthorized || st == PHAuthorizationStatusLimited;
				}

				if( !allowed )
				{
					int k = IOSPhotos_SaveToFiles( png, name );
					IOSPhotos_Finish( 0, k, 1 - k, 1 );
					[name release];
					return;
				}

				[png retain];
				[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
					PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
					PHAssetResourceCreationOptions *opt = [[[PHAssetResourceCreationOptions alloc] init] autorelease];
					opt.originalFilename = name;
					[req addResourceWithType:PHAssetResourceTypePhoto data:png options:opt];
					req.creationDate = when;
				} completionHandler:^( BOOL ok, NSError *err ) {
					if( ok )
						IOSPhotos_Finish( 1, 0, 0, 0 );
					else
					{
						int k = IOSPhotos_SaveToFiles( png, name );
						IOSPhotos_Finish( 0, k, 1 - k, 0 );
					}
					[png release];
					[name release];
				}];
			}
		});
	}
}
