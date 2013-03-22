// Copyright 2000-2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSView.h>

@interface NSView (OALayerBackedFix)

- (void)fixSubviewLayerOrdering; // For <bug:///86517> (13415520: -[NSView addSubview:positioned:relativeTo:] inserts sublayers in wrong position). Call this if you insert a view at the bottom of the subview stack, or else its layer will wind up beneath the tiling layer for its superview.

#if defined(MAC_OS_X_VERSION_10_8) && (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_8)

- (void)fixLayerGeometry; // For <bug:///62251> (8009542: CoreAnimation: Scroll view misbehaves with flipped layer-hosting document view). Call this if your view is flipped and your subviews appear in the wrong positions after a resize.

#endif

@end
