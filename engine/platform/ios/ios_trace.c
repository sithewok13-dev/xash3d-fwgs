/*
ios_trace.c - startup breadcrumbs for the iOS port

A game switch runs the engine again in the same process. When something
on that path kills the app before the engine log or the crash handler can
say anything, Documents/xash-trace.txt still shows the last step reached:
each line goes straight to disk.

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
#include <fcntl.h>
#include <unistd.h>
#include <time.h>

void IOS_Trace( const char *fmt, ... )
{
	static int fd = -1;
	char line[4096];
	va_list args;
	int len;

	if( fd < 0 )
	{
		char path[MAX_SYSPATH];

		// one app launch per file: emptied when the app starts
		Q_snprintf( path, sizeof( path ), "%s/xash-trace.txt", IOS_GetDocsDir( ));
		fd = open( path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644 );
		if( fd < 0 )
			return;
	}

	time_t now = time( NULL );
	struct tm *tm = localtime( &now );
	len = tm ? strftime( line, sizeof( line ), "[%H:%M:%S] ", tm ) : 0;

	va_start( args, fmt );
	vsnprintf( line + len, sizeof( line ) - len - 1, fmt, args );
	va_end( args );

	len = Q_strlen( line );
	line[len++] = '\n';

	if( write( fd, line, len ) == len )
		fsync( fd );
}
