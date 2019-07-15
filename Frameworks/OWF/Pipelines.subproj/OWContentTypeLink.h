// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class OWContentType, OWProcessorDescription;

@interface OWContentTypeLink : OFObject
{
    OWContentType *sourceContentType;
    OWContentType *targetContentType;
    OWProcessorDescription *processorDescription;
    float cost;
}

- initWithProcessorDescription:(OWProcessorDescription *)aProcessorDescription sourceContentType:(OWContentType *)fromContentType targetContentType:(OWContentType *)toContentType cost:(float)aCost;

- (OWContentType *)sourceContentType;
- (OWContentType *)targetContentType;
- (OWProcessorDescription *) processorDescription;
- (NSString *)processorClassName;
- (float)cost;

@end
