// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#ifndef __cplusplus // 'namespace' as a argument/property annoys ObjC++
    
@interface OFXMLQName : OFObject <NSCopying>

- initWithNamespace:(NSString *)namespace name:(NSString *)name;

// The resolved namespace of the name.  For example, <foo:bar/> would be resolved to whatever has previously been declared as the value of a "xmlns:foo" attribute.
@property(nonatomic,readonly) NSString *namespace;

// The non-namespace portion of the element name.  For example, <foo:bar/> would be "bar".
@property(nonatomic,readonly) NSString *name;

- (BOOL)isEqualToQName:(OFXMLQName *)otherName;

@end

#endif

// Standard namespace URIs; these cannot be defined by use of xmlns attributes but are built-in

extern const char * const OFXMLNamespaceXMLCString; // bound to the 'xml' prefix
extern NSString * const OFXMLNamespaceXML;

extern const char * const OFXMLNamespaceXMLNSCString; // bound to the 'xmlns' prefix
extern NSString * const OFXMLNamespaceXMLNS;
