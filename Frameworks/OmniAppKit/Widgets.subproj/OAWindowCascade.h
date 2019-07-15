// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSArray;
@class NSScreen;
@protocol OAWindowCascadeDataSource;

#import <Foundation/NSGeometry.h> // For NSPoint, NSRect

NS_ASSUME_NONNULL_BEGIN

@interface OAWindowCascade : OFObject

+ (instancetype)sharedInstance;
+ (void)addDataSource:(id <OAWindowCascadeDataSource>)newValue;
+ (void)removeDataSource:(id <OAWindowCascadeDataSource>)oldValue;
+ (void)avoidFontPanel;
+ (void)avoidColorPanel;

+ (NSScreen *)screenForPoint:(NSPoint)aPoint;

+ (NSRect)unobscuredWindowFrameFromStartingFrame:(NSRect)startingFrame avoidingWindows:(nullable NSArray <NSWindow *> *)windowsToAvoid;

- (NSRect)nextWindowFrameFromStartingFrame:(NSRect)startingFrame avoidingWindows:(nullable NSArray <NSWindow *> *)windowsToAvoid;
- (void)reset;

- (void)resetWithStartingFrame:(NSRect)startingFrame;

@end


@protocol OAWindowCascadeDataSource
- (NSArray <NSWindow *> *)windowsThatShouldBeAvoided;
@end

NS_ASSUME_NONNULL_END
