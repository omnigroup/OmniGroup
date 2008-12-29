// Copyright 2008 Omni Development, Inc.  All rights reserved.
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

+ (ODOModel *)_model;
{
    static ODOModel *model = nil;
    if (!model) {
        // Intern our model strings
        [ODOModel internName:@"pk"];

        [ODOModel internName:Bug_EntityName];
        [ODOModel internName:Bug_DateAdded];
        [ODOModel internName:Bug_Title];
        [ODOModel internName:Bug_BugTags];
        [ODOModel internName:Bug_Notes];
        [ODOModel internName:Bug_State];
        
        [ODOModel internName:BugTag_EntityName];
        [ODOModel internName:BugTag_Bug];
        [ODOModel internName:BugTag_Tag];
        
        [ODOModel internName:Note_EntityName];
        [ODOModel internName:Note_Author];
        [ODOModel internName:Note_DateAdded];
        [ODOModel internName:Note_Text];
        [ODOModel internName:Note_Bug];
        
        [ODOModel internName:State_EntityName];
        [ODOModel internName:State_Name];
        [ODOModel internName:State_Bugs];
        
        [ODOModel internName:Tag_EntityName];
        [ODOModel internName:Tag_Name];
        [ODOModel internName:Tag_Bugs];
        
        NSString *modelPath = [[self resourceDirectory] stringByAppendingPathComponent:@"ODOPerf.xodo"];
        
        NSError *error = nil;
        model = [[ODOModel alloc] initWithContentsOfFile:modelPath error:&error];
        if (!model) {
            NSLog(@"Unable to load model from %@: %@", modelPath, [error toPropertyList]);
            return nil;
        }
    }
    return model;
}

- initWithName:(NSString *)name;
{
    if (!(self = [super initWithName:name]))
        return nil;

    ODOModel *model = [[self class] _model];
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
    State *state = [ODOEntity insertNewObjectForEntityForName:State_EntityName inEditingContext:_editingContext primaryKey:nil];
    [self setupCompleted];
    
    NSUInteger steps = [[self class] stepCount];
    while (steps--)
        [state valueForKey:State_Name];
}

- (void)perf_setStringProperty;
{
    State *state = [ODOEntity insertNewObjectForEntityForName:State_EntityName inEditingContext:_editingContext primaryKey:nil];
    [self setupCompleted];
    
    NSUInteger steps = [[self class] stepCount];
    while (steps--) {
        [state setValue:@"a" forKey:State_Name];
        [state setValue:@"b" forKey:State_Name];
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
            State *state = [ODOEntity insertNewObjectForEntityForName:State_EntityName inEditingContext:_editingContext primaryKey:nil];
            [state setValue:@"foo" forKey:State_Name];
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
            State *state = [ODOEntity insertNewObjectForEntityForName:State_EntityName inEditingContext:_editingContext primaryKey:nil];
            [state setValue:@"foo" forKey:State_Name];
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
        [fetch setEntity:[[_database model] entityNamed:State_EntityName]];

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

@end
