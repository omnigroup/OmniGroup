// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSDocument-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSWindowController-OAExtensions.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>

RCS_ID("$Id$");

@implementation NSDocument (OAExtensions)

- (NSArray <__kindof NSWindowController *> *)windowControllersOfClass:(Class)windowControllerClass;
{
    return [self.windowControllers select:^BOOL(NSWindowController *wc){
        return !windowControllerClass || [wc isKindOfClass:windowControllerClass];
    }];
}

- (NSArray <__kindof NSWindowController *> *)orderedWindowControllersOfClass:(Class)windowControllerClass;
{
    NSArray <NSWindowController *> *candidateWindowControllers = [self.windowControllers select:^(NSWindowController *wc){
        // Ignore window controllers of the wrong class
        if (windowControllerClass && ![wc isKindOfClass:windowControllerClass]) {
            return NO;
        }

        // Don't provoke loading of windows we don't need
        return wc.isWindowLoaded;
    }];

    if ([candidateWindowControllers count] <= 1) {
        return candidateWindowControllers;
    }

    NSMutableArray <NSWindow *> *loadedWindows = [[[candidateWindowControllers arrayByPerformingBlock:^(NSWindowController *wc){
        return wc.window;
    }] mutableCopy] autorelease];

    NSArray *orderedWindows = [NSWindow windowsInZOrder]; // Doesn't include miniaturized or ordered out windows
    [loadedWindows sortBasedOnOrderInArray:orderedWindows identical:YES unknownAtFront:NO];

    // Actually want the window controllers
    return [loadedWindows arrayByPerformingBlock:^(NSWindow *window) {
        return window.windowController;
    }];
}

- (__kindof NSWindowController *)frontWindowControllerOfClass:(Class)windowControllerClass;
{
    return [[self orderedWindowControllersOfClass:windowControllerClass] firstObject];
}

- (NSArray <NSWindowController *> *)orderedWindowControllers;
{
    return [self orderedWindowControllersOfClass:[NSWindowController class]];
}

- (NSWindowController *)frontWindowController;
{
    return self.orderedWindowControllers.firstObject;
}

- (void)startingLongOperation:(NSString *)operationName automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
{
    NSWindowController *windowController = [self frontWindowController];
    if (windowController)
        [NSWindowController startingLongOperation:operationName controlSize:NSSmallControlSize inWindow:[windowController window] automaticallyEnds:shouldAutomaticallyEnd];
    else
        [NSWindowController startingLongOperation:operationName controlSize:NSSmallControlSize];
}

- (void)continuingLongOperation:(NSString *)operationStatus;
{
    [NSWindowController continuingLongOperation:operationStatus];
}

- (void)finishedLongOperation;
{
    [NSWindowController finishedLongOperation];
}

@end
