// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

extern NSString *OUIDisplayNameForFont(UIFont *font, BOOL useFamilyName);
extern NSString *OUIDisplayNameForFontFaceName(NSString *displayName, NSString *baseDisplayName);
extern NSString *OUIBaseFontNameForFamilyName(NSString *family);
extern BOOL OUIIsBaseFontNameForFamily(NSString *fontName, NSString *familyName);

typedef struct {
    NSSet *fontDescriptors;
    NSSet *fontSizes;
    CGFloat minFontSize, maxFontSize;
} OUIFontSelection;

@class OUIInspectorSlice;
extern OUIFontSelection OUICollectFontSelection(OUIInspectorSlice *self, NSSet *objects);

