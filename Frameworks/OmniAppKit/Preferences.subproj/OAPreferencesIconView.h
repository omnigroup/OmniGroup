// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSView.h>

@class NSTextFieldCell;
@class OAPreferenceClientRecord, OAPreferenceController;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet

@interface OAPreferencesIconView : NSView
{
    IBOutlet OAPreferenceController *preferenceController;

    NSUInteger pressedIconIndex;
    OAPreferenceClientRecord *selectedClientRecord;
    
    NSArray *preferenceClientRecords;
    NSTextFieldCell *preferenceTitleCell;
}

// API
- (void)setPreferenceController:(OAPreferenceController *)newPreferenceController;
- (void)setPreferenceClientRecords:(NSArray *)newPreferenceClientRecords;
- (NSArray *)preferenceClientRecords;

- (void)setSelectedClientRecord:(OAPreferenceClientRecord *)newSelectedClientRecord;

@end

@interface OAPreferencesIconView (Subclasses)
- (NSUInteger)_iconsWide;
- (NSUInteger)_numberOfIcons;
- (BOOL)_isIconSelectedAtIndex:(NSUInteger)index;
- (BOOL)_column:(NSUInteger *)column andRow:(NSUInteger *)row forIndex:(NSUInteger)index;
- (NSRect)_boundsForIndex:(NSUInteger)index;
- (BOOL)_iconImage:(NSImage **)image andName:(NSString **)name andIdentifier:(NSString **)identifier forIndex:(NSUInteger)index;
- (void)_drawIconAtIndex:(NSUInteger)index drawRect:(NSRect)drawRect;
- (void)_drawBackgroundForRect:(NSRect)rect;
- (void)_sizeToFit;
@end
