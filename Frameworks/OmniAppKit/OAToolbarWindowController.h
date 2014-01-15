// Copyright 2002-2007, 2010, 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSWindowController.h>
#import <OmniAppKit/OAToolbar.h>

@class OAToolbar;
@class NSToolbarItem;
@class NSBundle, NSDictionary;

@protocol OAToolbarHelper
- (NSString *)itemIdentifierExtension;
- (NSString *)templateItemIdentifier;
- (NSArray *)allowedItems;
- (void)finishSetupForToolbarItem:(NSToolbarItem *)item toolbar:(NSToolbar *)toolbar willBeInsertedIntoToolbar:(BOOL)willInsert;
@end

@interface OAToolbarWindowController : NSWindowController <OAToolbarDelegate>
{
@private
    OAToolbar *_toolbar;
    BOOL _isCreatingToolbar;
}

+ (void)registerToolbarHelper:(NSObject <OAToolbarHelper> *)helperObject;
+ (NSBundle *)toolbarBundle;
+ (Class)toolbarClass;
+ (Class)toolbarItemClass;

// DTS workaround for <bug:///83131> (r.12466034: Scroll view gets spurious NSZeroSize, causing constraint violations on 10.7)
// Return YES from this method (the default) if the window controller should call -updateConstraintsIfNeeded on the window before installing the toolbar to avoid constraint violations.
+ (BOOL)shouldUpdateConstraintsBeforeInstallingToolbar;

- (OAToolbar *)toolbar;
- (void)createToolbar;
- (BOOL)isCreatingToolbar;
- (NSDictionary *)toolbarInfoForItem:(NSString *)identifier;
- (NSDictionary *)localizedToolbarInfoForItem:(NSString *)identifier;

// implement in subclasses to control toolbar
- (NSString *)toolbarConfigurationName; // file name to lookup .toolbar plist
- (NSString *)toolbarIdentifier; // identifier used for preferences - defaults to configurationName if unimplemented
- (BOOL)shouldAllowUserToolbarCustomization;
- (BOOL)shouldAutosaveToolbarConfiguration;
- (NSDictionary *)toolbarConfigurationDictionary;

@end
