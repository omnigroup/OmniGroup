// Copyright 1997-2006, 2008-2010, 2013 Omni Development, Inc. All rights reserved.
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
#import "OBBacktraceBuffer.h"
#import <unistd.h> // For getpid()

RCS_ID("$Id$")

#ifdef OMNI_ASSERTIONS_ON

BOOL OBEnableExpensiveAssertions = NO;

void OBLogAssertionFailure(const char *type, const char *expression, const char *file, unsigned int lineNumber, const char *reason)
{
    if (expression && *expression != '\0') {
        if (reason && *reason != '\0')
            fprintf(stderr, "%s failed: '%s' (reason: '%s') at %s:%d\n", type, expression, reason, file, lineNumber);
        else
            fprintf(stderr, "%s failed: requires '%s', at %s:%d\n", type, expression, file, lineNumber);
    } else {
        if (reason && *reason != '\0')
            fprintf(stderr, "%s failed (reason: '%s') at %s:%d\n", type, reason, file, lineNumber);
        else
            fprintf(stderr, "%s failed at %s:%d\n", type, file, lineNumber);
    }
}

static NSString * const OBEnableExpensiveAssertionsKey = @"OBEnableExpensiveAssertions";

static void OBDefaultAssertionHandler(const char *type, const char *expression, const char *file, unsigned int lineNumber, const char *reason)
{
    OBLogAssertionFailure(type, expression, file, lineNumber, reason);
}

static OBAssertionFailureHandler currentAssertionHandler = OBDefaultAssertionHandler;
void OBSetAssertionFailureHandler(OBAssertionFailureHandler handler)
{
    if (handler)
        currentAssertionHandler = handler;
    else
        currentAssertionHandler = OBDefaultAssertionHandler;
}

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
    currentAssertionHandler(type, expression, file, lineNumber, [reason UTF8String]);
    OBAssertFailed();
}

void OBAssertFailed(void)
{
    // This function is an intended target for breakpoints. To ensure it doesn't get optimized out (even with __attribute__((noinline))), put an asm statement here.
    asm("");
}

void _OBAssertNotImplemented(id self, const char *selName)
{
    OBASSERT(strstr(selName, "@") == NULL); // Make sure @selector(...) wasn't passed to OBASSERT_NOT_IMPLEMENTED
    
    SEL sel = sel_getUid(selName);
    if ([self respondsToSelector:sel]) {
        Class impClass = OBClassImplementingMethod([self class], sel);
        NSLog(@"%@ has implementation of %@", NSStringFromClass(impClass), NSStringFromSelector(sel));
        OBAssertFailed();
    }
}

#endif

#if defined(OMNI_ASSERTIONS_ON) || defined(DEBUG)

static void _OBAssertionLoad(void) __attribute__((constructor));
static void _OBAssertionLoad(void)
{
#ifdef OMNI_ASSERTIONS_ON
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
#elif DEBUG
    if (getenv("OBASSERT_NO_BANNER") == NULL)
        fprintf(stderr, "*** Assertions are OFF ***\n");
#endif
}
#endif
