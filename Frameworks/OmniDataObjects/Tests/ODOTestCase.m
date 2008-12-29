// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOTestCase.h"

#import <OmniBase/OBUtilities.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <OmniFoundation/OFXMLIdentifierRegistry.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/Tests/ODOTestCase.m 104581 2008-09-06 21:18:23Z kc $")

@implementation ODOTestCase

+ (void)initialize;
{
    OBINITIALIZE;
    
    [ODOModel internName:@"pk"];
    [ODOModel internName:@"name"];
    [ODOModel internName:@"details"];
    [ODOModel internName:@"master"];
}

- (void)setUp;
{
    NSError *error = nil;
    NSBundle *testBundle = [NSBundle bundleWithIdentifier:OMNI_BUNDLE_IDENTIFIER];
    
    // Find the first <cls>.xodo file and use that as the model for this test.  ODOTestCase.xodo exists for generic tests that can share a model.
    Class cls = [self class];
    while (cls) {
        NSString *name = NSStringFromClass(cls);
        NSString *path = [testBundle pathForResource:name ofType:@"xodo"];
        if (path) {
            _model = [[ODOModel alloc] initWithContentsOfFile:path error:&error];
            if (!_model) {
                NSLog(@"Unable to load model from '%@': %@", path, [error toPropertyList]);
                exit(1);
            }
            break;
        }
        
        if (cls == [ODOTestCase class]) {
            OBASSERT_NOT_REACHED("Should have found the base model.");
            break;
        }
        
        cls = [cls superclass];
    }
    
    _database = [[ODODatabase alloc] initWithModel:_model];
    
    _databasePath = [[NSString alloc] initWithFormat:@"%@/%@-%@-%@.sqlite", NSTemporaryDirectory(), NSStringFromClass([self class]), [self name], [OFXMLCreateID() autorelease]];
    if (![_database connectToURL:[NSURL fileURLWithPath:_databasePath] error:&error]) {
        NSLog(@"Unable to connect to database at '%@': %@", _databasePath, [error toPropertyList]);
        exit(1);
    }
    
    _undoManager = [[NSUndoManager alloc] init];
    
    _editingContext = [[ODOEditingContext alloc] initWithDatabase:_database];
    [_editingContext setUndoManager:_undoManager];
    
    [super setUp];
}

- (void)tearDown;
{
    [_editingContext release];
    _editingContext = nil;
    
    [_undoManager removeAllActions];
    [_undoManager release];
    _undoManager = nil;
    
    if ([_database connectedURL]) {
        NSError *error = nil;
        if (![_database disconnect:&error])
            NSLog(@"Error disconnecting from database at %@: %@", _databasePath, [error toPropertyList]);
    }
    [_database release];
    _database = nil;
    
    if (_databasePath) {
        if (![[NSFileManager defaultManager] removeFileAtPath:_databasePath handler:nil])
            NSLog(@"Error removing database file at '%@'.", _databasePath);
        [_databasePath release];
        _databasePath = nil;
    }
    
    [_model release];
    _model = nil;
    
    [super tearDown];
}

- (BOOL)fileManager:(NSFileManager *)fm shouldProceedAfterError:(NSDictionary *)errorInfo;
{
    NSLog(@"error: %@", errorInfo);
    return NO;
}

- (void)closeUndoGroup;
{
    // This will actually close undo groups in all undo managers.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantPast]];
    should([_undoManager groupingLevel] == 0);
}

@end
