// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODORelationship.h>

@class OFEnumNameTable;

extern NSString * const ODORelationshipElementName;
extern NSString * const ODORelationshipDeleteRuleAttributeName;
extern NSString * const ODORelationshipToManyAttributeName;
extern NSString * const ODORelationshipDestinationEntityAttributeName;
extern NSString * const ODORelationshipInverseRelationshipAttributeName;

extern OFEnumNameTable * ODORelationshipDeleteRuleEnumNameTable(void);

@interface ODORelationship (Internal)
- (id)initWithCursor:(OFXMLCursor *)cursor entity:(ODOEntity *)entity error:(NSError **)outError;
- (BOOL)finalizeModelLoading:(NSError **)outError;
@end
