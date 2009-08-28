// Copyright 2003-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLQName.h>

RCS_ID("$Id$");

@implementation OFXMLQName

- initWithNamespace:(NSString *)namespace name:(NSString *)name;
{
    // _namespace can be in an element or attribute without a containing namespace declared.
    // _name can be empty if we are defining the QName for the default namespace with something like xmlns="myURI".  A prefixed namespace will be, xmlns:foo="myURI" and that attribute's QName will be {xmlns-URI, foo}. The default namespace will be {xmlns-URI, ""}.
    // At least one must be non-empty and we convert nil to empty strings to make comparison easier.
    OBPRECONDITION(![NSString isEmptyString:namespace] || ![NSString isEmptyString:name]);
    
    if (!namespace)
        namespace = @"";
    if (!name)
        name = @"";
    
    _namespace = [namespace copy];
    _name = [name copy];
    return self;
}

@synthesize namespace = _namespace, name = _name;

- (BOOL)isEqualToQName:(OFXMLQName *)otherName;
{
    if (self == otherName)
        return YES;

    // Ensuring the pointers are non-nil makes this compare easier.
    OBASSERT(_namespace);
    OBASSERT(_name);
    
    return [_namespace isEqualToString:otherName.namespace] && [_name isEqualToString:otherName.name];
}

#pragma mark Identity/hashing

- (NSUInteger)hash;
{
    return [_namespace hash] ^ [_name hash];
}

- (BOOL)isEqual:(id)otherObject;
{
    if (![otherObject isKindOfClass:[OFXMLQName class]])
        return NO;
    return [self isEqualToQName:(OFXMLQName *)otherObject];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

#pragma mark Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@ -- %@>", _namespace, _name];
}

@end

#define NS_XML "http://www.w3.org/XML/1998/namespace"
const char * const OFXMLNamespaceXMLCString = NS_XML;
NSString * const OFXMLNamespaceXML = (NSString *)CFSTR(NS_XML);
#undef NS_XML

#define NS_XMLNS "http://www.w3.org/2000/xmlns/"
const char * const OFXMLNamespaceXMLNSCString = NS_XMLNS;
NSString * const OFXMLNamespaceXMLNS = (NSString *)CFSTR(NS_XMLNS);
#undef NS_XMLNS
