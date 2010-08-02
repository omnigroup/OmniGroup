// Copyright 2002-2007, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h> // for NSRect

/*
 By default, none of the inspectors in the group are expanded. To configure which inspectors you want expanded in your application, you need to register an "Inspector" default that specifies which inspectors are to be expanded. For standard Omni applications, this should go in the application's Info.plist, in OFRegistrations->NSUserDefaults->defaultsDictionary. The value for the Inspector key is a dictionary that contains boolean values for the pertinent inspectors, with the inspector identifiers as the keys. For example, OmniOutliner's entry looks similar to the following, which specifies that the "item style" and "text style" inspectors should be expanded.

        <key>Inspector</key>
        <dict>
            <key>OOItemStyleInspector</key>
            <true/>
            <key>OSStyleInspector</key>
            <true/>
        </dict>
 */

@class NSArray, NSMutableArray, NSWindow, NSScreen, NSMenuItem, NSTimer;
@class OIInspectorController;

@interface OIInspectorGroup : NSObject
{
    NSMutableArray *_inspectors;
    OIInspectorController *_resizingInspector;
    struct {
        unsigned int	ignoreResizing:1;
        unsigned int	isSettingExpansion:1;
        unsigned int	isShowing:1;
        unsigned int	screenChangesEnabled:1;
        unsigned int	hasPositionedWindows:1;
    } _inspectorGroupFlags;
}

// API

+ (void)restoreInspectorGroupsWithInspectors:(NSArray *)inspectors;
+ (void)clearAllGroups;
+ (void)enableWorkspaces;
+ (void)saveExistingGroups;
+ (void)useASeparateMenuForWorkspaces;
+ (BOOL)isUsingASeparateMenuForWorkspaces;

+ (void)setDynamicMenuPlaceholder:(NSMenuItem *)placeholder;
+ (NSArray *)groups;
+ (NSUInteger)groupCount;
+ (NSArray *)visibleGroups;
+ (NSArray *)visibleWindows;
+ (void)forceAllGroupsToCheckScreenGeometry;

- (BOOL)defaultGroupVisibility;

- (void)hideGroup;
- (void)showGroup;
- (void)orderFrontGroup;

- (void)addInspector:(OIInspectorController *)aController;
- (NSRect)inspector:(OIInspectorController *)aController willResizeToFrame:(NSRect)aFrame isSettingExpansion:(BOOL)isSettingExpansion;
- (void)inspectorWillStartResizing:(OIInspectorController *)inspectorController;
- (void)inspectorDidFinishResizing:(OIInspectorController *)inspectorController;

- (void)detachFromGroup:(OIInspectorController *)aController;
- (NSRect)snapToOtherGroupWithFrame:(NSRect)aRect;
- (NSRect)fitFrame:(NSRect)aFrame onScreen:(NSScreen *)aScreen forceVisible:(BOOL)yn;
- (void)setTopLeftPoint:(NSPoint)aPoint;
- (void)windowsDidMoveToFrame:(NSRect)aFrame;

- (BOOL)isHeadOfGroup:(OIInspectorController *)aController;
- (BOOL)isOnlyExpandedMemberOfGroup:(OIInspectorController *)aController;
- (NSArray *)inspectors;
- (BOOL)getGroupFrame:(NSRect *)result;
- (BOOL)isVisible;
- (BOOL)isBelowOverlappingGroup;
- (BOOL)isSettingExpansion;

- (CGFloat)singlePaneExpandedMaxHeight;
- (BOOL)ignoreResizing;
- (BOOL)canBeginResizingOperation;

- (BOOL)screenChangesEnabled;
- (void)setScreenChangesEnabled:(BOOL)yn;
- (void)setFloating:(BOOL)yn;

@end
