// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniBase/macros.h 104581 2008-09-06 21:18:23Z kc $

#import <Foundation/NSAutoreleasePool.h>
#import <OmniBase/SystemType.h>

#if !defined(SWAP)
#define SWAP(A, B) do { __typeof__(A) __temp = (A); (A) = (B); (B) = __temp;} while(0)
#endif

// On Solaris, when _TS_ERRNO is defined <errno.h> defines errno as the thread-safe ___errno() function.
// On NT, errno is defined to be '(*_errno())' and presumably this function is also thread safe.
// On MacOS X, errno is defined to be '(*__error())', which is also presumably thread safe. 

#import <errno.h>
#define OMNI_ERRNO() errno

#define OMNI_POOL_START				\
do {						\
    NSAutoreleasePool *__pool;			\
    __pool = [[NSAutoreleasePool alloc] init];	\
    @try {

#define OMNI_POOL_END \
    } @catch (NSException *__exc) { \
	[__exc retain]; \
	[__pool release]; \
	__pool = nil; \
	[__exc autorelease]; \
	[__exc raise]; \
    } @finally { \
	[__pool release]; \
    } \
} while(0)

// For when you have an outError to deal with too
#define OMNI_POOL_ERROR_END \
    } @catch (NSException *__exc) { \
        *outError = nil; \
        [__exc retain]; \
        [__pool release]; \
        __pool = nil; \
        [__exc autorelease]; \
        [__exc raise]; \
    } @finally { \
        [*outError retain]; \
        [__pool release]; \
        [*outError autorelease]; \
    } \
} while(0)

// We don't want to use the main-bundle related macros when building other bundle types.  This is sometimes what you want to do, but you shouldn't use the macros since it'll make genstrings emit those strings into your bundle as well.  We can't do this from the .xcconfig files since NSBundle's #define wins vs. command line flags.
#import <Foundation/NSBundle.h> // Make sure this is imported first so that it doesn't get imported afterwards, clobbering our attempted clobbering.
#if defined(OMNI_BUILDING_BUNDLE) || defined(OMNI_BUILDING_FRAMEWORK)
    #undef NSLocalizedString
    #define NSLocalizedString Use_NSBundle_methods_if_you_really_want_to_look_up_strings_in_the_main_bundle
    #undef NSLocalizedStringFromTable
    #define NSLocalizedStringFromTable Use_NSBundle_methods_if_you_really_want_to_look_up_strings_in_the_main_bundle
#endif
