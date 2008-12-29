// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OADragController.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class NSArray;
@class NSEvent, NSImage, NSPasteboard, NSView;
@class OAPasteboardHelper;

#import <Foundation/NSGeometry.h> // For NSPoint
#import <OmniFoundation/OFWeakRetainConcreteImplementation.h>

@interface OADragController : OFObject <OFWeakRetain>
{
    NSPasteboard *draggingPasteboard;
    OAPasteboardHelper *pasteboardHelper;
    NSView *draggingFromView;
    id delegate;
}

+ (OADragController *)sharedDragController;

- (void)startDragFromView:(NSView *)view image:(NSImage *)image atPoint:(NSPoint)location offset:(NSPoint)offset event:(NSEvent *)event slideBack:(BOOL)slideBack pasteboardHelper:(OAPasteboardHelper *)newPasteboardHelper delegate:(id)newDelegate;

- (NSView *)view;

@end

