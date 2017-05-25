// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIFileListViewController.h"

#import <OmniDAV/ODAVFileInfo.h>
#import <OmniUIDocument/OUIDocumentAppController.h>

RCS_ID("$Id$");

@implementation OUIFileListViewController
{
    OUIDocumentExporter *_exporter;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;

    self.shouldShowLastModifiedDate = YES;

    return self;
}

- (void)setFiles:(NSArray *)newFiles;
{
    _files = newFiles;
    
    [(UITableView *)self.view reloadData];
}

// for subclasses
- (NSString *)localizedNameForFileName:(NSString *)fileName;
{
    return fileName;
}

#pragma mark -
#pragma mark Private

- (BOOL)_canOpenFile:(ODAVFileInfo *)fileInfo;
{
    return [[OUIDocumentAppController controller] canViewFileTypeWithIdentifier:[fileInfo UTI]];
}

#pragma mark -
#pragma mark UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    return [_files count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    
    ODAVFileInfo *fileInfo = [_files objectAtIndex:indexPath.row];
    BOOL isDocument = [self _canOpenFile:fileInfo];
    BOOL isFolder = !isDocument && fileInfo.isDirectory; // Things that we can open might be directories, but we won't let the user navigate into them.s
    
    if (isDocument) {
        // Look up localized sample document names and trim path extensions
        NSString *localizedFileName = [self localizedNameForFileName:[[fileInfo name] stringByDeletingPathExtension]];
        if (!localizedFileName)
            localizedFileName = [fileInfo name];
        
        cell.textLabel.text = localizedFileName;
    } else {
        // Leave the folder name exactly the way the user had it.
        cell.textLabel.text = [fileInfo name];
    }
    
    cell.accessoryType = isFolder ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    
    BOOL canOpenFile = (isFolder || isDocument) && [fileInfo exists];
    cell.textLabel.textColor = canOpenFile ? [UIColor blackColor] : [UIColor grayColor];
    
    if (self.shouldShowLastModifiedDate && isDocument) {
        NSDate *lastModifiedDate = [fileInfo lastModifiedDate];
        if (lastModifiedDate) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateStyle:NSDateFormatterMediumStyle];
            [formatter setLocale:[NSLocale currentLocale]];
            cell.detailTextLabel.text = [formatter stringFromDate:lastModifiedDate];
        }
    }
    else {
        cell.detailTextLabel.text = nil;
    }
    
    UIImage *icon = nil;
    if (isDocument) {
        if (_exporter == nil) {
            _exporter = [OUIDocumentExporter exporterForViewController:self];
        }
        
        icon = [_exporter iconForUTI:[fileInfo UTI]];
        // Not so sure about this assert. For example when we're browing through a WebDAV there is no reason to think we will have an icon for every UTI.
        OBASSERT(icon, @"bug:///142999 (iOS-OmniGraffle Engineering: Assertion failed: 'Export to WebDAV' as OmniGraffle: Requires 'icon')");
    }
    if (isFolder) {
        icon = [UIImage imageNamed:@"OUIFolder" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    } else if (!icon) {
        icon = [UIImage imageNamed:@"OUIDocument" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    }
    
    cell.imageView.image = icon;
    
    return cell;
}

#pragma mark - OUIDocumentExporterHost

- (ODSFileItem *)fileItemToExport
{
    return nil;
}

- (UIColor *)tintColorForExportMenu
{
    return self.view.tintColor;
}

#pragma mark - UIViewController

- (BOOL)shouldAutorotate;
{
    return YES;
}

@end
