// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIWorkspace.h>

#import <OmniFoundation/NSArray-OFExtensions.h>

RCS_ID("$Id$")

@interface OIWorkspace ()
@property(readonly) NSMutableDictionary *workspaceDictionary;
@end


NSString * const OIWorkspaceWillChangeNotification = @"OIWorkspaceWillChangeNotification";
NSString * const OIWorkspaceDidChangeNotification = @"OIWorkspaceDidChangeNotification";

static NSString *inspectorDefaultsVersion = nil;
static NSArray *sharedWorkspaces = nil;
static OIWorkspace *sharedWorkspace = nil;

@implementation OIWorkspace

+ (OIWorkspace *)sharedWorkspace;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedWorkspace = [[OIWorkspace alloc] initWithName:nil];
        
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
    });
    
    return sharedWorkspace;
}

+ (void)setInspectorDefaultsVersion:(NSString *)versionString;
{
    inspectorDefaultsVersion = versionString;
}

+ (NSString *)inspectorPreference;
{
    if (inspectorDefaultsVersion)
        return [@"Inspector" stringByAppendingString:inspectorDefaultsVersion];
    else
        return @"Inspector";
}

+ (NSString *)inspectorWorkspacesPreference;
{
    if (inspectorDefaultsVersion)
        return [@"InspectorWorkspaces" stringByAppendingString:inspectorDefaultsVersion];
    else
        return @"InspectorWorkspaces";
}

+ (NSArray *)sharedWorkspaces;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedWorkspaces = [[[NSUserDefaults standardUserDefaults] objectForKey:[[self class] inspectorWorkspacesPreference]] copy];
        if (!sharedWorkspaces)
            sharedWorkspaces = [[NSArray alloc] init];
    });
    
    return sharedWorkspaces;
}

+ (void)updateWorkspaces:(void (^)(NSMutableArray *workspaces))operation;
{
    NSMutableArray *updated = [sharedWorkspaces mutableCopy];
    if (operation)
        operation(updated);
    if (OFNOTEQUAL(sharedWorkspaces, updated)) {
        sharedWorkspaces = [updated copy];
        
        [[NSUserDefaults standardUserDefaults] setObject:sharedWorkspaces forKey:[[self class] inspectorWorkspacesPreference]];
    }
}

+ (void)renameWorkspaceWithName:(NSString *)oldName toName:(NSString *)newName;
{
    NSString *oldDefault = [[self class] userDefaultsKeyWithName:oldName];
    NSString *newDefault = [[self class] userDefaultsKeyWithName:newName];
    
    if (![newDefault isEqualToString:oldDefault]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:[defaults objectForKey:oldDefault] forKey:newDefault];
        [defaults removeObjectForKey:oldDefault];
        
        NSUInteger workspaceIndex = [sharedWorkspaces indexOfObjectIdenticalTo:oldName];
        sharedWorkspaces = [sharedWorkspaces arrayByReplacingObjectAtIndex:workspaceIndex withObject:newName];
        
        [[NSUserDefaults standardUserDefaults] setObject:sharedWorkspaces forKey:[[self class] inspectorWorkspacesPreference]];
    }
}

+ (void)removeWorkspaceWithName:(NSString *)name;
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    [defaults removeObjectForKey:[NSString stringWithFormat:@"%@-%@", [[self class] inspectorWorkspacesPreference], name]];
    sharedWorkspaces = [sharedWorkspaces arrayByRemovingObject:name];
    [defaults setObject:sharedWorkspaces forKey:[[self class] inspectorWorkspacesPreference]];
}

+ (void)moveWorkspacesWithNames:(NSArray *)workspaceNames toIndex:(NSInteger)row;
{
    for (NSString *name in workspaceNames) {
        NSUInteger workspaceIndex = [sharedWorkspaces indexOfObject:name];
        if (workspaceIndex == NSNotFound) {
            OBASSERT_NOT_REACHED("Possible to hit this?");
            continue;
        }
        if (row >= 0 && workspaceIndex < (NSUInteger)row)
            row--;
        sharedWorkspaces = [sharedWorkspaces arrayByRemovingObjectAtIndex:workspaceIndex];
    }
    sharedWorkspaces = [sharedWorkspaces arrayByInsertingObjectsFromArray:workspaceNames atIndex:row];
    [[NSUserDefaults standardUserDefaults] setObject:sharedWorkspaces forKey:[[self class] inspectorWorkspacesPreference]];
}

+ (NSString *)userDefaultsKeyWithName:(NSString *)name;
{
    NSString *userDefaultsKey;
    if ([NSString isEmptyString:name]) {
        userDefaultsKey = [self inspectorPreference];
    } else {
        userDefaultsKey = [NSString stringWithFormat:@"%@-%@", [[self class] inspectorWorkspacesPreference], name];
    }
    
    return userDefaultsKey;
}

- (instancetype)initWithName:(NSString *)name;
{
    if (!(self = [super init]))
        return nil;

    NSString *userDefaultsKey = [[self class] userDefaultsKeyWithName:name];
    
    if (![NSString isEmptyString:userDefaultsKey]) {
        _workspaceDictionary = [[[NSUserDefaults standardUserDefaults] objectForKey:userDefaultsKey] mutableCopy];
    }
    
    if (!_workspaceDictionary) {
        _workspaceDictionary = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

- (id)objectForKey:(id)aKey;
{
    return [_workspaceDictionary objectForKey:aKey];
}

- (void)updateInspectorsWithBlock:(void (^)(NSMutableDictionary *dictionary))block
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceWillChangeNotification object:self];
    
    block(_workspaceDictionary);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceDidChangeNotification object:self];
}

- (void)loadFrom:(NSString *)name;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceWillChangeNotification object:self];

    _workspaceDictionary = [[[NSUserDefaults standardUserDefaults] objectForKey:[[self class] userDefaultsKeyWithName:name]] mutableCopy];

    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceDidChangeNotification object:self];
}

- (void)reset
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceWillChangeNotification object:self];

    _workspaceDictionary = nil;
    [self save];

    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceDidChangeNotification object:self];
}

- (void)save
{
    if (_workspaceDictionary) {
        [[NSUserDefaults standardUserDefaults] setObject:[_workspaceDictionary copy] forKey:[OIWorkspace inspectorPreference]];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[OIWorkspace inspectorPreference]];
        _workspaceDictionary = [[[NSUserDefaults standardUserDefaults] objectForKey:[OIWorkspace inspectorPreference]] mutableCopy];
        if (!_workspaceDictionary)
            _workspaceDictionary = [[NSMutableDictionary alloc] init];
    }
}

- (void)saveAs:(NSString *)workspaceName;
{
    [[NSUserDefaults standardUserDefaults] setObject:[_workspaceDictionary copy] forKey:[[self class] userDefaultsKeyWithName:workspaceName]];
    
    if (![sharedWorkspaces containsObject:workspaceName]) {
        sharedWorkspaces = [sharedWorkspaces arrayByAddingObject:workspaceName];

        [[NSUserDefaults standardUserDefaults] setObject:sharedWorkspaces forKey:[[self class] inspectorWorkspacesPreference]];
    }
}

@end
