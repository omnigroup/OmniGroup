// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUPartialItem.h"

@import OmniFoundation;

RCS_ID("$Id$")

@interface OSUPartialItem ()

@property (nonatomic) BOOL readingURLString;
@property (nonatomic) BOOL readingPublishDate;
@end

@implementation OSUPartialItem
static NSString *releaseNotesElement = @"releaseNotesLink";
static NSString *publishDateElement = @"pubDate";

- (instancetype)initWithXMLData:(NSData *)data
{
    self = [super init];
    if (self == nil)
        return nil;

    self.releaseNotesURLString = @"";
    self.publishDateString = @"";
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = self;
    [parser parse];

    if ([NSString isEmptyString:self.publishDateString])
        return nil;

    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict
{
    if ([elementName containsString:releaseNotesElement]) {
        self.readingURLString = YES;
    } else if ([elementName containsString:publishDateElement]) {
        self.readingPublishDate = YES;
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if ([elementName containsString:releaseNotesElement]) {
        self.readingURLString = NO;
    } else if ([elementName containsString:publishDateElement]) {
        self.readingPublishDate = NO;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(nonnull NSString *)string
{
    if (self.readingURLString) {
        self.releaseNotesURLString = [self.releaseNotesURLString stringByAppendingString:string];
    } else if (self.readingPublishDate) {
        self.publishDateString = [self.publishDateString stringByAppendingString:string];
    }
}

@end
