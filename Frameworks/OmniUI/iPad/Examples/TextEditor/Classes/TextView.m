// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextView.h"

#import "TextDocument.h"
#import "AppController.h"
#import "DocumentContentsZoomInspectorSlice.h"

RCS_ID("$Id$")

@implementation TextView

- (NSArray *)inspectableObjects;
{
    TextDocument *document = (TextDocument *)[[AppController controller] document];
    return [[super inspectableObjects] arrayByAddingObject:document];
}

- (NSArray *)inspector:(OUIInspector *)inspector makeAvailableSlicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;
{
    NSMutableArray *slices = [[[super inspector:inspector makeAvailableSlicesForStackedSlicesPane:pane] mutableCopy] autorelease];
    
    [slices insertObject:[[DocumentContentsZoomInspectorSlice new] autorelease] atIndex:0];
    
    return slices;
}

@end
