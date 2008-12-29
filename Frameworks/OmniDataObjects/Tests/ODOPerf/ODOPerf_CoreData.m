// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOPerf_CoreData.h"

#define ODO_PERF_MODEL_CD 1
#include "ODOPerfModel_Impl.h"

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/Tests/ODOPerf/ODOPerf_CoreData.m 104583 2008-09-06 21:23:18Z kc $")

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
    State *state = [NSEntityDescription insertNewObjectForEntityForName:State_EntityName inManagedObjectContext:_moc];
    [self setupCompleted];
    
    NSUInteger steps = [[self class] stepCount];
    while (steps--)
        [state valueForKey:State_Name];
}

- (void)perf_setStringProperty;
{
    State *state = [NSEntityDescription insertNewObjectForEntityForName:State_EntityName inManagedObjectContext:_moc];
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
            State *state = [NSEntityDescription insertNewObjectForEntityForName:State_EntityName inManagedObjectContext:_moc];
            [state setValue:@"foo" forKey:State_Name];
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
            State *state = [NSEntityDescription insertNewObjectForEntityForName:State_EntityName inManagedObjectContext:_moc];
            [state setValue:@"foo" forKey:State_Name];
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
        [fetch setEntity:[[[_psc managedObjectModel] entitiesByName] objectForKey:State_EntityName]];
        
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

@end
