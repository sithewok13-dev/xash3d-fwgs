/*
ios_perf.c - frame times in the iOS log

Every 5 seconds of play, one line in engine.log (and the device log): the
frames drawn per second and where a frame's time went, on average: the
game's own work (input, server, client, sound), drawing (the renderer
handing the GPU its work), and present (the swap, which waits while the GPU
or the screen is behind), plus the worst frame. Also which OpenGL ES runs
(ANGLE on Metal, or Apple's).

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#include "common.h"
#include "platform/platform.h"

#define IOS_PERF_PERIOD 5.0

static double perf_draw, perf_present; // this frame's, so far

void IOS_PerfAddDraw( double seconds )
{
	perf_draw += seconds;
}

void IOS_PerfAddPresent( double seconds )
{
	perf_present += seconds;
}

void IOS_PerfFrame( double frame_seconds, qboolean playing )
{
	static double start, sum_frame, sum_draw, sum_present, worst;
	static int frames;
	double now = Platform_DoubleTime( );
	double draw = perf_draw, present = perf_present;

	perf_draw = perf_present = 0.0;

	if( !playing )
	{
		start = 0.0;
		return;
	}

	if( start == 0.0 )
	{
		start = now;
		frames = 0;
		sum_frame = sum_draw = sum_present = worst = 0.0;
		return;
	}

	// drawing's time includes the present (the swap is inside the renderer's frame)
	if( present > draw )
		present = draw;

	frames++;
	sum_frame += frame_seconds;
	sum_draw += draw - present;
	sum_present += present;
	if( frame_seconds > worst )
		worst = frame_seconds;

	if( now - start >= IOS_PERF_PERIOD && frames > 0 )
	{
		double ms = 1000.0 / frames;
		double game = sum_frame - sum_draw - sum_present;
		char line[256];

		Q_snprintf( line, sizeof( line ),
			"iOS: frames %.1f fps; per frame %.1f ms (worst %.1f): game %.1f, drawing %.1f, present %.1f; %s\n",
			frames / ( now - start ), sum_frame * ms, worst * 1000.0, ( game > 0.0 ? game : 0.0 ) * ms,
			sum_draw * ms, sum_present * ms, IOS_Angle_Active( ) ? "ANGLE (Metal)" : "Apple OpenGL ES" );
		Sys_PrintLog( line );

		start = now;
		frames = 0;
		sum_frame = sum_draw = sum_present = worst = 0.0;
	}
}
