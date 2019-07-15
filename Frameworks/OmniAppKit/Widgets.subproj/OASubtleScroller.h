// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSScroller.h>

/*! \brief A subclass of NSScroller that draws itself with a more subdued style. */

@interface OASubtleScroller : NSScroller

/*! Which edge of the sidebar's track should be drawn (given in bounds coordinates, so MinY=top if -isFlipped returns YES). If unset, derived from the scroller's direction and its userInterfaceDirection.*/
@property NSRectEdge visibleEdge;

/*! If old-style scrollers are enabled, NSScroller draws a solid white background. If not nil, the background will be filled with this color instead. */
@property (copy) NSColor *scrollerBackgroundColor;

@end
