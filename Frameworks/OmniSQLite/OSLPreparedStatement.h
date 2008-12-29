// Copyright 2004-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSData, NSDictionary;
@class OSLDatabaseController;

@interface OSLPreparedStatement : OFObject
{
    NSString *sql;
    void *statement;
    unsigned int bindIndex;
    OSLDatabaseController *databaseController;
}

- initWithSQL:(NSString *)someSQL statement:(void *)preparedStatement databaseController:(OSLDatabaseController *)aDatabaseController;
- (void)reset;
- (NSDictionary *)step;

- (void)bindInt:(int)integer;
- (void)bindString:(NSString *)string;
- (void)bindBlob:(NSData *)data;
- (void)bindLongLongInt:(long long)longLong;
- (void)bindNull;

// Convenience method

- (void)bindPropertyList:(id)propertyList;
    // This archives the XML data from a property list as a database blob

@end

