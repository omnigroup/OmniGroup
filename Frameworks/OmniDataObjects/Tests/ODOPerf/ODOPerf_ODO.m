// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOPerf_ODO.h"

#define ODO_PERF_MODEL_ODO 1
#include "ODOPerfModel_Impl.h"

RCS_ID("$Id$")

@implementation ODOPerf_ODO

- initWithName:(NSString *)name;
{
    if (!(self = [super initWithName:name]))
        return nil;

    ODOModel *model = ODOPerfModel();
    if (!model) {
        [self release];
        return nil;
    }
    
    _database = [[ODODatabase alloc] initWithModel:model];
    
    NSString *storePath = self.storePath;
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:NULL];

    NSError *error = nil;
    if (![_database connectToURL:[NSURL fileURLWithPath:storePath] error:&error]) {
        NSLog(@"Unable to connect to store at %@: %@", storePath, [error toPropertyList]);
        [self release];
        return nil;
    }

    _editingContext = [[ODOEditingContext alloc] initWithDatabase:_database];
    
    _undoManager = [[NSUndoManager alloc] init];
    [_editingContext setUndoManager:_undoManager];
    
    return self;
}

- (void)dealloc;
{
    [_editingContext reset];
    [_editingContext release];
    [_undoManager release];
    
    if ([_database connectedURL]) {
        NSError *error = nil;
        if (![_database disconnect:&error])
            NSLog(@"Unable to disconnect database: %@", [error toPropertyList]);
    }
    [_database release];
    
    [super dealloc];
}

- (void)perf_getStringProperty;
{
    State *state = [ODOEntity insertNewObjectForEntityForName:ODOPerfStateEntityName inEditingContext:_editingContext primaryKey:nil];
    [self setupCompleted];
    
    NSUInteger steps = [[self class] stepCount];
    while (steps--)
        [state valueForKey:ODOPerfStateName];
}

- (void)perf_setStringProperty;
{
    State *state = [ODOEntity insertNewObjectForEntityForName:ODOPerfStateEntityName inEditingContext:_editingContext primaryKey:nil];
    [self setupCompleted];
    
    NSUInteger steps = [[self class] stepCount];
    while (steps--) {
        [state setValue:@"a" forKey:ODOPerfStateName];
        [state setValue:@"b" forKey:ODOPerfStateName];
    }
}

- (void)perf_getDynamicStringProperty;
{
    State *state = [ODOEntity insertNewObjectForEntityForName:ODOPerfStateEntityName inEditingContext:_editingContext primaryKey:nil];
    [self setupCompleted];
    
    NSUInteger steps = [[self class] stepCount];
    while (steps--)
        state.name;
}

- (void)perf_setDynamicStringProperty;
{
    State *state = [ODOEntity insertNewObjectForEntityForName:ODOPerfStateEntityName inEditingContext:_editingContext primaryKey:nil];
    [self setupCompleted];
    
    NSUInteger steps = [[self class] stepCount];
    while (steps--) {
        state.name = @"a";
        state.name = @"b";
    }
}

- (void)perf_insertObjects;
{
    NSUInteger batchSize = 100;
    NSUInteger batches = MAX(1U, [[self class] stepCount]/batchSize);
    
    while (batches--) {
        NSUInteger batchIndex;
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        for (batchIndex = 0; batchIndex < batchSize; batchIndex++) {
            State *state = [ODOEntity insertNewObjectForEntityForName:ODOPerfStateEntityName inEditingContext:_editingContext primaryKey:nil];
            [state setValue:@"foo" forKey:ODOPerfStateName];
        }
        
        NSError *error = nil;
        if (![_editingContext saveWithDate:[NSDate date] error:&error]) {
            NSLog(@"Unable to save: %@", [error toPropertyList]);
            return;
        }
        
        [pool release];
    }
}

- (void)perf_fetchObjects;
{
    // Get some objects inserted.
    NSUInteger batchSize = 100;
    {
        NSUInteger batchIndex;
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        for (batchIndex = 0; batchIndex < batchSize; batchIndex++) {
            State *state = [ODOEntity insertNewObjectForEntityForName:ODOPerfStateEntityName inEditingContext:_editingContext primaryKey:nil];
            [state setValue:@"foo" forKey:ODOPerfStateName];
        }
        
        NSError *error = nil;
        if (![_editingContext saveWithDate:[NSDate date] error:&error]) {
            NSLog(@"Unable to save: %@", [error toPropertyList]);
            return;
        }
        
        [pool release];
    }
    
    [self setupCompleted];
    
    // Fetch the objects back a bunch of times
    {
        ODOFetchRequest *fetch = [[ODOFetchRequest alloc] init];
        [fetch setEntity:[[_database model] entityNamed:ODOPerfStateEntityName]];

        NSUInteger batches = MAX(1U, [[self class] stepCount]/batchSize);
        while (batches--) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            [_editingContext reset];
            
            NSError *error = nil;
            if (![_editingContext executeFetchRequest:fetch error:&error]) {
                NSLog(@"Unable to fetch: %@", [error toPropertyList]);
                return;
            }
            
            [pool release];
        }

        [fetch release];
    }
}

- (void)perf_editToOneRelationship;
{
    // Make a bunch of bugs pointing to a state.
    NSUInteger stepCount = 10000; // Not obeying the global default
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        State *state = [ODOEntity insertNewObjectForEntityForName:ODOPerfStateEntityName inEditingContext:_editingContext primaryKey:nil];
        [state setValue:@"open" forKey:ODOPerfStateName];
        [pool release];
        
        NSUInteger batchSize = 100;
        NSUInteger batches = MAX(1U, stepCount/batchSize);
        
        while (batches--) {
            NSUInteger batchIndex;
            pool = [[NSAutoreleasePool alloc] init];
            NSDate *date = [NSDate date];
            for (batchIndex = 0; batchIndex < batchSize; batchIndex++) {
                Bug *bug = [ODOEntity insertNewObjectForEntityForName:ODOPerfBugEntityName inEditingContext:_editingContext primaryKey:nil];
                [bug setValue:date forKey:ODOPerfBugDateAdded];
                [bug setValue:@"bug" forKey:ODOPerfBugTitle];
                [bug setValue:state forKey:ODOPerfBugState];
            }
            
            NSError *error = nil;
            if (![_editingContext saveWithDate:date error:&error]) {
                NSLog(@"Unable to save: %@", [error toPropertyList]);
                return;
            }
            
            [pool release];
        }
    }
    
    // Reset to get everything out of memory, refetch the state we want.
    [_editingContext reset];
    State *state;
    {
        ODOFetchRequest *fetch = [[ODOFetchRequest alloc] init];
        [fetch setEntity:[[_database model] entityNamed:ODOPerfStateEntityName]];

        NSError *error = nil;
        NSArray *states = [_editingContext executeFetchRequest:fetch error:&error];
        if (!states) {
            NSLog(@"Unable to fetch: %@", [error toPropertyList]);
            return;
        }
        OBASSERT([states count] == 1);
        state = [states lastObject];
        OBASSERT([state hasFaultForRelationshipNamed:ODOPerfStateBugs]);
    }
    
    [self setupCompleted];
    
    // Insert one bug refering to the existing state.
    ODOLogSQL = YES;
    {
        NSDate *date = [NSDate date];
        Bug *bug = [ODOEntity insertNewObjectForEntityForName:ODOPerfBugEntityName inEditingContext:_editingContext primaryKey:nil];
        [bug setValue:date forKey:ODOPerfBugDateAdded];
        [bug setValue:@"bug" forKey:ODOPerfBugTitle];
        [bug setValue:state forKey:ODOPerfBugState];
        
        NSError *error = nil;
        if (![_editingContext saveWithDate:[NSDate date] error:&error]) {
            NSLog(@"Unable to save: %@", [error toPropertyList]);
            return;
        }
        
        OBASSERT([state hasFaultForRelationshipNamed:ODOPerfStateBugs]);
    }
    ODOLogSQL = NO;
}

@end
