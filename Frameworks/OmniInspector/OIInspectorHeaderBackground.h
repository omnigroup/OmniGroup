// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniInspector/OIInspectorHeaderBackground.h 91062 2007-09-11 21:18:41Z wiml $

#import <AppKit/NSView.h>

@class OIInspectorHeaderView;

@interface OIInspectorHeaderBackground : NSView
{
    OIInspectorHeaderView *windowHeader;
}

- (void)setHeaderView:(OIInspectorHeaderView *)header;

@end
