// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColor.h>
#import <OmniAppKit/OAAppearance.h>

// OUIDocumentPicker and friends
#define kOUIDocumentPickerItemViewNameLabelFontSize (17.0)
#define kOUIDocumentPickerItemViewNameLabelSmallFontSize (10.0)
#define kOUIDocumentPickerItemViewNameLabelColor ((OAWhiteAlpha){0.0, 1.0})
#define kOUIDocumentPickerItemViewDetailLabelFontSize (12.0)
#define kOUIDocumentPickerItemViewDetailLabelSmallFontSize (8.0)
#define kOUIDocumentPickerItemViewDetailLabelColor ((OAWhiteAlpha){0.4, 1.0})
#define kOUIDocumentPickerItemMetadataViewBackgroundColor ((OAWhiteAlpha){1.0, 0.9})
#define kOUIDocumentPickerItemMetadataViewEditingBackgroundColor ((OAWhiteAlpha){1.0, 1.0})
#define kOUIDocumentPickerItemViewNameToPreviewPadding (7.0)
#define kOUIDocumentPickerItemSmallViewNameToPreviewPadding (5.0)
#define kOUIDocumentPickerItemViewNameToDatePadding (0.0)
#define kOUIDocumentPickerItemViewNameToTopPaddingSmallSize (2.0)
#define kOUIDocumentPickerItemViewNameToTopPaddingLargeSize (4.0)
#define kOUIDocumentPickerItemViewTopToBottomPaddingRatio (1)
#define kOUIDocumentPickerItemViewLabelShadowColor ((OAWhiteAlpha){0.0, 0.66})
#define kOUIDocumentPickerItemViewProgressTintColor ((OALinearRGBA){0.5, 0.5, 0.85, 1.0})

#define kOUIDocumentPickerFolderItemMiniPreviewSize ((CGSize){.width = 60.0f, .height = 60.0f})
#define kOUIDocumentPickerFolderItemMiniPreviewInsets ((UIEdgeInsets){10.0f, 10.0f, 10.0f, 10.0f})
#define kOUIDocumentPickerFolderItemMiniPreviewSpacing (10.0f)

#define kOUIDocumentPickerFolderSmallItemMiniPreviewSize ((CGSize){.width = 42.0f, .height = 42.0f})
#define kOUIDocumentPickerFolderSmallItemMiniPreviewInsets ((UIEdgeInsets){7.0f, 7.0f, 7.0f, 7.0f})
#define kOUIDocumentPickerFolderSmallItemMiniPreviewSpacing (6.0f)

#define kOUIDocumentPickerNavBarItemsAdditionalSpace (20.0f)

#define kOUIDocumentPickerItemVerticalPadding (27.0)
#define kOUIDocumentPickerItemHorizontalPadding (27.0)
#define kOUIDocumentPickerItemSmallVerticalPadding (16.0)
#define kOUIDocumentPickerItemSmallHorizontalPadding (16.0)

#define kOUIDocumentPickerItemNormalSize (220.0)
#define kOUIDocumentPickerItemSmallSize (104.0)

#define kOUIDocumentPickerMetaDataNormalSizeRatio (4.2)  // metadata view will be a bit less than 1/4 the total height of the item view
#define kOUIDocumentPickerMetaDataSmallSizeRatio (3.5)

// Animations
#define kOUIDocumentPickerTemplateAnimationDuration (0.25f)
#define kOUIDocumentPickerTemplateAnimationScaleFactor (1.5f)

#define kOUIDocumentPickerRevertAnimationDuration (0.25f)

// OUIDocumentPreviewView
#define kOUIDocumentPreviewViewNormalShadowBlur (1.25)
#define kOUIDocumentPreviewViewNormalShadowColor ((OAWhiteAlpha){0.0, 0.75})
#define kOUIDocumentPreviewViewNormalBorderColor ((OAWhiteAlpha){0.5, 1.0})
#define kOUIDocumentPreviewViewSelectedBorderThickness (6)
#define kOUIDocumentPreviewViewSmallSelectedBorderThickness (4)
#define kOUIDocumentPreviewViewSelectedBorderColor ((OALinearRGBA){0.227, 0.557, 0.929, 0.850})
#define kOUIDocumentPreviewSelectionTouchBounceScale (0.96)
#define kOUIDocumentPreviewSelectionTouchBounceDuration (0.17)
#define kOUIDocumentPreviewHighlightAlpha (0.5)
#define kOUIDocumentPreviewViewTransitionDuration (0.2f)
