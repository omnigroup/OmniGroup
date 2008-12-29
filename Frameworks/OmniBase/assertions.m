// Copyright 1997-2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/assertions.h>
#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>
#import <unistd.h> // For getpid()

RCS_ID("$Id$")

#ifdef OMNI_ASSERTIONS_ON

BOOL OBEnableExpensiveAssertions = NO;

void OBLogAssertionFailure(const char *type, const char *expression, const char *file, unsigned int lineNumber)
{
    fprintf(stderr, "%s failed: requires '%s', file %s, line %d\n", type, expression, file, lineNumber);
}

static NSString *OBShouldAbortOnAssertFailureEnabled = @"OBShouldAbortOnAssertFailureEnabled";

static void OBDefaultAssertionHandler(const char *type, const char *expression, const char *file, unsigned int lineNumber)
{
    OBLogAssertionFailure(type, expression, file, lineNumber);
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if ([userDefaults boolForKey:OBShouldAbortOnAssertFailureEnabled])
        abort();
    else if (OBIsRunningUnitTests()) {
        // If we are running unit tests, abort on assertion failure.  We could make assertions throw exceptions, but note that this wouldn't catch cases where you are using 'shouldRaise' and hit an assertion.
#ifdef DEBUG
        // If we're failing in a debug build, give the developer a little time to connect in gdb before crashing
        fprintf(stderr, "You have 15 seconds to attach to pid %u in gdb...\n", getpid());
        [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:15.0]];
#endif
        abort();
    }
}

static OBAssertionFailureHandler currentAssertionHandler = OBDefaultAssertionHandler;
void OBSetAssertionFailureHandler(OBAssertionFailureHandler handler)
{
    if (handler)
        currentAssertionHandler = handler;
    else
        currentAssertionHandler = OBDefaultAssertionHandler;
}

void OBAssertFailed(const char *type, const char *expression, const char *file, unsigned int lineNumber)
{
     currentAssertionHandler(type, expression, file, lineNumber);
}

#endif

#if defined(OMNI_ASSERTIONS_ON) || defined(DEBUG)

static void _OBAssertionLoad(void) __attribute__((constructor));
static void _OBAssertionLoad(void)
{
#ifdef OMNI_ASSERTIONS_ON
    OBEnableExpensiveAssertions = [[NSUserDefaults standardUserDefaults] boolForKey:@"OBEnableExpensiveAssertions"];
    if (getenv("OBASSERT_NO_BANNER") == NULL) {
        fprintf(stderr, "*** Assertions are ON ***\n");
        if (OBEnableExpensiveAssertions)
            fprintf(stderr, "*** Expensive assertions are ON ***\n");
    }
#elif DEBUG
    if (getenv("OBASSERT_NO_BANNER") == NULL)
        fprintf(stderr, "*** Assertions are OFF ***\n");
#endif
}
#endif
