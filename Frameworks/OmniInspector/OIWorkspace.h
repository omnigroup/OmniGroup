// Copyright 2002-2017 Omni Development, Inc. All rights reserved.
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

@property(retain) NSDictionary *sidebarInspectorConfiguration;
@property(retain) NSArray *floatingInspectorConfiguration;
@property(retain) NSArray *inspectorGroupIdentifiers;
@property(retain) NSDictionary *configuration;
@property(retain) NSDictionary *rulerConfiguration;
@property(retain) NSArray *floatingStencilConfiguration;

@property NSRect colorPanelFrame;
@property BOOL colorPanelVisible;
@property NSRect fontPanelFrame;
@property BOOL fontPanelVisible;

- (NSPoint)floatingInspectorPositionForIdentifier:(NSString *)identifier;
- (void)setFloatingInspectorPosition:(NSPoint)position forIdentifier:(NSString *)identifier;
- (NSArray *)inspectorGroupOrderForIdentifier:(NSString *)identifier;
- (void)setInspectorGroupOrder:(NSArray *)order forIdentifier:(NSString *)identifier;
- (NSPoint)inspectorGroupPositionForIdentifier:(NSString *)identifier;
- (void)setInspectorGroupPosition:(NSPoint)position forIdentifier:(NSString *)identifier;
- (BOOL)inspectorGroupVisibleForIdentifier:(NSString *)identifier;
- (void)setInspectorGroupVisible:(BOOL)yn forIdentifier:(NSString *)identifier;
- (BOOL)inspectorIsDisclosedForIdentifier:(NSString *)identifier;
- (void)setInspectorIsDisclosed:(BOOL)yn forIdentifier:(NSString *)identifier;
- (CGFloat)heightforInspectorIdentifier:(NSString *)identifier;
- (void)setHeight:(CGFloat)height forInspectorIdentifier:(NSString *)identifier;

- (NSArray *)toolPrototypesForIdentifier:(NSString *)identifier;
- (void)setToolPrototypes:(NSArray *)prototypes forIdentifier:(NSString *)identifier;

@end
