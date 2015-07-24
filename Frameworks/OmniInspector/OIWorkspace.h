// Copyright 2002-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

extern NSString * const OIWorkspaceWillChangeNotification;
extern NSString * const OIWorkspaceDidChangeNotification;

@interface OIWorkspace: NSObject

// API
+ (NSString *)inspectorWorkspacesPreference;

+ (OIWorkspace *)sharedWorkspace;

+ (void)setInspectorDefaultsVersion:(NSString *)versionString;

+ (NSArray *)sharedWorkspaces;

+ (void)updateWorkspaces:(void (^)(NSMutableArray *workspaces))operation;

// 
+ (void)renameWorkspaceWithName:(NSString *)oldName toName:(NSString *)newName;
+ (void)removeWorkspaceWithName:(NSString *)name;
+ (void)moveWorkspacesWithNames:(NSArray *)workspaceNames toIndex:(NSInteger)row;
+ (NSString *)userDefaultsKeyWithName:(NSString *)name;

- (void)loadFrom:(NSString *)name;
- (void)reset;

// Save is kind of a lousy name. If self has has been loaded this writes it to defaults. If not, or has been reset, this loads the default workspace from user defaults.
- (void)save;
- (void)saveAs:(NSString *)workspaceName;

- (id)objectForKey:(id)aKey;
- (void)updateInspectorsWithBlock:(void (^)(NSMutableDictionary *dictionary))block;

@end
