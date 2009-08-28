// Copyright 2002-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSWindowController.h>
#import <Availability.h>

#if defined(MAC_OS_X_VERSION_10_6) && (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6)
#import <AppKit/NSToolbar.h>
#endif
@class OAToolbar;
@class NSToolbarItem;
@class NSBundle, NSDictionary;

@protocol OAToolbarHelper
- (NSString *)itemIdentifierExtension;
- (NSString *)templateItemIdentifier;
- (NSArray *)allowedItems;
- (void)finishSetupForItem:(NSToolbarItem *)item;
@end

@interface OAToolbarWindowController : NSWindowController 
#if defined(MAC_OS_X_VERSION_10_6) && (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6)
<NSToolbarDelegate>
#endif
{
    OAToolbar *toolbar;
    BOOL _isCreatingToolbar;
}

+ (void)registerToolbarHelper:(NSObject <OAToolbarHelper> *)helperObject;
+ (NSBundle *)toolbarBundle;
+ (Class)toolbarClass;
+ (Class)toolbarItemClass;

- (OAToolbar *)toolbar;
- (void)createToolbar;
- (BOOL)isCreatingToolbar;
- (NSDictionary *)toolbarInfoForItem:(NSString *)identifier;

// implement in subclasses to control toolbar
- (NSString *)toolbarConfigurationName; // file name to lookup .toolbar plist
- (NSString *)toolbarIdentifier; // identifier used for preferences - defaults to configurationName if unimplemented
- (BOOL)shouldAllowUserToolbarCustomization;
- (BOOL)shouldAutosaveToolbarConfiguration;
- (NSDictionary *)toolbarConfigurationDictionary;

@end
