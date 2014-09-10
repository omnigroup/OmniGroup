// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
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
#import <OmniUIDocument/OUIDocumentPickerDelegate.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerItemView.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>
#import <OmniUI/OUIEmptyOverlayView.h>

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
    OUIEmptyOverlayView *_templatePickerEmptyOverlayView = [OUIEmptyOverlayView overlayViewWithMessage:nil buttonTitle:buttonTitle action:^{
        [weakSelf newDocumentWithTemplateFileItem:nil];
    }];
    
    return _templatePickerEmptyOverlayView;
}

+ (OUIDocumentPickerFilter *)selectedFilterForPicker:(OUIDocumentPicker *)picker;
{
    id <OUIDocumentPickerDelegate> delegate = picker.delegate;
    if ([delegate respondsToSelector:@selector(documentPickerTemplateDocumentFilter:)]) {
        OUIDocumentPickerFilter *templateFilter = [delegate documentPickerTemplateDocumentFilter:picker];
        NSPredicate *predicate = templateFilter.predicate;
        templateFilter.predicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            if (![predicate evaluateWithObject:evaluatedObject])
                return NO;
            // filter out fileItems in the trash.
            ODSItem *item = evaluatedObject;
            if (item.scope.isTrash)
                return NO;
            else
                return YES;
        }];

        return templateFilter;
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

- (void)_updateToolbarItemsAnimated:(BOOL)animated;
{
    OBPRECONDITION(self.documentStore);

    UINavigationItem *navigationItem = self.navigationItem;

    navigationItem.title = NSLocalizedStringFromTableInBundle(@"Choose a Template", @"OmniUIDocument", OMNI_BUNDLE, @"toolbar prompt when choosing a template");
    [navigationItem setLeftBarButtonItem:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancelChooseTemplate:)] animated:animated];
    [navigationItem setRightBarButtonItem:nil animated:animated];
}

- (NSString *)nameLabelForItem:(ODSItem *)item;
{
    return @""; // every file item we display should be a template.  No need to provide a label for the file name.
}

- (void)ensureSelectedFilterMatchesFileItem:(ODSFileItem *)fileItem;
{
    // nothing to do here.
}

#pragma mark -
#pragma mark OUIDocumentPickerScrollView delegate

- (void)documentPickerScrollView:(OUIDocumentPickerScrollView *)scrollView itemViewTapped:(OUIDocumentPickerItemView *)itemView;
{
    if ([itemView isKindOfClass:[OUIDocumentPickerFileItemView class]]) {
        ODSFileItem *fileItem = (ODSFileItem *)itemView.item;
        OBASSERT([fileItem isKindOfClass:[ODSFileItem class]]);

        if (fileItem.isDownloaded == NO) {
            NSError *error = nil;
            if (![fileItem requestDownload:&error]) {
                OUI_PRESENT_ERROR(error);
            }
            return;
        }

        [self _beginIgnoringDocumentsDirectoryUpdates]; // prevent the possibility of the newly created document showing up in the template chooser.  This will only happen if you are creating a new template.
        [self newDocumentWithTemplateFileItem:fileItem documentType:self.type];
        // do not call _endIgnoringDocumentsDirectoryUpdates.  Otherwise we will get updates before we animate away opening the document.  We will not be returning to this view controller so this should not be an issue.
    }
}

@end
