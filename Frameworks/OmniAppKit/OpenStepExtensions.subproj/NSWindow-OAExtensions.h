// Copyright 1997-2006, 2008, 2010-2011 Omni Development, Inc.  All rights reserved.
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

#if !defined(MAC_OS_X_VERSION_10_7) || MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_7
enum {
    NSFullScreenWindowMask      = 1 << 14
};
#endif

#if !defined(MAC_OS_X_VERSION_10_7) || MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_7
/* You may specify at most one of NSWindowCollectionBehaviorFullScreenPrimary or NSWindowCollectionBehaviorFullScreenAuxiliary. */
enum {
    NSWindowCollectionBehaviorFullScreenPrimary = 1 << 7,   // the frontmost window with this collection behavior will be the fullscreen window.  
    NSWindowCollectionBehaviorFullScreenAuxiliary = 1 << 8	  // windows with this collection behavior can be shown with the fullscreen window.  
};
#endif

@interface NSWindow (OAExtensions)

+ (NSArray *)windowsInZOrder;

- (NSPoint)frameTopLeftPoint;

- (BOOL)isBecomingKey;
- (BOOL)shouldDrawAsKey;

- (void)addConstructionWarning;

- (CGPoint)convertBaseToCGScreen:(NSPoint)windowPoint;

@end
