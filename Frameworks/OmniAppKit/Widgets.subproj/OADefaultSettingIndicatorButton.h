// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSButton.h>

#import <AppKit/NSNibDeclarations.h> // For IBAction, IBOutlet

NS_ASSUME_NONNULL_BEGIN

@interface OADefaultSettingIndicatorButton : NSButton

// Actions
- (IBAction)resetDefaultValue:(id)sender;

// API
+ (OADefaultSettingIndicatorButton *)defaultSettingIndicatorWithIdentifier:(id <NSCopying>)settingIdentifier forView:(NSView *)view delegate:(id)delegate;

- (id)delegate;
- (void)setDelegate:(id)newDelegate;

// Make sure no one calls this one, which is now provided by NSUserInterfaceItemIdentification
@property (nullable, copy) NSString *identifier NS_UNAVAILABLE;

@property(nonatomic,copy) id <NSCopying> settingIdentifier;

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
- (nullable id)defaultObjectValueForSettingIndicatorButton:(OADefaultSettingIndicatorButton *)indicatorButton;
- (nullable id)objectValueForSettingIndicatorButton:(OADefaultSettingIndicatorButton *)indicatorButton;
- (void)restoreDefaultObjectValueForSettingIndicatorButton:(OADefaultSettingIndicatorButton *)indicatorButton;
- (nullable NSString *)toolTipForSettingIndicatorButton:(OADefaultSettingIndicatorButton *)indicatorButton;
@end

NS_ASSUME_NONNULL_END

