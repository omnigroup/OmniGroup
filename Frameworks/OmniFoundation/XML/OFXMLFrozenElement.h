// Copyright 2005, 2008, 2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/OFXMLBuffer.h>

@class NSArray, NSError;
@class OFXMLDocument;

@interface OFXMLFrozenElement : OFObject
{
    NSString  *_name;
    NSArray   *_children;
    NSArray   *_attributeNamesAndValues;
}

// API
- initWithName:(NSString *)name children:(NSArray *)children attributes:(NSDictionary *)attributes attributeOrder:(NSArray *)attributeOrder;

- (NSString *)name;

- (BOOL)appendXML:(OFXMLBuffer)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;

@end
