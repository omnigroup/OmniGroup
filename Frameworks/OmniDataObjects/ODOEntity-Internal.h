// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOEntity.h>

@class OFXMLCursor;

extern NSString * const ODOEntityElementName;
extern NSString * const ODOEntityNameAttributeName;
extern NSString * const ODOEntityInstanceClassAttributeName;

@interface ODOEntity (Internal)
- (id)initWithCursor:(OFXMLCursor *)cursor model:(ODOModel *)model error:(NSError **)outError;
- (BOOL)finalizeModelLoading:(NSError **)outError;
- (NSArray *)snapshotProperties;
@end
