// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOPerf_CoreData.h"

#define ODO_PERF_MODEL_CD 1
#include "ODOPerfModel_Impl.h"

RCS_ID("$Id$")

@implementation ODOPerf_CoreData

- initWithName:(NSString *)name;
{
    if (!(self = [super initWithName:name]))
        return nil;
    
    NSString *modelPath = [[[self class] resourceDirectory] stringByAppendingPathComponent:@"ODOPerf.mom"];
    NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:modelPath]] autorelease];
    if (!model) {
        NSLog(@"Unable to load model from %@", modelPath);
        [self release];
        return nil;
    }
    
    _psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    
    NSString *storePath = self.storePath;
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:NULL];
    
    NSError *error = nil;
    _ps = [[_psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:[NSURL fileURLWithPath:storePath] options:nil error:&error] retain];
    if (!_ps) {
        NSLog(@"Unable to create persistent store at %@: %@", storePath, [error toPropertyList]);
        [self release];
        return nil;
    }
    
    _undoManager = [[NSUndoManager alloc] init];
    _moc = [[NSManagedObjectContext alloc] init];
    [_moc setUndoManager:_undoManager];
    [_moc setPersistentStoreCoordinator:_psc];
    
    return self;
}

- (void)dealloc;
{
    [_moc release];
    [_undoManager release];
    [_ps release];
    [_psc release];
    
    [super dealloc];
}

- (void)perf_getStringProperty;
{
    State *state = [NSEntityDescription insertNewObjectForEntityForName:ODOPerfStateEntityName inManagedObjectContext:_moc];
    [self setupCompleted];
    
    NSUInteger steps = [[self class] stepCount];
    while (steps--)
        [state valueForKey:ODOPerfStateName];
}

- (void)perf_setStringProperty;
{
    State *state = [NSEntityDescription insertNewObjectForEntityForName:ODOPerfStateEntityName inManagedObjectContext:_moc];
    [self setupCompleted];
    
    NSUInteger steps = [[self class] stepCount];
    while (steps--) {
        [state setValue:@"a" forKey:ODOPerfStateName];
        [state setValue:@"b" forKey:ODOPerfStateName];
    }
}

- (void)perf_getDynamicStringProperty;
{
    State *state = [NSEntityDescription insertNewObjectForEntityForName:ODOPerfStateEntityName inManagedObjectContext:_moc];
    [self setupCompleted];
    
    NSUInteger steps = [[self class] stepCount];
    while (steps--)
        state.name;
}

- (void)perf_setDynamicStringProperty;
{
    State *state = [NSEntityDescription insertNewObjectForEntityForName:ODOPerfStateEntityName inManagedObjectContext:_moc];
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
            State *state = [NSEntityDescription insertNewObjectForEntityForName:ODOPerfStateEntityName inManagedObjectContext:_moc];
            [state setValue:@"foo" forKey:ODOPerfStateName];
        }
        
        NSError *error = nil;
        if (![_moc save:&error]) {
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
            State *state = [NSEntityDescription insertNewObjectForEntityForName:ODOPerfStateEntityName inManagedObjectContext:_moc];
            [state setValue:@"foo" forKey:ODOPerfStateName];
        }
        
        NSError *error = nil;
        if (![_moc save:&error]) {
            NSLog(@"Unable to save: %@", [error toPropertyList]);
            return;
        }
        
        [pool release];
    }
    
    [self setupCompleted];
    
    // Fetch the objects back a bunch of times
    {
        NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
        [fetch setEntity:[[[_psc managedObjectModel] entitiesByName] objectForKey:ODOPerfStateEntityName]];
        
        NSUInteger batches = MAX(1U, [[self class] stepCount]/batchSize);
        while (batches--) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            [_moc reset];
            
            NSError *error = nil;
            if (![_moc executeFetchRequest:fetch error:&error]) {
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
        State *state = [NSEntityDescription insertNewObjectForEntityForName:ODOPerfStateEntityName inManagedObjectContext:_moc];
        [state setValue:@"open" forKey:ODOPerfStateName];
        [pool release];
        
        NSUInteger batchSize = 100;
        NSUInteger batches = MAX(1U, stepCount/batchSize);
        
        while (batches--) {
            NSUInteger batchIndex;
            pool = [[NSAutoreleasePool alloc] init];
            NSDate *date = [NSDate date];
            for (batchIndex = 0; batchIndex < batchSize; batchIndex++) {
                Bug *bug = [NSEntityDescription insertNewObjectForEntityForName:ODOPerfBugEntityName inManagedObjectContext:_moc];
                [bug setValue:date forKey:ODOPerfBugDateAdded];
                [bug setValue:@"bug" forKey:ODOPerfBugTitle];
                [bug setValue:state forKey:ODOPerfBugState];
            }
            
            NSError *error = nil;
            if (![_moc save:&error]) {
                NSLog(@"Unable to save: %@", [error toPropertyList]);
                return;
            }
            
            [pool release];
        }
    }
    
    // Reset to get everything out of memory, refetch the state we want.
    [_moc reset];
    State *state;
    {
        NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
        [fetch setEntity:[[[_psc managedObjectModel] entitiesByName] objectForKey:ODOPerfStateEntityName]];
        
        NSError *error = nil;
        NSArray *states = [_moc executeFetchRequest:fetch error:&error];
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
//    ODOLogSQL = YES;
    {
        NSDate *date = [NSDate date];
        Bug *bug = [NSEntityDescription insertNewObjectForEntityForName:ODOPerfBugEntityName inManagedObjectContext:_moc];
        [bug setValue:date forKey:ODOPerfBugDateAdded];
        [bug setValue:@"bug" forKey:ODOPerfBugTitle];
        [bug setValue:state forKey:ODOPerfBugState];
        
        NSError *error = nil;
        if (![_moc save:&error]) {
            NSLog(@"Unable to save: %@", [error toPropertyList]);
            return;
        }
        
        OBASSERT([state hasFaultForRelationshipNamed:ODOPerfStateBugs]);
    }
//    ODOLogSQL = NO;
}

@end
