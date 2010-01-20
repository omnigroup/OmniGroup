// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OFXMLQName;

@interface OFXMLUnparsedElement : OFObject
{
@private
    OFXMLQName *_qname;
    NSString *_identifier;
    NSData *_data;
}

- initWithQName:(OFXMLQName *)qname identifier:(NSString *)identifier data:(NSData *)data; 

@property(readonly) OFXMLQName *qname;
@property(readonly) NSString *identifier;
@property(readonly) NSData *data;

@property(readonly) NSString *name; // returns the local name for compatibility with OFXMLElement, at least until the whole stack is QName aware

@end
