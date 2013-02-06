// Copyright 1997-2005, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSArray;
@class NSEvent, NSImage, NSPasteboard, NSView;
@class OAPasteboardHelper;

#import <Foundation/NSGeometry.h> // For NSPoint

@interface OADragController : NSObject

+ (OADragController *)sharedDragController;

- (void)startDragFromView:(NSView *)view image:(NSImage *)image atPoint:(NSPoint)location offset:(NSPoint)offset event:(NSEvent *)event slideBack:(BOOL)slideBack pasteboardHelper:(OAPasteboardHelper *)newPasteboardHelper;

- (NSView *)view;

@end

