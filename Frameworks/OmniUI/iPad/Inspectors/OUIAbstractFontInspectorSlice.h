// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSlice.h>
#import <OmniFoundation/OFExtent.h>

@class OAFontDescriptor;

@interface OUIAbstractFontInspectorSliceFontDisplay : NSObject
@property(nonatomic,copy) NSString *text;
@property(nonatomic,strong) UIFont *font;
@end

@interface OUIAbstractFontInspectorSlice : OUIInspectorSlice

+ (OUIAbstractFontInspectorSliceFontDisplay *)fontNameDisplayForFontDescriptor:(OAFontDescriptor *)fontDescriptor;
+ (OUIAbstractFontInspectorSliceFontDisplay *)fontNameDisplayForFontDescriptors:(NSArray *)fontDescriptors;

@end
