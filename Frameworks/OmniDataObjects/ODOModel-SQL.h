// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOModel-SQL.h 104581 2008-09-06 21:18:23Z kc $

#import <OmniDataObjects/ODOModel.h>

@class ODODatabase;

@interface ODOModel (SQL)
- (BOOL)_createSchemaInDatabase:(ODODatabase *)database error:(NSError **)outError;
@end
