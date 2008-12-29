// Copyright 2002-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIDynamicInspectorMenuItem.h"

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

#import "OIInspectorGroup.h"
#import "OIInspectorRegistry.h"

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniInspector/OIDynamicInspectorMenuItem.m 72316 2006-02-07 18:59:27Z bungi $");

@interface OIDynamicInspectorMenuItem (Private)
@end

@implementation OIDynamicInspectorMenuItem

- (void)awakeFromNib;
{
    [OIInspectorGroup setDynamicMenuPlaceholder:self];
    [[OIInspectorRegistry sharedInspector] dynamicMenuPlaceholderSet];
}

@end

@implementation OIDynamicInspectorMenuItem (Private)
@end
