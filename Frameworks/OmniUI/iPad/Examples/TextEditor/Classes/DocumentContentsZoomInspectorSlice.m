// Copyright 2010-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "DocumentContentsZoomInspectorSlice.h"

#import "TextDocument.h"
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniUI/OUIInspectorTextWell.h>
#import <OmniUI/OUIInspectorStepperButton.h>
#import <OmniUI/OUIInspector.h>

RCS_ID("$Id$");

@interface DocumentContentsZoomInspectorSlice ()
@property(nonatomic,retain) NSNumberFormatter *zoomFormatter;
@end

@implementation DocumentContentsZoomInspectorSlice

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    self.title = NSLocalizedStringFromTableInBundle(@"View", @"Inspectors", OMNI_BUNDLE, @"document contents inspector segment title");
    
    return self;
}

#pragma mark - OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object isKindOfClass:[TextDocument class]];
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    TextDocument *document = [self.appropriateObjectsForInspection first:^(id obj) {
        return [obj isKindOfClass:[TextDocument class]];
    }];
    OBASSERT(document);
    
    CGFloat scale = document ? document.scale : 1;
    
    _zoomTextWell.text = [_zoomFormatter stringForObjectValue:[NSNumber numberWithFloat:scale]];
}

#pragma mark - UIViewController

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    _zoomDecreaseStepperButton.title = @"A";
    _zoomDecreaseStepperButton.titleFont = [UIFont boldSystemFontOfSize:14];
    _zoomDecreaseStepperButton.titleColor = [UIColor whiteColor];
    _zoomDecreaseStepperButton.flipped = YES;
    
    _zoomIncreaseStepperButton.title = @"A";
    _zoomIncreaseStepperButton.titleFont = [UIFont boldSystemFontOfSize:32];
    _zoomIncreaseStepperButton.titleColor = [UIColor whiteColor];
    
    _zoomFormatter = [[NSNumberFormatter alloc] init];
    _zoomFormatter.numberStyle = NSNumberFormatterPercentStyle;
    _zoomFormatter.locale = [NSLocale currentLocale];
    
    CGFloat fontSize = [OUIInspectorTextWell fontSize];
    _zoomTextWell.font = [UIFont boldSystemFontOfSize:fontSize];
    _zoomTextWell.label = NSLocalizedStringFromTableInBundle(@"Zoom: %@", @"Inspectors", OMNI_BUNDLE, @"zoom label format string in percent");
    _zoomTextWell.labelFont = [UIFont systemFontOfSize:fontSize];
    _zoomTextWell.editable = YES;
    [_zoomTextWell addTarget:self action:@selector(zoomChanged:) forControlEvents:UIControlEventValueChanged];
    
    [_zoomTextWell setKeyboardType:UIKeyboardTypeNumberPad];
}

#pragma mark - Actions

static void _setZoom(DocumentContentsZoomInspectorSlice *self, CGFloat scale)
{
    [self.inspector willBeginChangingInspectedObjects];
    {
        TextDocument *document = [self.appropriateObjectsForInspection first:^(id obj) {
            return [obj isKindOfClass:[TextDocument class]];
        }];
        OBASSERT(document);
        
        scale = MAX(scale, 0.25);
        scale = MIN(scale, 3);
        
        document.scale = scale;
    }
    [self.inspector didEndChangingInspectedObjects];
}

static void _adjustZoom(DocumentContentsZoomInspectorSlice *self, CGFloat direction)
{
    // Make sure that we are not editing the zoomTextWell
    [[self view] endEditing:NO];

    TextDocument *document = [self.appropriateObjectsForInspection first:^(id obj) {
        return [obj isKindOfClass:[TextDocument class]];
    }];
    OBASSERT(document);
    
    CGFloat scale = document ? document.scale : 1;
    
    scale = (round(scale * 10 + direction)) / 10;
    
    _setZoom(self, scale);
}

- (IBAction)zoomDecrease:(id)sender;
{
    _adjustZoom(self, -1);
}

- (IBAction)zoomIncrease:(id)sender;
{
    _adjustZoom(self, 1);
}

- (void)zoomChanged:(id)sender;
{
    NSString *zoomString = _zoomTextWell.text;
    
    // NSNumberFormatter can't parse its own output on iOS. Works OK on the OS X 10.6 version of Foundation, though.
#if 0
    // The formatters are useless for parsing the value back. It won't even parse "10" or "10%".
    NSNumber *zoomNumber = nil;
    NSString *errorDescription = nil;
    if (![_zoomFormatter getObjectValue:&zoomNumber forString:zoomString errorDescription:&errorDescription]) {
        NSLog(@"Unable to parse zoom well text '%@': %@", zoomString, errorDescription);
        [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
    } else if (zoomNumber) {
        _setZoom(self, [zoomNumber floatValue]);
    }
#else
    zoomString = [zoomString stringByTrimmingCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]]; // In case the local puts the percent stuff before the number bits.
    CGFloat zoom = [zoomString floatValue];
    
    if (zoom <= 0) {
        NSLog(@"Unable to parse zoom well text '%@'", zoomString);
        [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
    } else
        _setZoom(self, zoom / 100.0);
#endif
}

@end
