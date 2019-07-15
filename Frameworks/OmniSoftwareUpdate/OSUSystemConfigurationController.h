// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSWindowController.h>

typedef void(^OSUHTMLAppendTextBlock)(NSString *text);
typedef void(^OSUHTMLAppendContentsBlock)(void (^contents)(void));
typedef void(^OSUHTMLAppendTableInfoRowBlock)(NSString *title, NSString *value);

@interface OSUSystemHTMLReport : NSObject

@property (nonatomic, readonly) OSUHTMLAppendTextBlock str;
@property (nonatomic, readonly) OSUHTMLAppendTextBlock p;
@property (nonatomic, readonly) OSUHTMLAppendContentsBlock table;
@property (nonatomic, readonly) OSUHTMLAppendContentsBlock tr;
@property (nonatomic, readonly) OSUHTMLAppendContentsBlock th_section;
@property (nonatomic, readonly) OSUHTMLAppendContentsBlock th;
@property (nonatomic, readonly) OSUHTMLAppendContentsBlock td;
@property (nonatomic, readonly) OSUHTMLAppendContentsBlock td_right;
@property (nonatomic, readonly) OSUHTMLAppendTableInfoRowBlock infoRow;

@end

@protocol OSUProbeDataFormatter <NSObject>

- (void)formatProbeWithKey:(NSString *)probeKey forReport:(OSUSystemHTMLReport *)report;

@end

@interface OSUSystemConfigurationController : NSWindowController

+ (void)setFormatter:(id<OSUProbeDataFormatter>)formatter forProbeKey:(NSString *)probeKey;

- (void)runModalSheetInWindow:(NSWindow *)window;

@end
