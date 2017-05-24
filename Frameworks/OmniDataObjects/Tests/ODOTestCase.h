// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFTestCase.h"

#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>
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
- (BOOL)save:(NSError **)outError;

@end

@interface ODOTestCaseObject : ODOObject
@end

@interface ODOTestCaseMaster : ODOTestCaseObject
@end
#import "ODOTestCaseMaster-Properties.h"
@interface ODOTestCaseDetail : ODOTestCaseObject
@end
#import "ODOTestCaseDetail-Properties.h"
@interface ODOTestCaseAllAttributeTypes : ODOTestCaseObject
@end
#import "ODOTestCaseAllAttributeTypes-Properties.h"

@interface ODOTestCaseLeftHand : ODOTestCaseObject
@end
#import "ODOTestCaseLeftHand-Properties.h"

@interface ODOTestCaseRightHand : ODOTestCaseObject
@end
#import "ODOTestCaseRightHand-Properties.h"

@interface ODOTestCaseLeftHandRequired : ODOTestCaseObject
@end
#import "ODOTestCaseLeftHandRequired-Properties.h"

@interface ODOTestCaseRightHandRequired : ODOTestCaseObject
@end
#import "ODOTestCaseRightHandRequired-Properties.h"

@interface ODOTestCasePeerA : ODOTestCaseObject
@end
#import "ODOTestCasePeerA-Properties.h"

@interface ODOTestCasePeerB : ODOTestCaseObject
@end
#import "ODOTestCasePeerB-Properties.h"

static inline id _insertTestObject(ODOEditingContext *ctx, Class cls, NSString *entityName, NSString *pk)
{
    OBPRECONDITION(ctx);
    OBPRECONDITION(cls);
    OBPRECONDITION(entityName);
    ODOObject *object = [[[cls alloc] initWithEntity:[ODOTestCaseModel() entityNamed:entityName] primaryKey:pk insertingIntoEditingContext:ctx] autorelease];
    return object;
}
#define INSERT_TEST_OBJECT(cls, name) cls *name = _insertTestObject(_editingContext, [cls class], cls ## EntityName, (NSString *)CFSTR(#name)); OB_UNUSED_VALUE(name)
#define MASTER(x) INSERT_TEST_OBJECT(ODOTestCaseMaster, x)

static inline ODOTestCaseDetail *_insertDetail(ODOEditingContext *ctx, NSString *pk, ODOTestCaseMaster *master)
{
    ODOTestCaseDetail *detail = [[[ODOTestCaseDetail alloc] initWithEntity:[ODOTestCaseModel() entityNamed:ODOTestCaseDetailEntityName] primaryKey:pk insertingIntoEditingContext:ctx] autorelease];
    
    if (master)
        detail.master = master;
    
    return detail;
}
#define DETAIL(x,master) ODOTestCaseDetail *x = _insertDetail(_editingContext, (NSString *)CFSTR(#x), master); OB_UNUSED_VALUE(x)

#define NoMaster (nil)

