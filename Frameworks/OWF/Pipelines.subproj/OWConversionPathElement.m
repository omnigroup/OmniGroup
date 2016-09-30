// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWConversionPathElement.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContentType.h>
#import <OWF/OWContentTypeLink.h>

RCS_ID("$Id$")

@implementation OWConversionPathElement

+ (OWConversionPathElement *)elementLink:(OWContentTypeLink *)aLink nextElement:(OWConversionPathElement *)anElement;
{
    return [[self alloc] initWithLink:aLink nextElement:anElement];
}

- initWithLink:(OWContentTypeLink *)aLink nextElement:(OWConversionPathElement *)anElement;
{
    // nextElement can be nil
    OBPRECONDITION(aLink);
    
    nextElement = anElement;
    link = aLink;
    totalCost = nextElement ? [nextElement totalCost] : 0.0f;
    totalCost += [link cost];
    
    return self;
}

- (OWConversionPathElement *)nextElement;
{
    return nextElement;
}

- (OWContentTypeLink *)link;
{
    return link;
}

- (float)totalCost;
{
    return totalCost;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    if (nextElement)
	[debugDictionary setObject:nextElement forKey:@"nextElement"];
    if (link)
	[debugDictionary setObject:link forKey:@"link"];
    [debugDictionary setObject: [NSNumber numberWithFloat: totalCost] forKey: @"totalCost"];
    return debugDictionary;
}

@end
