// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniBase/system.h 102858 2008-07-15 04:25:10Z bungi $
//
// This file contains stuff that isn't necessarily portable between operating systems.

#import <AvailabilityMacros.h>
#import <TargetConditionals.h>

#if TARGET_OS_MAC && (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE)
//
// Mac OS X
//

#if defined(__cplusplus)
extern "C" {
#endif

#import <libc.h>
#import <stddef.h>
#import <arpa/nameser.h>
#import <resolv.h>
#import <netdb.h>
#import <sys/types.h>
#import <sys/time.h>
#import <sys/dir.h>
#import <sys/errno.h>
#import <sys/stat.h>
#import <sys/uio.h>
#import <sys/file.h>
#import <fcntl.h>

// <c.h> is no longer present on 10.5
#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
#import <c.h> // For MIN(), etc.
#endif

#import <unistd.h>
#import <math.h> // For floor(), etc.

#import <pthread.h>

#if defined(__cplusplus)
}  // extern "C"
#endif
        
    
#elif defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <stddef.h>
#import <sys/types.h>
#import <sys/time.h>
#import <sys/errno.h>
#import <sys/stat.h>
#import <sys/uio.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h> // For floor(), etc.
#import <pthread.h>

#else

//
// Unknown system
//

#error Unknown system!

#endif

// Default to using BSD socket API.

#ifndef OBSocketRead
#define OBSocketRead(socketFD, buffer, byteCount) read(socketFD, buffer, byteCount)
#endif
#ifndef OBSocketWrite
#define OBSocketWrite(socketFD, buffer, byteCount) write(socketFD, buffer, byteCount)
#endif
#ifndef OBSocketWriteVectors
#define OBSocketWriteVectors(socketFD, buffers, bufferCount) writev(socketFD, buffers, bufferCount)
#endif
#ifndef OBSocketClose
#define OBSocketClose(socketFD) close(socketFD)
#endif
