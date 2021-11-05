// Copyright 2005-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIInspector.h>
#import <OmniInspector/OIInspectorTabController.h>

@class NSAttributedString, NSMutableArray; // Foundation
@class NSMatrix; // AppKit
@class OIInspectorController;
@class OIInspectorTabController;
@class OITabMatrix;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet and IBAction

@interface OITabbedInspector : OIInspector <OIConcreteInspector, OIInspectorTabContainer, NSMenuItemValidation>
{
    IBOutlet NSView *contentView;
    IBOutlet OITabMatrix *buttonMatrix;
    NSArray *_enabledTabControllers;
    NSMutableArray *_trackingRectTags;
    BOOL _singleSelection;
    BOOL _shouldInspectNothing;
    BOOL _autoSelection;
    NSString *_currentInspectionIdentifier;
}

@property (nonatomic, readonly) BOOL placesButtonsInTitlebar; // @"placesButtonInTitlebar" in plist
@property (nonatomic,readonly) BOOL placesButtonsInHeaderView; // @"placesButtonsInHeaderView" in plist
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
