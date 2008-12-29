// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOAttribute.h>

extern NSString * const ODOAttributeElementName;
extern NSString * const ODOAttributeTypeAttributeName;
extern NSString * const ODOAttributeDefaultValueAttributeName;
extern NSString * const ODOAttributePrimaryKeyAttributeName;

extern OFEnumNameTable * ODOAttributeTypeEnumNameTable(void);

@interface ODOAttribute (Internal)
- (id)initWithCursor:(OFXMLCursor *)cursor entity:(ODOEntity *)entity error:(NSError **)outError;
- (BOOL)isPrimaryKey;
@end
