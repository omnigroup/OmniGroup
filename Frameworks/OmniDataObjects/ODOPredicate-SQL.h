// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOPredicate-SQL.h 104583 2008-09-06 21:23:18Z kc $

#import <OmniDataObjects/ODOPredicate.h>

@class ODOEntity;

@interface NSPredicate (SQL)
- (BOOL)_appendSQL:(NSMutableString *)sql entity:(ODOEntity *)entity constants:(NSMutableArray *)constants error:(NSError **)outError;
@end
@interface NSExpression (SQL)
- (BOOL)_appendSQL:(NSMutableString *)sql entity:(ODOEntity *)entity constants:(NSMutableArray *)constants error:(NSError **)outError;
@end
