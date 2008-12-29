// Copyright 2000-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSArray;
@class NSScreen;
@protocol OAWindowCascadeDataSource;

#import <Foundation/NSGeometry.h> // For NSPoint, NSRect

@interface OAWindowCascade : OFObject
{
    NSRect lastStartingFrame;
    NSPoint lastWindowOrigin;
}

+ (id)sharedInstance;
+ (void)addDataSource:(id <OAWindowCascadeDataSource>)newValue;
+ (void)removeDataSource:(id <OAWindowCascadeDataSource>)oldValue;
+ (void)avoidFontPanel;
+ (void)avoidColorPanel;

+ (NSScreen *)screenForPoint:(NSPoint)aPoint;

+ (NSRect)unobscuredWindowFrameFromStartingFrame:(NSRect)startingFrame avoidingWindows:(NSArray *)windowsToAvoid;

- (NSRect)nextWindowFrameFromStartingFrame:(NSRect)startingFrame avoidingWindows:(NSArray *)windowsToAvoid;
- (void)reset;

@end


@protocol OAWindowCascadeDataSource
- (NSArray *)windowsThatShouldBeAvoided;
@end
