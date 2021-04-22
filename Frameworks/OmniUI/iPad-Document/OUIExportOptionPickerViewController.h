// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class OUIExportOption, OUIExportOptionPickerViewController;

@protocol OUIExportOptionPickerViewControllerDelegate

// If the set of options contains one that requires a purchase, and that specific file type is tapped, this delegate method will still be called.
- (void)exportOptionPicker:(OUIExportOptionPickerViewController *)optionPicker selectedExportOption:(OUIExportOption *)exportOption inRect:(CGRect)optionRect ofView:(UIView *)optionView;

// This will be called when the button at the bottom of the option list is tapped to perform an in-app purchase, instead of a file type. Note that the file type might not be listed in the available options until the purchase is made.
- (void)exportOptionPickerPerformInAppPurchase:(OUIExportOptionPickerViewController *)optionPicker;

@end

@interface OUIExportOptionPickerViewController : UIViewController

- initWithExportOptions:(NSArray <OUIExportOption *> *)exportOptions;
- (id)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (id)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property(nonatomic,nullable,weak) id <OUIExportOptionPickerViewControllerDelegate> delegate;
@property(nonatomic, readonly) NSArray <OUIExportOption *> *exportOptions;

@property(nonatomic) BOOL showInAppPurchaseButton;
@property(nonatomic,copy) NSString *inAppPurchaseButtonTitle;

- (void)setExportDestination:(nullable NSString *)text;

- (void)setInterfaceDisabledWhileExporting:(BOOL)shouldDisable completion:(void (^ _Nullable)(void))completion;

@end

NS_ASSUME_NONNULL_END
