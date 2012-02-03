// Copyright 2003-2005, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSButton.h>

#import <AppKit/NSNibDeclarations.h> // For IBAction, IBOutlet

@interface OADefaultSettingIndicatorButton : NSButton
{
    IBOutlet NSView *snuggleUpToRightSideOfView;
    IBOutlet id delegate;
    
    id identifier;
    
    struct {
        unsigned int displaysEvenInDefaultState:1;
    } _flags;
}

// Actions
- (IBAction)resetDefaultValue:(id)sender;

// API
+ (OADefaultSettingIndicatorButton *)defaultSettingIndicatorWithIdentifier:(id)identifier forView:(NSView *)view delegate:(id)delegate;

- (id)delegate;
- (void)setDelegate:(id)newDelegate;

- (id)identifier;
- (void)setIdentifier:(id)newIdentifier;

- (void)validate;

- (void)setDisplaysEvenInDefaultState:(BOOL)displays;
- (BOOL)displaysEvenInDefaultState;

- (void)setSnuggleUpToRightSideOfView:(NSView *)view;
- (NSView *)snuggleUpToRightSideOfView;
- (void)repositionWithRespectToSnuggleView;
- (void)repositionWithRespectToSnuggleViewAllowingResize:(BOOL)allowResize;

@end

@interface NSObject (OADefaultSettingIndicatorButtonDelegate)
- (NSInteger)stateForSettingIndicatorButton:(OADefaultSettingIndicatorButton *)indicatorButton;
- (id)defaultObjectValueForSettingIndicatorButton:(OADefaultSettingIndicatorButton *)indicatorButton;
- (id)objectValueForSettingIndicatorButton:(OADefaultSettingIndicatorButton *)indicatorButton;
- (void)restoreDefaultObjectValueForSettingIndicatorButton:(OADefaultSettingIndicatorButton *)indicatorButton;
- (NSString *)toolTipForSettingIndicatorButton:(OADefaultSettingIndicatorButton *)indicatorButton;
@end
