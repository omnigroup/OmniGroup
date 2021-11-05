// Copyright 2015-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@import Foundation;
#import <OmniInspector/OIInspector.h>
#import <OmniInspector/OIInspectorTabController.h>

@class OIInspectorTabController;
@class OITabMatrix;

@interface OIScrollingTabbedInspector : OIInspector <OIConcreteInspector, OIInspectorTabContainer, NSMenuItemValidation>

@property (nonatomic, readonly) BOOL placesButtonsInTitlebar; // @"placesButtonInTitlebar" in plist
@property (nonatomic, readonly) BOOL placesButtonsInHeaderView; // @"placesButtonsInHeaderView" in plist
@property (nonatomic, readonly) OITabMatrix *buttonMatrix;

// API
- (NSAttributedString *)windowTitle;
- (void)loadConfiguration:(NSDictionary *)dict;
- (NSDictionary *)configuration;

- (void)registerInspectorDictionary:(NSDictionary *)tabPlist inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(NSBundle *)sourceBundle;

- (NSArray *)tabIdentifiers;
- (NSArray *)selectedTabIdentifiers;
- (NSArray *)pinnedTabIdentifiers;
- (void)setSelectedTabIdentifiers:(NSArray *)selectedIdentifiers pinnedTabIdentifiers:(NSArray *)pinnedIdentifiers;

- (NSArray *)allTabIdentifiers; // this includes disabled tabs as well.
- (void)setEnabledTabIdentifiers:(NSArray *)tabIdentifiers;

- (OIInspectorTabController *)tabWithIdentifier:(NSString *)identifier;
- (OIInspector <OIConcreteInspector> *)inspectorWithIdentifier:(NSString *)tabIdentifier;
- (void)switchToInspectorWithIdentifier:(NSString *)tabIdentifier;

// Actions
- (IBAction)selectInspector:(id)sender;

@end
