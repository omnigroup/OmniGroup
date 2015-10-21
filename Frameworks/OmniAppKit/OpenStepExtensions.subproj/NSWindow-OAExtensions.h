// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSWindow.h>

#import <Foundation/NSGeometry.h> // for NSPoint
#import <Foundation/NSDate.h> // for NSTimeInterval

#import <OmniBase/OBUtilities.h>

@interface NSWindow (OAExtensions)

+ (NSArray *)windowsInZOrder;

/// This block will be executed before -displayIfNeeded on *any* window.
+ (void)beforeAnyDisplayIfNeededPerformBlock:(void (^)(void))block;

/// This block will be executed before -displayIfNeeded but only for this window. N.B., you probably want beforeAnyDisplayIfNeededPerformBlock: as displayIfNeeded is not always called, for example when a user is interacting with a popover presented from the window. Conversions to that API should check that the blocks don't rely on the window still existing.
- (void)beforeDisplayIfNeededPerformBlock:(void (^)(void))block NS_DEPRECATED_MAC(10_10, 10_10, "Use +beforeAnyDisplayIfNeededPerformBlock:");

- (void)performDisplayIfNeededBlocks;

- (NSPoint)frameTopLeftPoint;

- (BOOL)isBecomingKey;
- (BOOL)shouldDrawAsKey;

- (void)addConstructionWarning;

- (NSPoint)convertPointToScreen:(NSPoint)windowPoint;
- (NSPoint)convertPointFromScreen:(NSPoint)screenPoint;

- (CGPoint)convertBaseToCGScreen:(NSPoint)windowPoint;

- (IBAction)visualizeConstraintsForPickedView:(id)sender;

@end
