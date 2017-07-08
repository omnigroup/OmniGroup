// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentCreationTemplatePickerViewController.h>

#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFilter.h>
#import <OmniFoundation/OFEnumNameTable.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIEmptyOverlayView.h>
#import <OmniUIDocument/OUIDocumentPickerDelegate.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerItemView.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>
#import <OmniUIDocument/OUIDocumentAppController.h>

RCS_ID("$Id$");

@interface OUIDocumentPickerViewController (/** private mehtods */)
- (void)_beginIgnoringDocumentsDirectoryUpdates;
- (void)_endIgnoringDocumentsDirectoryUpdates;
@end

@interface OUIDocumentCreationTemplatePickerViewController ()
@end

@implementation OUIDocumentCreationTemplatePickerViewController

- (instancetype)initWithDocumentPicker:(OUIDocumentPicker *)picker folderItem:(ODSFolderItem *)folderItem documentType:(ODSDocumentType)type;
{
    if (!(self = [super initWithDocumentPicker:picker folderItem:folderItem]))
        return nil;

    _type = type;

    return self;
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:YES];
    self.displayedTitleString = NSLocalizedStringFromTableInBundle(@"Choose a Template", @"OmniUIDocument", OMNI_BUNDLE, @"toolbar prompt when choosing a template");
    [self scrollToTopAnimated:YES];
}

- (void)_cancelChooseTemplate:(id)sender;
{
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark -
#pragma mark OUIDocumentPickerViewController subclass

- (ODSFilter *)newDocumentStoreFilter;
{
    return [[ODSFilter alloc] initWithStore:self.documentStore];
}

- (NSArray *)availableFilters;
{
    return nil;
}

- (OUIEmptyOverlayView *)newEmptyOverlayView;
{
    NSString *buttonTitle = NSLocalizedStringFromTableInBundle(@"Tap here to add a document without a template.", @"OmniUIDocument", OMNI_BUNDLE, @"empty template picker button text");
    
    __weak OUIDocumentPickerViewController *weakSelf = self;
    OUIEmptyOverlayView *_templatePickerEmptyOverlayView = [OUIEmptyOverlayView overlayViewWithMessage:nil buttonTitle:buttonTitle customFontColor:[[OUIDocumentAppController controller] emptyOverlayViewTextColor] action:^{
        [weakSelf newDocumentWithTemplateFileItem:nil];
    }];
    
    return _templatePickerEmptyOverlayView;
}

+ (OUIDocumentPickerFilter *)selectedFilterForPicker:(OUIDocumentPicker *)picker;
{
    id <OUIDocumentPickerDelegate> delegate = picker.delegate;
    if ([delegate respondsToSelector:@selector(documentPickerTemplateDocumentFilter:)]) {
        OUIDocumentPickerFilter *templateFilter = [delegate documentPickerTemplateDocumentFilter:picker];

        // Return a new filter with an extra not-in-trash check in the predicate. The new document template picker should never show any of the strings, but we'll keep the other properties too.
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            if (![templateFilter.predicate evaluateWithObject:evaluatedObject])
                return NO;
            // filter out fileItems in the trash.
            ODSItem *item = evaluatedObject;
            if (item.scope.isTrash)
                return NO;
            else
                return YES;
        }];

        return [[OUIDocumentPickerFilter alloc] initWithIdentifier:templateFilter.identifier imageName:templateFilter.identifier predicate:predicate localizedFilterChooserButtonLabel:templateFilter.localizedFilterChooserButtonLabel localizedFilterChooserShortButtonLabel:templateFilter.localizedFilterChooserShortButtonLabel localizedMatchingObjectsDescription:templateFilter.localizedMatchingObjectsDescription];
    }
    return nil;
}

+ (NSArray *)sortDescriptors;
{
    static NSArray *descriptors = nil;
    if (!descriptors) {
        NSSortDescriptor *scopeSort = [[NSSortDescriptor alloc] initWithKey:ODSItemScopeBinding ascending:NO comparator:^NSComparisonResult(id obj1, id obj2) {
            if (([(ODSScope *)obj1 isTemplate] && [(ODSScope *)obj2 isTemplate]) || (![(ODSScope *)obj1 isTemplate] && ![(ODSScope *)obj2 isTemplate]))
                return NSOrderedSame;
            if ([(ODSScope *)obj1 isTemplate])
                return NSOrderedDescending;
            return NSOrderedAscending;
        }];
        NSSortDescriptor *nameSort = [[NSSortDescriptor alloc] initWithKey:ODSItemNameBinding ascending:YES selector:@selector(localizedStandardCompare:)];
        descriptors = [[NSArray alloc] initWithObjects:scopeSort, nameSort, nil];
    }
    
    return descriptors;
}

- (BOOL)supportsUpdatingSorting;
{
    return NO;
}

//- (void)_updateToolbarItems Animated:(BOOL)animated;
- (void)_updateToolbarItemsForTraitCollection:(UITraitCollection *)traitCollection animated:(BOOL)animated {
    OBPRECONDITION(self.documentStore);

    UINavigationItem *navigationItem = self.navigationItem;

    [navigationItem setLeftBarButtonItem:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancelChooseTemplate:)] animated:animated];
    [navigationItem setRightBarButtonItem:nil animated:animated];
}

- (NSString *)nameLabelForItem:(ODSItem *)item;
{
    return @""; // every file item we display should be a template.  No need to provide a label for the file name.
}

- (void)ensureSelectedFilterMatchesFileItem:(ODSFileItem *)fileItem;
{
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:NO];
        OUIDocumentPickerViewController *scopeViewController = OB_CHECKED_CAST(OUIDocumentPickerViewController, self.navigationController.topViewController);
        [scopeViewController ensureSelectedFilterMatchesFileItem:fileItem];
    }
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    if (action == @selector(newDocument:)) {
        return NO;
    }

    return [super canPerformAction:action withSender:sender];
}

#pragma mark -
#pragma mark OUIDocumentPickerScrollView delegate

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewTapped:(OUIDocumentPickerItemView *)itemView;
{
    if ([itemView isKindOfClass:[OUIDocumentPickerFileItemView class]]) {
        ODSFileItem *fileItem = (ODSFileItem *)itemView.item;
        OBASSERT([fileItem isKindOfClass:[ODSFileItem class]]);

        if (fileItem.isDownloaded == NO) {
            __autoreleasing NSError *error = nil;
            if (![fileItem requestDownload:&error]) {
                OUI_PRESENT_ERROR_FROM(error, self);
            }
            return;
        }

        [self _beginIgnoringDocumentsDirectoryUpdates]; // prevent the possibility of the newly created document showing up in the template chooser.  This will only happen if you are creating a new template.
        [self newDocumentWithTemplateFileItem:fileItem documentType:self.type completion:^{
            [self _endIgnoringDocumentsDirectoryUpdates];
        }];
    }
}

- (BOOL)documentPickerScrollViewShouldMultiselect:(OUIDocumentPickerScrollView *)scrollView
{
    return NO;
}

@end
