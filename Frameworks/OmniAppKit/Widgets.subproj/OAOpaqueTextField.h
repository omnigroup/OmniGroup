// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSTextField.h>

/*
 * A subclass of NSTextField that draws all of its ancestor views into its backing store before drawing its own content in order to get subpixel anti-aliasing.
 * In -drawRect:, if the current context is drawing to the screen, the view walks up its ancestor view hierarchy and asks all the views to -drawRect: (after applying the correct transformation so their drawing appears in the right place).
 *
 * The release notes for 10.8 promise that NSTextField will draw correctly on its own, but that's actually not true: <bug:///86159> (13299815: AppKit: NSTextField fails to draw with raised background style when layer-backed)
 */

@interface OAOpaqueTextField : NSTextField
{
    BOOL isDrawingToLayer;
    id drawingObserver;
}
@end
