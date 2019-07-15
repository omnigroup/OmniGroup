// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAChangeConfigurationValue.h>

#import <OmniAppKit/NSOutlineView-OAExtensions.h>
#import <OmniAppKit/OAStrings.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniBase/NSError-OBUtilities.h>

RCS_ID("$Id$");

BOOL OAHandleChangeConfigurationValueURL(NSURL *url, NSError * __autoreleasing *outError)
{
    return OFHandleChangeConfigurationValueURL(url, outError, ^(NSString *title, NSString *message, OFConfigurationValueChangeConfirmationCallback callback){
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = title;
        alert.informativeText = message;
        
        [alert addButtonWithTitle:OAOK()];
        [alert addButtonWithTitle:OACancel()];
        
        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            callback(YES, nil);
        } else {
            OBUserCancelledError(outError);
            callback(NO, outError ? *outError : nil);
        }
    });
}

@interface OAChangeConfigurationValuesOutlineView : NSOutlineView
@end

@implementation OAChangeConfigurationValuesOutlineView

#pragma mark - NSResponder

// -[NSOutlineView keyDown:] doesn't handle delete.
- (void)keyDown:(NSEvent *)theEvent;
{
    NSString *characters = [theEvent characters];

    if (([characters length] == 1) && ([characters characterAtIndex:0] == NSDeleteCharacter)) {
        BOOL didClearValue = NO;
        NSArray *selectedItems = [self selectedItems];
        for (OFConfigurationValue *configurationValue in selectedItems) {
            if ([configurationValue hasNonDefaultValue]) {
                didClearValue = YES;
                [configurationValue restoreDefaultValue];
            }
        }
        
        if (!didClearValue) {
            NSBeep();
        }
        return;
    }
    [super keyDown:theEvent];
}

@end

@interface OAChangeConfigurationValueTableCellView : NSTableCellView
@property(nonatomic,strong) IBOutlet NSTextField *valueTextField;
@end

@implementation OAChangeConfigurationValueTableCellView

- (IBAction)incrementValue:(id)sender;
{
    OFConfigurationValue *configurationValue = OB_CHECKED_CAST(OFConfigurationValue, self.objectValue);
    [configurationValue setValueFromDouble:configurationValue.currentValue + 1];
}
- (IBAction)decrementValue:(id)sender;
{
    OFConfigurationValue *configurationValue = OB_CHECKED_CAST(OFConfigurationValue, self.objectValue);
    [configurationValue setValueFromDouble:configurationValue.currentValue - 1];
}
- (IBAction)setValueFromTextField:(id)sender;
{
    OFConfigurationValue *configurationValue = OB_CHECKED_CAST(OFConfigurationValue, self.objectValue);
    [configurationValue setValueFromString:self.valueTextField.stringValue];
}

@end

@interface OAChangeConfigurationValuesWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate>
@end

@implementation OAChangeConfigurationValuesWindowController
{
    IBOutlet NSOutlineView *_outlineView;
    NSArray *_configurationValues;
}

- init;
{
    return [super initWithWindowNibName:@"OAChangeConfigurationValues" owner:self];
}

- (IBAction)copyConfiguration:(id)sender;
{
    NSURL *url = [OFConfigurationValue URLForConfigurationValues:[OFConfigurationValue configurationValues]];
    
    NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSPasteboardNameGeneral];
    [pboard declareTypes:@[NSPasteboardTypeURL] owner:nil];
    [url writeToPasteboard:pboard];
}

- (IBAction)restoreDefaultConfiguration:(id)sender;
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedStringFromTableInBundle(@"Restore default configuration?", @"OmniAppKit", OMNI_BUNDLE, @"Alert title when restoring configuration settings to default state");
    alert.informativeText = NSLocalizedStringFromTableInBundle(@"All configuration values will be restored to their default values.", @"OmniAppKit", OMNI_BUNDLE, @"Alert message when restoring configuration settings to default state");
    
    [alert addButtonWithTitle:OAOK()];
    [alert addButtonWithTitle:OACancel()];
    
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [OFConfigurationValue restoreAllConfigurationValuesToDefaults];
        }
    }];
}

#pragma mark - NSWindowController

static unsigned ConfigurationValueContext;

- (void)windowWillLoad;
{
    [super windowWillLoad];
    
    // Keep ourselves alive while our window is up
    OBStrongRetain(self);
    
    _configurationValues = [[OFConfigurationValue configurationValues] sortedArrayUsingComparator:^NSComparisonResult(OFConfigurationValue *value1, OFConfigurationValue *value2) {
        return [value1.key compare:value2.key];
    }];
    
    for (OFConfigurationValue *configurationValue in _configurationValues) {
        [configurationValue addObserver:self forKeyPath:OFValidateKeyPath(configurationValue, currentValue) options:0 context:&ConfigurationValueContext];
    }
}

- (void)setWindow:(NSWindow *)window;
{
    [super setWindow:window];
    
    if (window == nil) {
        OBAutorelease(self);
    }
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item;
{
    return [_configurationValues count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item;
{
    return _configurationValues[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item;
{
    return (item == nil);
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item;
{
    OFConfigurationValue *configurationValue = OB_CHECKED_CAST(OFConfigurationValue, item);
    
    NSString *identifier = [tableColumn identifier];
    
    OAChangeConfigurationValueTableCellView *cellView = OB_CHECKED_CAST(OAChangeConfigurationValueTableCellView, [outlineView makeViewWithIdentifier:identifier owner:nil]);

    cellView.objectValue = configurationValue;
    cellView.textField.stringValue = configurationValue.key;
    cellView.valueTextField.stringValue = [NSString stringWithFormat:@"%g", configurationValue.currentValue];
    
    BOOL hasNonDefaultValue = configurationValue.currentValue != configurationValue.defaultValue;
    CGFloat fontSize = [NSFont systemFontSizeForControlSize:NSControlSizeRegular];
    NSFont *font;
    if (hasNonDefaultValue)
        font = [NSFont boldSystemFontOfSize:fontSize];
    else
        font = [NSFont systemFontOfSize:fontSize];
    
    cellView.textField.font = font;
    cellView.valueTextField.font = font;

    return cellView;
}

#pragma mark - NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &ConfigurationValueContext) {
        NSUInteger rowIndex = [_configurationValues indexOfObjectIdenticalTo:object];
        if (rowIndex != NSNotFound) {
            // -reloadItem:reloadChildren: doesn't work for some reason, but we have the row index, so we can use the NSTableView method.
            [_outlineView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

@end
