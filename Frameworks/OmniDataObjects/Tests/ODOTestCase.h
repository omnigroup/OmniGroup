// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniBase/rcsid.h>
#import <OmniBase/NSError-OBExtensions.h>

#import "ODOTestCaseModel.h"

@interface ODOTestCase : OFTestCase
{
    NSString *_databasePath;
    ODODatabase *_database;
    NSUndoManager *_undoManager;
    ODOEditingContext *_editingContext;
}

- (void)closeUndoGroup;

@end
