// Copyright 2002-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIDynamicInspectorMenuItem.h"

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <OmniInspector/OIInspectorGroup.h>
#import <OmniInspector/OIInspectorRegistry.h>

RCS_ID("$Id$");

@implementation OIDynamicInspectorMenuItem

- (void)awakeFromNib;
{
    [OIInspectorGroup setDynamicMenuPlaceholder:self];
    [[OIInspectorRegistry inspectorRegistryForMainWindow] dynamicMenuPlaceholderSet];
}

@end
