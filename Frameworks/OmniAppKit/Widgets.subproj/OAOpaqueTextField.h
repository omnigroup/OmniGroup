// Copyright 2012 Omni Development, Inc.  All rights reserved.
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
 * As of Mac OS X 10.8, NSTextField has started doing the right thing. But because we only get this new behavior if we don't override -drawRect:, this class only does any meaningful work when running on 10.7.
 */

@interface OAOpaqueTextField : NSTextField
{
    BOOL isDrawingToLayer;
    id drawingObserver;
}
@end
