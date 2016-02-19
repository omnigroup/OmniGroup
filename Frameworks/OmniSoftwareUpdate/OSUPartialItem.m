// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUPartialItem.h"

RCS_ID("$Id$")

@interface OSUPartialItem ()

@property (nonatomic) BOOL readingURLString;

@end

@implementation OSUPartialItem

- (instancetype)initWithXMLData:(NSData *)data
{
    if (self = [super init]) {
        self.releaseNotesURLString = @"";
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
        parser.delegate = self;
        [parser parse];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict
{
    if ([elementName containsString:@"releaseNotesLink"]) {
        self.readingURLString = YES;
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    self.readingURLString = NO;
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(nonnull NSString *)string{
    if (self.readingURLString) {
        self.releaseNotesURLString = [self.releaseNotesURLString stringByAppendingString:string];
    }
}

@end
