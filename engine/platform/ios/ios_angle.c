/*
ios_angle.c - OpenGL ES 3.0 on Metal through ANGLE, for the iOS port

Apple's OpenGL ES is deprecated and costs a lot of CPU time per draw call.
ANGLE's Metal backend runs the same OpenGL ES calls on Metal. SDL2's UIKit
backend only knows Apple's OpenGL ES (EAGL), with no EGL, so the context is
made here: an EGL surface on SDL's Metal view. SDL still owns the window,
the events, the sound and the controllers. vid_sdl2.c uses this when the
renderer asks for OpenGL ES 2 or newer (ref_gles3compat) and ANGLE starts.

ANGLE is the app's own libEGL and libGLESv2 frameworks, opened at run time:
if they are missing or can't start (an iOS older than they were built for,
no Metal), nothing here is tried again for the rest of the launch: that
renderer fails to start and the next one draws, ref_gles1 on Apple's OpenGL
ES as before (see R_Init). "-ref gles1" on the engine command line (the
launcher's options) picks Apple's on purpose.

The same code runs on Linux for testing (XASH_ANGLE_RIG): Mesa's EGL on
SDL's X11 window instead of ANGLE on the Metal view.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#include <SDL.h>
#include "common.h"
#include "platform/platform.h"
#include "ref_api.h"
#include <dlfcn.h>
#include <stdint.h>

#if XASH_ANGLE_RIG
#include <SDL_syswm.h>
#else
#include <SDL_metal.h>
#endif

// the few EGL types and values used here (the iOS SDK has no EGL headers)
typedef void *EGLDisplay, *EGLConfig, *EGLSurface, *EGLContext;
typedef int32_t EGLint;
typedef unsigned int EGLBoolean, EGLenum;

#define EGL_NO_DISPLAY  ((EGLDisplay)0)
#define EGL_NO_SURFACE  ((EGLSurface)0)
#define EGL_NO_CONTEXT  ((EGLContext)0)
#define EGL_SUCCESS                   0x3000
#define EGL_ALPHA_SIZE                0x3021
#define EGL_BLUE_SIZE                 0x3022
#define EGL_GREEN_SIZE                0x3023
#define EGL_RED_SIZE                  0x3024
#define EGL_DEPTH_SIZE                0x3025
#define EGL_STENCIL_SIZE              0x3026
#define EGL_SAMPLES                   0x3031
#define EGL_SAMPLE_BUFFERS            0x3032
#define EGL_SURFACE_TYPE              0x3033
#define EGL_NONE                      0x3038
#define EGL_RENDERABLE_TYPE           0x3040
#define EGL_VENDOR                    0x3053
#define EGL_VERSION                   0x3054
#define EGL_EXTENSIONS                0x3055
#define EGL_WINDOW_BIT                0x0004
#define EGL_OPENGL_ES3_BIT            0x0040
#define EGL_OPENGL_ES_API             0x30A0
#define EGL_CONTEXT_MAJOR_VERSION     0x3098
#define EGL_CONTEXT_MINOR_VERSION     0x30FB
// EGL_ANGLE_platform_angle, EGL_ANGLE_platform_angle_metal
#define EGL_PLATFORM_ANGLE_ANGLE            0x3202
#define EGL_PLATFORM_ANGLE_TYPE_ANGLE       0x3203
#define EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE 0x3489

#define GL_VENDOR   0x1F00
#define GL_RENDERER 0x1F01
#define GL_VERSION  0x1F02

typedef void *( *eglGetProcAddress_t )( const char *name );
typedef EGLDisplay ( *eglGetDisplay_t )( void *native );
typedef EGLDisplay ( *eglGetPlatformDisplayEXT_t )( EGLenum platform, void *native, const EGLint *attribs );
typedef EGLBoolean ( *eglInitialize_t )( EGLDisplay dpy, EGLint *major, EGLint *minor );
typedef EGLBoolean ( *eglTerminate_t )( EGLDisplay dpy );
typedef EGLBoolean ( *eglBindAPI_t )( EGLenum api );
typedef EGLBoolean ( *eglChooseConfig_t )( EGLDisplay dpy, const EGLint *attribs, EGLConfig *configs, EGLint size, EGLint *num );
typedef EGLBoolean ( *eglGetConfigAttrib_t )( EGLDisplay dpy, EGLConfig config, EGLint attr, EGLint *value );
typedef EGLSurface ( *eglCreateWindowSurface_t )( EGLDisplay dpy, EGLConfig config, void *win, const EGLint *attribs );
typedef EGLBoolean ( *eglDestroySurface_t )( EGLDisplay dpy, EGLSurface surface );
typedef EGLContext ( *eglCreateContext_t )( EGLDisplay dpy, EGLConfig config, EGLContext share, const EGLint *attribs );
typedef EGLBoolean ( *eglDestroyContext_t )( EGLDisplay dpy, EGLContext ctx );
typedef EGLBoolean ( *eglMakeCurrent_t )( EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx );
typedef EGLBoolean ( *eglSwapBuffers_t )( EGLDisplay dpy, EGLSurface surface );
typedef EGLBoolean ( *eglSwapInterval_t )( EGLDisplay dpy, EGLint interval );
typedef EGLint ( *eglGetError_t )( void );
typedef const char *( *eglQueryString_t )( EGLDisplay dpy, EGLint name );
typedef const unsigned char *( *glGetString_t )( unsigned int name );

static struct
{
	qboolean tried, broken; // loading was tried; it failed, or ANGLE didn't start
	void *egl_lib, *gles_lib;

	eglGetProcAddress_t GetProcAddress;
	eglGetDisplay_t GetDisplay;
	eglInitialize_t Initialize;
	eglTerminate_t Terminate;
	eglBindAPI_t BindAPI;
	eglChooseConfig_t ChooseConfig;
	eglGetConfigAttrib_t GetConfigAttrib;
	eglCreateWindowSurface_t CreateWindowSurface;
	eglDestroySurface_t DestroySurface;
	eglCreateContext_t CreateContext;
	eglDestroyContext_t DestroyContext;
	eglMakeCurrent_t MakeCurrent;
	eglSwapBuffers_t SwapBuffers;
	eglSwapInterval_t SwapInterval;
	eglGetError_t GetError;
	eglQueryString_t QueryString;

	// what the renderer asked for (REF_GL_* attributes)
	int want_major, want_es, want_alpha, want_depth, want_stencil, want_samples;

	// what it got
	int red, green, blue, alpha, depth, stencil, samples;

	void *view; // SDL_MetalView (the surface draws into its layer)
	EGLDisplay display;
	EGLSurface surface;
	EGLContext context;
	int interval;
} angle;

static void IOS_AngleFail( const char *what )
{
	Con_Printf( S_ERROR "ANGLE: %s (EGL error 0x%04x)\n", what, angle.GetError ? (unsigned)angle.GetError( ) : 0u );
}

static void *IOS_AngleOpen( const char *name )
{
	char path[MAX_SYSPATH];
	void *lib;

#if XASH_ANGLE_RIG
	Q_strncpy( path, name, sizeof( path ));
#else
	// the frameworks sit next to SDL2.framework in the app (scripts/ios/createipa.sh)
	Q_snprintf( path, sizeof( path ), "%s/%s.framework/%s", IOS_GetExecDir( ), name, name );
#endif

	lib = dlopen( path, RTLD_NOW | RTLD_LOCAL );
	if( !lib )
		Con_Printf( "ANGLE: can't load %s: %s\n", name, dlerror( ));
	return lib;
}

qboolean IOS_Angle_Load( void )
{
	if( angle.tried )
		return !angle.broken;

	angle.tried = true;
	angle.broken = true;

#if XASH_ANGLE_RIG
	// libGLESv2 first: libEGL finds it among the loaded libraries
	angle.gles_lib = IOS_AngleOpen( "libGLESv2.so.2" );
	angle.egl_lib = angle.gles_lib ? IOS_AngleOpen( "libEGL.so.1" ) : NULL;
#else
	angle.gles_lib = IOS_AngleOpen( "libGLESv2" );
	angle.egl_lib = angle.gles_lib ? IOS_AngleOpen( "libEGL" ) : NULL;
#endif
	if( !angle.egl_lib )
		return false;

#define EGL_FUNC( name ) \
	if( !( angle.name = (egl##name##_t)dlsym( angle.egl_lib, "egl" #name ))) \
	{ \
		Con_Printf( "ANGLE: libEGL has no egl" #name "\n" ); \
		return false; \
	}
	EGL_FUNC( GetProcAddress )
	EGL_FUNC( GetDisplay )
	EGL_FUNC( Initialize )
	EGL_FUNC( Terminate )
	EGL_FUNC( BindAPI )
	EGL_FUNC( ChooseConfig )
	EGL_FUNC( GetConfigAttrib )
	EGL_FUNC( CreateWindowSurface )
	EGL_FUNC( DestroySurface )
	EGL_FUNC( CreateContext )
	EGL_FUNC( DestroyContext )
	EGL_FUNC( MakeCurrent )
	EGL_FUNC( SwapBuffers )
	EGL_FUNC( SwapInterval )
	EGL_FUNC( GetError )
	EGL_FUNC( QueryString )
#undef EGL_FUNC

	angle.broken = false;
	return true;
}

void IOS_Angle_ResetAttributes( void )
{
	angle.want_major = angle.want_es = 0;
	angle.want_alpha = 8;
	angle.want_depth = 24;
	angle.want_stencil = 8;
	angle.want_samples = 0;
}

void IOS_Angle_SetAttribute( int attr, int val )
{
	switch( attr )
	{
	case REF_GL_CONTEXT_MAJOR_VERSION: angle.want_major = val; break;
	case REF_GL_CONTEXT_PROFILE_MASK: angle.want_es = val == REF_GL_CONTEXT_PROFILE_ES; break;
	case REF_GL_ALPHA_SIZE: angle.want_alpha = val; break;
	case REF_GL_DEPTH_SIZE: angle.want_depth = val; break;
	case REF_GL_STENCIL_SIZE: angle.want_stencil = val; break;
	case REF_GL_MULTISAMPLESAMPLES: angle.want_samples = val; break;
	}
}

qboolean IOS_Angle_Wanted( void )
{
	// ref_gles3compat asks for OpenGL ES 2.0 or newer: ANGLE's. ref_gles1
	// (nanogl) asks for 1.1: Apple's, as before.
	return angle.want_es && angle.want_major >= 2;
}

qboolean IOS_Angle_Active( void )
{
	return angle.context != EGL_NO_CONTEXT;
}

static EGLConfig IOS_AngleChooseConfig( void )
{
	// what was asked, then without MSAA, then the least the renderer can use
	const int tries[][4] = // alpha, depth, stencil, samples
	{
		{ angle.want_alpha, angle.want_depth, angle.want_stencil, angle.want_samples },
		{ angle.want_alpha, angle.want_depth, angle.want_stencil, 0 },
		{ 0, 24, 0, 0 },
		{ 0, 16, 0, 0 },
	};
	int i;

	for( i = 0; i < (int)ARRAYSIZE( tries ); i++ )
	{
		const EGLint attribs[] =
		{
			EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
			EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
			EGL_RED_SIZE, 8,
			EGL_GREEN_SIZE, 8,
			EGL_BLUE_SIZE, 8,
			EGL_ALPHA_SIZE, tries[i][0],
			EGL_DEPTH_SIZE, tries[i][1],
			EGL_STENCIL_SIZE, tries[i][2],
			EGL_SAMPLE_BUFFERS, tries[i][3] > 1 ? 1 : 0,
			EGL_SAMPLES, tries[i][3] > 1 ? tries[i][3] : 0,
			EGL_NONE
		};
		EGLConfig config = NULL;
		EGLint num = 0;

		if( angle.ChooseConfig( angle.display, attribs, &config, 1, &num ) && num > 0 && config )
		{
			EGLint v;
#define GET( attr, field ) angle.field = angle.GetConfigAttrib( angle.display, config, attr, &v ) ? v : 0
			GET( EGL_RED_SIZE, red );
			GET( EGL_GREEN_SIZE, green );
			GET( EGL_BLUE_SIZE, blue );
			GET( EGL_ALPHA_SIZE, alpha );
			GET( EGL_DEPTH_SIZE, depth );
			GET( EGL_STENCIL_SIZE, stencil );
			GET( EGL_SAMPLES, samples );
#undef GET
			return config;
		}
	}

	return NULL;
}

/*
==================
IOS_Angle_CreateContext

an OpenGL ES 3.0 context drawing into the window, current on return;
false: ANGLE couldn't start (logged), and won't be tried again
==================
*/
qboolean IOS_Angle_CreateContext( void *window )
{
	void *native;
	EGLConfig config;
	EGLint major = 0, minor = 0;
	glGetString_t getstring;

	IOS_Angle_DeleteContext( );

	if( !IOS_Angle_Load( ))
		return false;

#if XASH_ANGLE_RIG
	SDL_SysWMinfo info;

	SDL_VERSION( &info.version );
	if( !SDL_GetWindowWMInfo( window, &info ) || info.subsystem != SDL_SYSWM_X11 )
	{
		Con_Printf( S_ERROR "ANGLE: rig needs an X11 window\n" );
		goto fail;
	}
	native = (void *)(uintptr_t)info.info.x11.window;
	angle.display = angle.GetDisplay( info.info.x11.display );
#else
	eglGetPlatformDisplayEXT_t getplatformdisplay;

	// SDL's Metal view is backed by a CAMetalLayer sized for the window;
	// ANGLE draws straight into that layer
	angle.view = SDL_Metal_CreateView( window );
	if( !angle.view )
	{
		Con_Printf( S_ERROR "ANGLE: SDL_Metal_CreateView: %s\n", SDL_GetError( ));
		goto fail;
	}

	native = SDL_Metal_GetLayer( angle.view );
	if( !native )
	{
		Con_Printf( S_ERROR "ANGLE: SDL_Metal_GetLayer: %s\n", SDL_GetError( ));
		goto fail;
	}

	// Metal by name, rather than whatever ANGLE takes by default
	getplatformdisplay = (eglGetPlatformDisplayEXT_t)angle.GetProcAddress( "eglGetPlatformDisplayEXT" );
	if( getplatformdisplay )
	{
		const EGLint attribs[] = { EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE, EGL_NONE };
		angle.display = getplatformdisplay( EGL_PLATFORM_ANGLE_ANGLE, NULL, attribs );
	}
	if( angle.display == EGL_NO_DISPLAY )
	{
		Con_Printf( "ANGLE: no Metal display, trying the default one\n" );
		angle.display = angle.GetDisplay( NULL );
	}
#endif

	if( angle.display == EGL_NO_DISPLAY || !angle.Initialize( angle.display, &major, &minor ))
	{
		IOS_AngleFail( "eglInitialize failed" );
		angle.display = EGL_NO_DISPLAY;
		goto fail;
	}
	Con_Printf( "ANGLE: EGL %d.%d, %s\n", major, minor, angle.QueryString( angle.display, EGL_VENDOR ));

	angle.BindAPI( EGL_OPENGL_ES_API );

	if( !( config = IOS_AngleChooseConfig( )))
	{
		IOS_AngleFail( "no OpenGL ES 3 config" );
		goto fail;
	}

	angle.surface = angle.CreateWindowSurface( angle.display, config, native, NULL );
	if( angle.surface == EGL_NO_SURFACE )
	{
		IOS_AngleFail( "eglCreateWindowSurface failed" );
		goto fail;
	}

	{
		const EGLint attribs[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE };
		angle.context = angle.CreateContext( angle.display, config, EGL_NO_CONTEXT, attribs );
	}
	if( angle.context == EGL_NO_CONTEXT )
	{
		IOS_AngleFail( "eglCreateContext (OpenGL ES 3.0) failed" );
		goto fail;
	}

	if( !angle.MakeCurrent( angle.display, angle.surface, angle.surface, angle.context ))
	{
		IOS_AngleFail( "eglMakeCurrent failed" );
		goto fail;
	}

	angle.SwapInterval( angle.display, angle.interval );

	getstring = (glGetString_t)angle.GetProcAddress( "glGetString" );
	Con_Printf( "ANGLE: %s, %s (%d%d%d%d, depth %d, stencil %d, MSAA %d)\n",
		getstring ? (const char *)getstring( GL_RENDERER ) : "?",
		getstring ? (const char *)getstring( GL_VERSION ) : "?",
		angle.red, angle.green, angle.blue, angle.alpha, angle.depth, angle.stencil, angle.samples );
	return true;

fail:
	IOS_Angle_DeleteContext( );
	angle.broken = true;
	return false;
}

void IOS_Angle_DeleteContext( void )
{
	if( angle.display != EGL_NO_DISPLAY )
	{
		angle.MakeCurrent( angle.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT );
		if( angle.context != EGL_NO_CONTEXT )
			angle.DestroyContext( angle.display, angle.context );
		if( angle.surface != EGL_NO_SURFACE )
			angle.DestroySurface( angle.display, angle.surface );
		angle.Terminate( angle.display );
	}

	angle.context = EGL_NO_CONTEXT;
	angle.surface = EGL_NO_SURFACE;
	angle.display = EGL_NO_DISPLAY;

#if !XASH_ANGLE_RIG
	// the view outlives the surface drawing into its layer
	if( angle.view )
		SDL_Metal_DestroyView( angle.view );
#endif
	angle.view = NULL;
}

void IOS_Angle_SwapBuffers( void )
{
	if( angle.surface != EGL_NO_SURFACE )
		angle.SwapBuffers( angle.display, angle.surface );
}

void *IOS_Angle_GetProcAddress( const char *name )
{
	return angle.GetProcAddress ? angle.GetProcAddress( name ) : NULL;
}

int IOS_Angle_SetSwapInterval( int interval )
{
	// the screen's pace (1) or not waiting for it (0)
	angle.interval = interval ? 1 : 0;

	if( angle.display == EGL_NO_DISPLAY )
		return 0;

	return angle.SwapInterval( angle.display, angle.interval ) ? 0 : -1;
}

int IOS_Angle_GetAttribute( int attr, int *val )
{
	switch( attr )
	{
	case REF_GL_RED_SIZE: *val = angle.red; break;
	case REF_GL_GREEN_SIZE: *val = angle.green; break;
	case REF_GL_BLUE_SIZE: *val = angle.blue; break;
	case REF_GL_ALPHA_SIZE: *val = angle.alpha; break;
	case REF_GL_DEPTH_SIZE: *val = angle.depth; break;
	case REF_GL_STENCIL_SIZE: *val = angle.stencil; break;
	case REF_GL_MULTISAMPLEBUFFERS: *val = angle.samples > 1; break;
	case REF_GL_MULTISAMPLESAMPLES: *val = angle.samples > 1 ? angle.samples : 0; break;
	case REF_GL_DOUBLEBUFFER: *val = 1; break;
	case REF_GL_ACCELERATED_VISUAL: *val = 1; break;
	case REF_GL_CONTEXT_MAJOR_VERSION: *val = 3; break;
	case REF_GL_CONTEXT_MINOR_VERSION: *val = 0; break;
	case REF_GL_CONTEXT_EGL: *val = 1; break;
	case REF_GL_CONTEXT_PROFILE_MASK: *val = REF_GL_CONTEXT_PROFILE_ES; break;
	default: *val = 0; break;
	}

	return 0;
}
