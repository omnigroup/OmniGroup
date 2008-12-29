// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFController.h>

#import <ExceptionHandling/NSExceptionHandler.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

// This doesn't use OCUnit right now since, (1) it uses a custom OFController subclass and OFController isn't currently able to reset its shared instance and (2) some of the tests are intended to crash.  Both of these could be fixed, but they haven't been yet.

@interface OFCrashOnExceptionController : OFController
@end

@implementation OFCrashOnExceptionController

- (BOOL)crashOnAssertionOrUnhandledException;
{
    return YES;
}

- (unsigned int)exceptionHandlingMask;
{
    // OFController doesn't include NSLogOtherExceptionMask by default
    return NSLogUncaughtExceptionMask|NSLogUncaughtSystemExceptionMask|NSLogUncaughtRuntimeErrorMask|NSLogTopLevelExceptionMask|NSLogOtherExceptionMask;
}

- (void)testUnhandledException;
{
    // Mask will be NSLogUncaughtExceptionMask for this
    [NSException raise:NSGenericException format:@"Unhandled exception"];
}

- (void)testHandledException;
{
    @try {
        // Mask will be NSLogTopLevelExceptionMask for this
        [NSException raise:NSGenericException format:@"Handled exception"];
    } @catch (NSException *exc) {
        // ignored
    }
}

- (void)testReraisedAndUnhandledException;
{
    @try {
        [NSException raise:NSGenericException format:@"Reraised and then unhandled exception"];
    } @catch (NSException *exc) {
        [exc raise];
    }
}

- (void)testReraisedButHandledException;
{
    @try {
        @try {
            [NSException raise:NSGenericException format:@"Reraised but handled exception"];
        } @catch (NSException *exc) {
            [exc raise];
        }
    } @catch (NSException *exc) {
        // ignored
    }
}

@end

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    OFController *controller = [OFCrashOnExceptionController sharedController];
    int status = 0;
    
    [controller didInitialize];
    [controller startedRunning];

    do {
        NSString *action = [[NSUserDefaults standardUserDefaults] stringForKey:@"Action"];
        if ([NSString isEmptyString:action]) {
            NSLog(@"No action specified.");
            status = 1;
            break;
        }
        
        SEL sel = NSSelectorFromString(action);
        if (![controller respondsToSelector:sel]) {
            NSLog(@"Action '%@' doesn't appear to be implemented.", action);
            status = 1;
            break;
        }

        [controller performSelector:sel];
        
    } while (NO);
    
    [controller requestTermination];
    [pool release];
    return status;
}
