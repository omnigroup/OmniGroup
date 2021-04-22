// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

#import <OmniBase/OBUtilities.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>

#import "ODOTestCaseModel.h"

RCS_ID("$Id$")

OB_REQUIRE_ARC;

@implementation ODOTestCase

- (void)setUp;
{    
    _database = [[ODODatabase alloc] initWithModel:ODOTestCaseModel()];
    
    // Allow tests with 'unconnected' in the name to operate only in memory.
    if ([[self name] rangeOfString:@"unconnected"].length == 0) {
        _databasePath = [[NSString alloc] initWithFormat:@"%@/%@-%@-%@.sqlite", NSTemporaryDirectory(), NSStringFromClass([self class]), [self name], OFXMLCreateID()];

        NSError *error = nil;
        if (![_database connectToURL:[NSURL fileURLWithPath:_databasePath] error:&error]) {
            NSLog(@"Unable to connect to database at '%@': %@", _databasePath, [error toPropertyList]);
            exit(1);
        }
    }
    
    _undoManager = [[NSUndoManager alloc] init];
    
    _editingContext = [[ODOEditingContext alloc] initWithDatabase:_database];
    [_editingContext assumeOwnershipWithQueue:dispatch_get_main_queue()];
    [_editingContext setUndoManager:_undoManager];
    
    [super setUp];
}

- (void)tearDown;
{
    [_editingContext reset];

    [_undoManager removeAllActions];
    _undoManager = nil;
    
    if ([_database connectedURL]) {
        NSError *error = nil;
        if (![_database disconnect:&error])
            NSLog(@"Error disconnecting from database at '%@': %@", _databasePath, [error toPropertyList]);
    }
    _database = nil;
    
    [_editingContext relinquishOwnerhip];
    _editingContext = nil;

    if (_databasePath) {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] removeItemAtPath:_databasePath error:&error])
            NSLog(@"Error removing database file at '%@': %@", _databasePath, [error toPropertyList]);
        _databasePath = nil;
    }
    
    [super tearDown];
}

- (void)closeUndoGroup;
{
    [_editingContext processPendingChanges];
    
    // This will actually close undo groups in all undo managers.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantPast]];
    XCTAssertTrue([_undoManager groupingLevel] == 0);
}

- (BOOL)save:(NSError **)outError;
{
    [self closeUndoGroup];
    return [_editingContext saveWithDate:[NSDate date] error:outError];
}

@end

@implementation ODOTestCaseObject

+ (BOOL)objectIDShouldBeUndeletable:(ODOObjectID *)objectID;
{
    NSString *primaryKey = objectID.primaryKey;
    OBASSERT(![NSString isEmptyString:primaryKey]);
    
    return [primaryKey containsString:@"undeletable"];
}

@end

@implementation ODOTestCaseMaster
ODOTestCaseMaster_DynamicProperties;
@end
@implementation ODOTestCaseDetail
ODOTestCaseDetail_DynamicProperties;
@end
@implementation ODOTestCaseAllAttributeTypes
ODOTestCaseAllAttributeTypes_DynamicProperties;
@end
@implementation ODOTestCaseOptionalScalarTypes
ODOTestCaseOptionalScalarTypes_DynamicProperties;
@end
@implementation ODOTestCaseOptionalDate
ODOTestCaseOptionalDate_DynamicProperties;
@end
@implementation ODOTestCaseMultipleBooleans
ODOTestCaseMultipleBooleans_DynamicProperties;
@end
@implementation ODOTestCaseInterleavedSizeScalars
ODOTestCaseInterleavedSizeScalars_DynamicProperties;
@end
@implementation ODOTestCaseCalculatedProperty
ODOTestCaseCalculatedProperty_DynamicProperties;

+ (void)addChangeActionsForProperty:(ODOProperty *)property_ willActions:(ODOChangeActions *)willActions didActions:(ODOChangeActions *)didActions;
{
    [super addChangeActionsForProperty:property_ willActions:willActions didActions:didActions];

    NSString *key = property_.name;

    if ([key isEqual:ODOTestCaseCalculatedPropertyB0] || [key isEqual:ODOTestCaseCalculatedPropertyB0]) {
        [didActions append:^(ODOTestCaseCalculatedProperty *object, ODOProperty *property){
            [object invalidateCalculatedValueForKey:ODOTestCaseCalculatedPropertyXor];
        }];
    } else if ([key isEqual:ODOTestCaseCalculatedPropertyStr0] || [key isEqual:ODOTestCaseCalculatedPropertyStr1]) {
        [didActions append:^(ODOTestCaseCalculatedProperty *object, ODOProperty *property){
            [object invalidateCalculatedValueForKey:ODOTestCaseCalculatedPropertyConcat];
        }];
    }
}

- (id)calculateValueForXor;
{
    return @(self.b0 ^ self.b1);
}

- (id)calculateValueForConcat;
{
    return [self.str0 stringByAppendingString:self.str1];
}

@end
@implementation ODOTestCaseLeftHand
ODOTestCaseLeftHand_DynamicProperties;
@end
@implementation ODOTestCaseRightHand
ODOTestCaseRightHand_DynamicProperties;
@end
@implementation ODOTestCaseLeftHandRequired
ODOTestCaseLeftHandRequired_DynamicProperties;
@end
@implementation ODOTestCaseRightHandRequired
ODOTestCaseRightHandRequired_DynamicProperties;
@end
@implementation ODOTestCasePeerA
ODOTestCasePeerA_DynamicProperties;
@end
@implementation ODOTestCasePeerB
ODOTestCasePeerB_DynamicProperties;
@end

// The generated model source
#import "ODOTestCaseModel.m"

