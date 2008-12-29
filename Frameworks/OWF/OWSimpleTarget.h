// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSConditionLock;
@class OWContentInfo, OWContentType;

#import <OmniFoundation/OFWeakRetainConcreteImplementation.h>
#import <OWF/OWContent.h>
#import <OWF/OWTargetProtocol.h>

@interface OWSimpleTarget : OFObject <OWTarget, OFWeakRetain>
{
    OWContent *initialContent;
    
    OWContentInfo *parentContentInfo;
    OWContentType *targetContentType;
    NSString *targetTypeFormatString;
    
    NSConditionLock *resultLock;
    OWContent *resultingContent;
    OWTargetContentOffer resultingContentFlags;
    OWAddress *addressOfLastContent;
    
    OFWeakRetainConcreteImplementation_IVARS;
}

- (id)initWithParentContentInfo:(OWContentInfo *)contentInfo targetContentType:(OWContentType *)contentType initialContent:(OWContent *)someContent;

- (void)setTargetTypeFormatString:(NSString *)newFormatString;  // defaults to "%@ File". NB: The string passed to this method must already be localized into the user's language.

- (void)startProcessingContent;
- (OWContent *)resultingContent;
- (OWTargetContentOffer)resultingContentFlags;
- (OWAddress *)lastAddress;

OFWeakRetainConcreteImplementation_INTERFACE

@end
