// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSEnumerator.h>
#import <OmniFoundation/OFExtent.h>

extern NSString *OUIDisplayNameForFont(UIFont *font, BOOL useFamilyName);
extern NSString *OUIDisplayNameForFontFaceName(NSString *displayName, NSString *baseDisplayName);
extern NSString *OUIBaseFontNameForFamilyName(NSString *family);
extern BOOL OUIIsBaseFontNameForFamily(NSString *fontName, NSString *familyName);

@interface OUIFontSelection : NSObject
// Uniqued values
@property(nonatomic,copy) NSArray *fontDescriptors;
@property(nonatomic,copy) NSArray *fontSizes;
@property(nonatomic) OFExtent fontSizeExtent;
@end

@class OUIInspectorSlice;
extern OUIFontSelection *OUICollectFontSelection(OUIInspectorSlice *self, id <NSFastEnumeration> objects);

extern BOOL OUIFontIsDynamicType(UIFont *font);
