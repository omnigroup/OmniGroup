// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class OWContentTypeLink;

@interface OWConversionPathElement : OFObject
{
    OWConversionPathElement *nextElement;
    OWContentTypeLink *link;
    float totalCost;
}

+ (OWConversionPathElement *)elementLink: (OWContentTypeLink *) aLink nextElement: (OWConversionPathElement *) anElement;

- initWithLink:(OWContentTypeLink *)aLink nextElement: (OWConversionPathElement *) anElement;

- (OWConversionPathElement *) nextElement;
- (OWContentTypeLink *) link;
- (float) totalCost;

@end
