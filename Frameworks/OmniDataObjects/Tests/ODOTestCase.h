// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/Tests/ODOTestCase.h 104581 2008-09-06 21:18:23Z kc $

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniBase/rcsid.h>
#import <OmniFoundation/NSError-OFExtensions.h>

@interface ODOTestCase : OFTestCase
{
    ODOModel *_model;
    NSString *_databasePath;
    ODODatabase *_database;
    NSUndoManager *_undoManager;
    ODOEditingContext *_editingContext;
}

- (void)closeUndoGroup;

@end
