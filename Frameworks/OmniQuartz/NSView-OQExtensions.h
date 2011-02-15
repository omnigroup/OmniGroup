// Copyright 2005-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//  Created by Timothy J. Wood on 8/31/05.
//
// $Id$

#import <AppKit/NSView.h>

@class CIImage;

@interface NSView (OQExtensions)

- (CIImage *)newImage;
- (CIImage *)newImageFromRect:(NSRect)rect;
- (CIImage *)newImageFromRect:(NSRect)rect compatibleWithWindow:(NSWindow *)targetWindow;
- (CIImage *)newImageFromRect:(NSRect)rect compatibleWithWindow:(NSWindow *)targetWindow opaque:(BOOL)opaque;

- (void)fadeOutAndReplaceSubview:(NSView *)oldSubview withView:(NSView *)newSubview; // Uses NSViewAnimation

// Uses CIFilter and a custom animation.
- (void)transitionOutAndReplaceSubview:(NSView *)oldSubview withView:(NSView *)newSubview;
- (void)transitionOutAndReplaceSubview:(NSView *)oldSubview withView:(NSView *)newSubview reverse:(BOOL)reverse;

- (BOOL)writePNGImageToFile:(NSString *)path;

@end

