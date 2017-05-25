// Copyright 2015-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIWorkspace.h>

#import <OmniFoundation/NSArray-OFExtensions.h>

RCS_ID("$Id$")

@interface OIWorkspace ()

@property(retain) NSMutableDictionary *inspectorOrGroupPositionDictionary;
@property(retain) NSMutableDictionary *inspectorGroupOrderDictionary;
@property(retain) NSMutableDictionary *inspectorGroupVisibleDictionary;
@property(retain) NSMutableDictionary *inspectorHeightDictionary;
@property(retain) NSMutableDictionary *inspectorDisclosureDictionary;
@property(retain) NSMutableDictionary *toolPrototypeDictionary;

@property(retain) NSString *workspaceName; // nil if default

- (void)_loadWithDefaultsKey:(NSString *)key;
- (void)_saveToDefaultsKey:(NSString *)defaultsName;

@end


NSString * const OIWorkspaceWillChangeNotification = @"OIWorkspaceWillChangeNotification";
NSString * const OIWorkspaceDidChangeNotification = @"OIWorkspaceDidChangeNotification";

static NSString *inspectorDefaultsVersion = nil;
static NSArray *sharedWorkspaces = nil;
static OIWorkspace *sharedWorkspace = nil;

@implementation OIWorkspace

static NSString *WorkspaceClassName(NSBundle *bundle)
{
    return [[bundle infoDictionary] objectForKey:@"OIWorkspaceClass"];
}

+ (instancetype)sharedWorkspace;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // When running unit tests, the main bundle won't be the test bundle.
        NSString *workspaceClassName = WorkspaceClassName([NSBundle mainBundle]);

        Class workspaceClass;
        if ([NSString isEmptyString:workspaceClassName])
            workspaceClass = self;
        else {
            workspaceClass = NSClassFromString(workspaceClassName);
            if (workspaceClass == Nil) {
                NSLog(@"OIWorkspace: no such class \"%@\"", workspaceClassName);
                workspaceClass = self;
            }
        }

        OIWorkspace *allocatedWorkspace = [workspaceClass alloc]; // Special case; make sure assignment happens before call to -init so that it will actually initialize this instance
        if (sharedWorkspace == nil) {
            sharedWorkspace = allocatedWorkspace;
            OIWorkspace *initializedWorkspace = [allocatedWorkspace initWithName:nil];
            assert(sharedWorkspace == initializedWorkspace);
        }
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

    self.sidebarInspectorConfiguration = nil;
    self.floatingInspectorConfiguration = nil;
    self.inspectorGroupIdentifiers = nil;
    self.configuration = nil;
    self.rulerConfiguration = nil;
    self.floatingStencilConfiguration = nil;

    self.colorPanelFrame = NSZeroRect;
    self.colorPanelVisible = NO;
    self.fontPanelFrame = NSZeroRect;
    self.fontPanelVisible = NO;

    self.inspectorOrGroupPositionDictionary = [NSMutableDictionary dictionary];
    self.inspectorGroupOrderDictionary = [NSMutableDictionary dictionary];
    self.inspectorGroupVisibleDictionary = [NSMutableDictionary dictionary];
    self.inspectorHeightDictionary = [NSMutableDictionary dictionary];
    self.inspectorDisclosureDictionary = [NSMutableDictionary dictionary];
    self.toolPrototypeDictionary = [NSMutableDictionary dictionary];

    self.workspaceName = name;

    NSString *userDefaultsKey = [[self class] userDefaultsKeyWithName:name];

    if ([NSString isEmptyString:userDefaultsKey] == NO) {
        [self _loadWithDefaultsKey:userDefaultsKey];
    }

    return self;
}

- (void)loadFrom:(NSString *)name;
{
    self.workspaceName = name;
    [self _loadWithDefaultsKey:[[self class] userDefaultsKeyWithName:name]];
}

- (void)_loadWithDefaultsKey:(NSString *)defaultsKey;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceWillChangeNotification object:self];

    [self performLoadWithDefaultKey:defaultsKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceDidChangeNotification object:self];
}

- (void)performLoadWithDefaultKey:(NSString *)defaultsKey;
{
    // this is mutable because we need to remove key/value pairs as we match them with their ivars. This is to filter the values whose keys are just the name of the inspector identifier (the disclosure state of any particular inspector), from the rest of the workspace information. Ugh.
    NSMutableDictionary *workspaceDictionary;
    if (defaultsKey) {
    workspaceDictionary = [[[NSUserDefaults standardUserDefaults] objectForKey:defaultsKey] mutableCopy];
    } else {
        workspaceDictionary = [[[NSUserDefaults standardUserDefaults] objectForKey:[OIWorkspace inspectorPreference]] mutableCopy];
    }

    if (workspaceDictionary == nil)
        return;

    self.sidebarInspectorConfiguration = [workspaceDictionary objectForKey:@"_InfoConfiguration"];
    [workspaceDictionary removeObjectForKey:@"_InfoConfiguration"];

    self.floatingInspectorConfiguration = [workspaceDictionary objectForKey:@"_InfoFloatersConfiguration"];
    [workspaceDictionary removeObjectForKey:@"_InfoFloatersConfiguration"];

    self.inspectorGroupIdentifiers = [workspaceDictionary objectForKey:@"_groups"];
    [workspaceDictionary removeObjectForKey:@"_groups"];

    self.configuration = [workspaceDictionary objectForKey:@"_Configurations"];
    [workspaceDictionary removeObjectForKey:@"_Configurations"];

    self.rulerConfiguration = [workspaceDictionary objectForKey:@"_RulerConfiguration"];
    [workspaceDictionary removeObjectForKey:@"_RulerConfiguration"];

    self.floatingStencilConfiguration = [workspaceDictionary objectForKey:@"_floatingStencils"];
    [workspaceDictionary removeObjectForKey:@"_floatingStencils"];

    NSString *colorFrameString = [workspaceDictionary objectForKey:@"_ColorFrame"];
    if (colorFrameString) {
        self.colorPanelFrame = NSRectFromString(colorFrameString);
    } else {
        self.colorPanelFrame = NSZeroRect;
    }
    [workspaceDictionary removeObjectForKey:@"_ColorFrame"];


    NSNumber *colorVisible = [workspaceDictionary objectForKey:@"_ColorVisible"];
    self.colorPanelVisible = colorVisible != nil ? [colorVisible boolValue] : NO;
    [workspaceDictionary removeObjectForKey:@"_ColorVisible"];

    NSString *fontFrameString = [workspaceDictionary objectForKey:@"_FontFrame"];
    if (fontFrameString) {
        self.fontPanelFrame = NSRectFromString(fontFrameString);
    } else {
        self.fontPanelFrame = NSZeroRect;
    }
    [workspaceDictionary removeObjectForKey:@"_FontFrame"];

    NSNumber *fontVisibleObject = [workspaceDictionary objectForKey:@"_FontVisible"];
    self.fontPanelVisible = fontVisibleObject != nil ? [fontVisibleObject boolValue] : NO;
    [workspaceDictionary removeObjectForKey:@"_FontVisible"];

    NSSet *positionKeys = [workspaceDictionary keysOfEntriesPassingTest:^BOOL(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([(NSString *)key hasSuffix:@"-Position"])
            return YES;
        return NO;
    }];

    [workspaceDictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([positionKeys containsObject:key])
            [self.inspectorOrGroupPositionDictionary setObject:obj forKey:key];
    }];

    [workspaceDictionary removeObjectsForKeys:[positionKeys allObjects]];

    NSSet *orderKeys = [workspaceDictionary keysOfEntriesPassingTest:^BOOL(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([(NSString *)key hasSuffix:@"-Order"])
            return YES;
        return NO;
    }];

    [workspaceDictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([orderKeys containsObject:key])
            [self.inspectorGroupOrderDictionary setObject:obj forKey:key];
    }];

    [workspaceDictionary removeObjectsForKeys:[orderKeys allObjects]];

    NSSet *visibleKeys = [workspaceDictionary keysOfEntriesPassingTest:^BOOL(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([(NSString *)key hasSuffix:@"-Visible"])
            return YES;
        return NO;
    }];

    [workspaceDictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([visibleKeys containsObject:key])
            [self.inspectorGroupVisibleDictionary setObject:obj forKey:key];
    }];

    [workspaceDictionary removeObjectsForKeys:[visibleKeys allObjects]];

    NSSet *heightKeys = [workspaceDictionary keysOfEntriesPassingTest:^BOOL(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([(NSString *)key hasSuffix:@"-Height"])
            return YES;
        return NO;
    }];

    [workspaceDictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([heightKeys containsObject:key])
            [self.inspectorHeightDictionary setObject:obj forKey:key];
    }];

    [workspaceDictionary removeObjectsForKeys:[heightKeys allObjects]];

    NSSet *toolPrototypeKeys = [workspaceDictionary keysOfEntriesPassingTest:^BOOL(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([(NSString *)key hasSuffix:@" Prototypes"] && [(NSString *)key hasPrefix:@"Graffle Tool "])
            return YES;
        return NO;
    }];

    [workspaceDictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([toolPrototypeKeys containsObject:key])
            [self.toolPrototypeDictionary setObject:obj forKey:key];
    }];

    [workspaceDictionary removeObjectsForKeys:[toolPrototypeKeys allObjects]];

    self.inspectorDisclosureDictionary = [workspaceDictionary mutableCopy];
}

- (void)reset;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceWillChangeNotification object:self];

    [self performReset];
    [self save];

    [[NSNotificationCenter defaultCenter] postNotificationName:OIWorkspaceDidChangeNotification object:self];
}

- (void)performReset;
{
    self.sidebarInspectorConfiguration = nil;
    self.floatingInspectorConfiguration = nil;
    self.inspectorGroupIdentifiers = nil;
    self.configuration = nil;
    self.rulerConfiguration = nil;
    self.floatingStencilConfiguration = nil;

    self.colorPanelFrame = NSZeroRect;
    self.colorPanelVisible = NO;
    self.fontPanelFrame = NSZeroRect;
    self.fontPanelVisible = NO;

    self.inspectorOrGroupPositionDictionary = [NSMutableDictionary dictionary];
    self.inspectorGroupOrderDictionary = [NSMutableDictionary dictionary];
    self.inspectorGroupVisibleDictionary = [NSMutableDictionary dictionary];
    self.inspectorHeightDictionary = [NSMutableDictionary dictionary];
    self.inspectorDisclosureDictionary = [NSMutableDictionary dictionary];
    self.toolPrototypeDictionary = [NSMutableDictionary dictionary];

    self.workspaceName = nil;
}

// Save is kind of a lousy name. If self has has been loaded this writes it to defaults. If not, or has been reset, this loads the default workspace from user defaults.
- (void)save
{
    if (self.workspaceName != nil) {
        [self _saveToDefaultsKey:[OIWorkspace inspectorPreference]];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[OIWorkspace inspectorPreference]];
        if (self.sidebarInspectorConfiguration != nil) // we have a configuration it's just not a saved workspace
            [self _saveToDefaultsKey:[OIWorkspace inspectorPreference]];
        [self _loadWithDefaultsKey:nil];
    }
}

- (void)saveAs:(NSString *)workspaceName;
{
    self.workspaceName = workspaceName;

    [self _saveToDefaultsKey:[[self class] userDefaultsKeyWithName:workspaceName]];

    if (![sharedWorkspaces containsObject:workspaceName]) {
        sharedWorkspaces = [sharedWorkspaces arrayByAddingObject:workspaceName];

        [[NSUserDefaults standardUserDefaults] setObject:sharedWorkspaces forKey:[[self class] inspectorWorkspacesPreference]];
    }
}

- (void)_saveToDefaultsKey:(NSString *)defaultsName;
{
    [[NSUserDefaults standardUserDefaults] setObject:[self workspaceDictionaryToSave] forKey:defaultsName];
}

- (NSMutableDictionary *)workspaceDictionaryToSave;
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    [dict setObject:self.sidebarInspectorConfiguration forKey:@"_InfoConfiguration"];
    [dict setObject:self.floatingInspectorConfiguration forKey:@"_InfoFloatersConfiguration"];
    [dict setObject:self.inspectorGroupIdentifiers forKey:@"_groups"];
    if (self.configuration == nil) {
        self.configuration = [NSDictionary dictionary];
    }
    [dict setObject:self.configuration forKey:@"_Configurations"];
    [dict setObject:self.rulerConfiguration forKey:@"_RulerConfiguration"];
    [dict setObject:self.floatingStencilConfiguration forKey:@"_floatingStencils"];

    [dict setObject:NSStringFromRect(self.colorPanelFrame) forKey:@"_ColorFrame"];
    [dict setObject:@(self.colorPanelVisible) forKey:@"_ColorVisible"];
    [dict setObject:NSStringFromRect(self.fontPanelFrame) forKey:@"_FontFrame"];
    [dict setObject:@(self.fontPanelVisible) forKey:@"_FontVisible"];

    [dict addEntriesFromDictionary:self.inspectorOrGroupPositionDictionary];
    [dict addEntriesFromDictionary:self.inspectorGroupOrderDictionary];
    [dict addEntriesFromDictionary:self.inspectorGroupVisibleDictionary];
    [dict addEntriesFromDictionary:self.inspectorHeightDictionary];
    [dict addEntriesFromDictionary:self.inspectorDisclosureDictionary];
    [dict addEntriesFromDictionary:self.toolPrototypeDictionary];

    return dict;
}

- (NSPoint)floatingInspectorPositionForIdentifier:(NSString *)identifier;
{
    return NSPointFromString([self.inspectorOrGroupPositionDictionary valueForKey:[NSString stringWithFormat:@"%@-Position", identifier]]);
}

- (void)setFloatingInspectorPosition:(NSPoint)position forIdentifier:(NSString *)identifier;
{
    [self.inspectorOrGroupPositionDictionary setObject:NSStringFromPoint(position) forKey:[NSString stringWithFormat:@"%@-Position", identifier]];
}

- (NSArray *)inspectorGroupOrderForIdentifier:(NSString *)identifier;
{
    return [self.inspectorGroupOrderDictionary valueForKey:[NSString stringWithFormat:@"%@-Order", identifier]];
}

- (void)setInspectorGroupOrder:(NSArray *)order forIdentifier:(NSString *)identifier;
{
    [self.inspectorGroupOrderDictionary setObject:order forKey:[NSString stringWithFormat:@"%@-Order", identifier]];
}

- (NSPoint)inspectorGroupPositionForIdentifier:(NSString *)identifier;
{
    return NSPointFromString([self.inspectorOrGroupPositionDictionary valueForKey:[NSString stringWithFormat:@"%@-Position", identifier]]);
}

- (void)setInspectorGroupPosition:(NSPoint)position forIdentifier:(NSString *)identifier;
{
    [self.inspectorOrGroupPositionDictionary setObject:NSStringFromPoint(position) forKey:[NSString stringWithFormat:@"%@-Position", identifier]];
}

- (BOOL)inspectorGroupVisibleForIdentifier:(NSString *)identifier;
{
    return [[self.inspectorGroupVisibleDictionary objectForKey:[NSString stringWithFormat:@"%@-Visible", identifier]] boolValue];
}

- (void)setInspectorGroupVisible:(BOOL)yn forIdentifier:(NSString *)identifier;
{
    [self.inspectorGroupVisibleDictionary setObject:[NSNumber numberWithBool:yn] forKey:[NSString stringWithFormat:@"%@-Visible", identifier]];
}

- (BOOL)inspectorIsDisclosedForIdentifier:(NSString *)identifier;
{
    return [[self.inspectorDisclosureDictionary objectForKey:identifier] boolValue];
}

- (void)setInspectorIsDisclosed:(BOOL)yn forIdentifier:(NSString *)identifier;
{
    [self.inspectorDisclosureDictionary setObject:[NSNumber numberWithBool:yn] forKey:identifier];
}

- (CGFloat)heightforInspectorIdentifier:(NSString *)identifier;
{
    return [[self.inspectorHeightDictionary objectForKey:[NSString stringWithFormat:@"%@-Height", identifier]] cgFloatValue];
}

- (void)setHeight:(CGFloat)height forInspectorIdentifier:(NSString *)identifier;
{
    [self.inspectorHeightDictionary setObject:[NSNumber numberWithCGFloat:height] forKey:[NSString stringWithFormat:@"%@-Height", identifier]];
}

- (NSArray *)toolPrototypesForIdentifier:(NSString *)identifier;
{
    return [self.toolPrototypeDictionary objectForKey:[NSString stringWithFormat:@"Graffle Tool %@ Prototypes", identifier]];
}

- (void)setToolPrototypes:(NSArray *)prototypes forIdentifier:(NSString *)identifier;
{
    [self.toolPrototypeDictionary setObject:prototypes forKey:[NSString stringWithFormat:@"Graffle Tool %@ Prototypes", identifier]];
}

@end
