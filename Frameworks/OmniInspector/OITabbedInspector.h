// Copyright 2005-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OIInspector.h"

@class NSAttributedString, NSMutableArray; // Foundation
@class NSMatrix; // AppKit
@class OIInspectorController;
@class OITabMatrix;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet and IBAction

@interface OITabbedInspector : OIInspector <OIConcreteInspector> 
{
    IBOutlet NSView *inspectionView;
    IBOutlet NSView *contentView;
    IBOutlet OITabMatrix *buttonMatrix;
    NSArray *_tabControllers;
    NSMutableArray *_trackingRectTags;
    OIInspectorController *_nonretained_inspectorController;
    BOOL _singleSelection;
    BOOL _shouldInspectNothing;
    BOOL _autoSelection;
}

// API
- (NSAttributedString *)windowTitle;
- (void)loadConfiguration:(NSDictionary *)dict;
- (NSDictionary *)configuration;

- (void)registerInspectorDictionary:(NSDictionary *)tabPlist bundle:(NSBundle *)sourceBundle;

- (NSArray *)tabIdentifiers;
- (NSArray *)selectedTabIdentifiers;
- (NSArray *)pinnedTabIdentifiers;
- (void)setSelectedTabIdentifiers:(NSArray *)selectedIdentifiers pinnedTabIdentifiers:(NSArray *)pinnedIdentifiers;

- (void)updateDimmedForTabWithIdentifier:(NSString *)tabIdentifier;

- (OIInspector *)inspectorWithIdentifier:(NSString *)tabIdentifier;

// Actions
- (IBAction)selectInspector:(id)sender;
- (IBAction)switchToInspector:(id)sender;

@end
