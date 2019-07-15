// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class OFXMLQName;

@interface OFXMLUnparsedElement : OFObject

- initWithQName:(OFXMLQName *)qname identifier:(NSString *)identifier data:(NSData *)data; 

@property(nonatomic,readonly) OFXMLQName *qname;
@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) NSData *data;

@property(nonatomic,readonly) NSString *name; // returns the local name for compatibility with OFXMLElement, at least until the whole stack is QName aware

@end
