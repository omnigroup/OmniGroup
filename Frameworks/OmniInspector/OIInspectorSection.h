// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniInspector/OIInspectorSection.h 96302 2007-12-19 21:20:20Z bungi $

#import "OIInspector.h"

@interface OIInspectorSection : OIInspector
{
    IBOutlet NSView *firstKeyView;
}

- (NSView *)firstKeyView;

@end
