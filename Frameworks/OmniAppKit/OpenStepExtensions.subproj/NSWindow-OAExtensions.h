// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSWindow.h>

#import <Foundation/NSGeometry.h> // for NSPoint
#import <Foundation/NSDate.h> // for NSTimeInterval

#import <OmniBase/OBUtilities.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSWindow (Sierra)
// These are present on 10.12, but not declared publically until 10.14.
- (NSPoint)convertPointToScreen:(NSPoint)windowPoint;
- (NSPoint)convertPointFromScreen:(NSPoint)screenPoint;
@end

@interface NSWindow (OAExtensions)

@property (class, nonatomic, readonly) BOOL hasTabbedWindowSupport;

@property(class,nonatomic,readonly) NSArray <NSWindow *> *windowsInZOrder;

@property (class, nonatomic, readonly, getter=isPerformingDisplayIfNeededBlocks) BOOL performingDisplayIfNeededBlocks;

/// This block will be executed before -displayIfNeeded on *any* window.
+ (void)beforeAnyDisplayIfNeededPerformBlock:(void (^)(void))block;

/// This block will be executed before -displayIfNeeded but only for this window. N.B., you probably want beforeAnyDisplayIfNeededPerformBlock: as displayIfNeeded is not always called, for example when a user is interacting with a popover presented from the window. Conversions to that API should check that the blocks don't rely on the window still existing.
- (void)beforeDisplayIfNeededPerformBlock:(void (^)(void))block NS_DEPRECATED_MAC(10_10, 10_10, "Use +beforeAnyDisplayIfNeededPerformBlock:");

- (void)performDisplayIfNeededBlocks;

- (NSPoint)frameTopLeftPoint;

- (BOOL)isBecomingKey;
- (BOOL)shouldDrawAsKey;

- (void)addConstructionWarning;

- (CGPoint)convertBaseToCGScreen:(NSPoint)windowPoint;

- (IBAction)visualizeConstraintsForPickedView:(nullable id)sender;

// 10.13 marks this weak and thus implicitly nullable. Add this property for use between pre-10.13 Swift code and 10.13 so conditional lets will compile on both targets.
@property(nonatomic,readonly) NSResponder * _Nullable nullableFirstResponder;

@end

#pragma mark -

@interface NSWindow (CoalescedRecalculateKeyViewLoop)

@property (nonatomic, getter=isRecalculateKeyViewLoopScheduled) BOOL recalculateKeyViewLoopScheduled;
- (void)beforeDisplayIfNeededRecalculateKeyViewLoop;

@end

#pragma mark -

@interface NSWindow (NSWindowTabbingExtensions)

/// Temporarily sets the tabbing mode to the passed value, executes the block, then restore the previous value
- (void)withTabbingMode:(NSWindowTabbingMode)tabbingMode performBlock:(void (^)(void))block;

@end

extern NSNotificationName const OAWindowUserTabbingPreferenceDidChange;

NS_ASSUME_NONNULL_END

