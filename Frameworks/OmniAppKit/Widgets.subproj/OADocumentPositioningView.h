// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


/*
This view class is intended to keep a subview (the "document view") aligned in the content area of a scroll view. Clients will not generally use this class directly, but will use the convenience methods added to NSScrollView for setting the alignment. A client would need to use this class directly if they needed to swap out the document view, however, as simply changing the scroll view's document view will replace any positioning view with the new document view.
*/


#import <AppKit/NSView.h>
#import <AppKit/NSImageCell.h>	// for NSImageAlignment


@interface OADocumentPositioningView : NSView
{
@private
    NSView *documentView;
    NSImageAlignment documentViewAlignment;
}

// API

- (NSView *)documentView;
- (void)setDocumentView:(NSView *)value;

- (NSImageAlignment)documentViewAlignment;
- (void)setDocumentViewAlignment:(NSImageAlignment)value;

@end
