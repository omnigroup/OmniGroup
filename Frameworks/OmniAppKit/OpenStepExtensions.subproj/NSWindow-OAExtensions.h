// Copyright 1997-2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSWindow-OAExtensions.h 103484 2008-07-29 23:32:30Z wiml $

#import <AppKit/NSWindow.h>

#import <Foundation/NSGeometry.h> // for NSPoint
#import <Foundation/NSDate.h> // for NSTimeInterval

#import <OmniBase/OBUtilities.h>

@interface NSWindow (OAExtensions)

+ (NSArray *)windowsInZOrder;

- (NSPoint)frameTopLeftPoint;
- (void)morphToFrame:(NSRect)newFrame overTimeInterval:(NSTimeInterval)morphInterval;

- (BOOL)isBecomingKey;
- (BOOL)shouldDrawAsKey;

- (void *)carbonWindowRef OB_DEPRECATED_ATTRIBUTE;

- (void)addConstructionWarning;

- (CGPoint)convertBaseToCGScreen:(NSPoint)windowPoint;

@end
