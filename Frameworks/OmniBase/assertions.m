// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/assertions.h>
#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>
#import <OmniBase/macros.h>
#import <OmniBase/OBBacktraceBuffer.h>
#import <unistd.h> // For getpid()

RCS_ID("$Id$")

#ifdef OMNI_ASSERTIONS_ON

BOOL OBEnableExpensiveAssertions = NO;

void OBLogAssertionFailure(const char *type, const char *expression, const char *file, unsigned int lineNumber, const char *reason)
{
    // Make these start with 'Error: ' so that they get highlighted in build logs in various places.
    if (expression && *expression != '\0') {
        if (reason && *reason != '\0')
            fprintf(stderr, "Error: %s failed. Requires '%s' (reason: '%s') at %s:%d\n", type, expression, reason, file, lineNumber);
        else
            fprintf(stderr, "Error: %s failed. Requires '%s', at %s:%d\n", type, expression, file, lineNumber);
    } else {
        if (reason && *reason != '\0')
            fprintf(stderr, "Error: %s failed (reason: '%s') at %s:%d\n", type, reason, file, lineNumber);
        else
            fprintf(stderr, "Error: %s failed at %s:%d\n", type, file, lineNumber);
    }
}

static NSString * const OBEnableExpensiveAssertionsKey = @"OBEnableExpensiveAssertions";

void OBInvokeAssertionFailureHandler(const char *type, const char *expression, const char *file, unsigned int lineNumber, NSString *fmt, ...)
{
    NSString *reason;
    {
        va_list args;
        va_start(args, fmt);
        
        reason = OB_AUTORELEASE([[NSString alloc] initWithFormat:fmt arguments:args]);
        
        va_end(args);
    }
    
    OBRecordBacktrace(expression, OBBacktraceBuffer_OBAssertionFailure);

    const char *reasonCString = [reason UTF8String];
    OBLogAssertionFailure(type, expression, file, lineNumber, reasonCString);
    OBAssertFailed(reasonCString);
}

// The message is not logged here, but is used to check if there is a bug logged.
void OBAssertFailed(const char *message)
{
    // If the assertion message contains a bug link, allow continuing past it.
    // If you can't immediately fix the problem, please log a bug with steps to hit the problem and associate it with your app.
    if (message == NULL || strstr(message, "bug://") == NULL) {
        OBTrap(); // If you think you need to comment this out, maybe try breaking on this line and adding a "thread return" command to that breakpoint instead
    }
}

void _OBAssertNotImplemented(id self, const char *selName)
{
    OBASSERT(strstr(selName, "@") == NULL); // Make sure @selector(...) wasn't passed to OBASSERT_NOT_IMPLEMENTED
    
    SEL sel = sel_getUid(selName);
    if ([self respondsToSelector:sel]) {
        Class impClass = OBClassImplementingMethod([self class], sel);
        NSLog(@"%@ has implementation of %@", NSStringFromClass(impClass), NSStringFromSelector(sel));
        OBAssertFailed("");
    }
}

#endif

#if defined(OMNI_ASSERTIONS_ON) || defined(DEBUG)

static void _OBAssertionLoad(void) __attribute__((constructor));
static void _OBAssertionLoad(void)
{
#ifdef OMNI_ASSERTIONS_ON
#if !defined(TARGET_OS_WATCH) || !TARGET_OS_WATCH // crashes on watch, loads too soon?
    @autoreleasepool {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *assertionDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
                                           (id)kCFBooleanFalse, OBEnableExpensiveAssertionsKey,
                                           nil];
        [defaults registerDefaults:assertionDefaults];
        OBEnableExpensiveAssertions = [defaults boolForKey:OBEnableExpensiveAssertionsKey];
        if (getenv("OBASSERT_NO_BANNER") == NULL) {
            fprintf(stderr, "*** Assertions are ON ***\n");
            for(NSString *key in assertionDefaults) {
                fprintf(stderr, "    %s = %s\n",
                        [key UTF8String],
                        [defaults boolForKey:key]? "YES" : "NO");
            }
        }
    }
#endif
#elif DEBUG
    if (getenv("OBASSERT_NO_BANNER") == NULL)
        fprintf(stderr, "*** Assertions are OFF ***\n");
#endif
}
#endif
