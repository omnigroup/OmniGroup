// Copyright 2017 The Omni Group. All rights reserved.

#import "NSURL-OUIExtensions.h"

RCS_ID("$Id$");

@implementation NSURL (OUIExtensions)

- (BOOL)isProbablyAppScheme;
{
    static NSSet *schemesThatUIDataDetectorsShouldHandle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // All permanent schemes from http://www.iana.org/assignments/uri-schemes/uri-schemes.xhtml as of 9/30/2016.
        NSArray *schemes = @[
                             @"aaa",
                             @"aaas",
                             @"about",
                             @"acap",
                             @"acct",
                             @"cap",
                             @"cid",
                             @"coap",
                             @"coaps",
                             @"crid",
                             @"data",
                             @"dav",
                             @"dict",
                             @"dns",
                             @"example",
                             @"file",
                             @"ftp",
                             @"geo",
                             @"go",
                             @"gopher",
                             @"h323",
                             @"http",
                             @"https",
                             @"iax",
                             @"icap",
                             @"im",
                             @"imap",
                             @"info",
                             @"ipp",
                             @"ipps",
                             @"iris",
                             @"iris.beep",
                             @"iris.lwz",
                             @"iris.xpc",
                             @"iris.xpcs",
                             @"jabber",
                             @"ldap",
                             @"mailto",
                             @"message",
                             @"mid",
                             @"msrp",
                             @"msrps",
                             @"mtqp",
                             @"mupdate",
                             @"news",
                             @"nfs",
                             @"ni",
                             @"nih",
                             @"nntp",
                             @"opaquelocktoken",
                             @"pkcs11",
                             @"pop",
                             @"pres",
                             @"reload",
                             @"rtsp",
                             @"rtsps",
                             @"rtspu",
                             @"service",
                             @"session",
                             @"shttp",
                             @"sieve",
                             @"sip",
                             @"sips",
                             @"sms",
                             @"snmp",
                             @"soap.beep",
                             @"soap.beeps",
                             @"stun",
                             @"stuns",
                             @"tag",
                             @"tel",
                             @"telnet",
                             @"tftp",
                             @"thismessage",
                             @"tip",
                             @"tn3270",
                             @"turn",
                             @"turns",
                             @"tv",
                             @"urn",
                             @"vemmi",
                             @"vnc",
                             @"ws",
                             @"wss",
                             @"xcon",
                             @"xcon-userid",
                             @"xmlrpc.beep",
                             @"xmlrpc.beeps",
                             @"xmpp",
                             @"z39.50r",
                             @"z39.50s",
                             ];
        schemesThatUIDataDetectorsShouldHandle = [NSSet setWithArray:schemes];
    });
    
    NSString *scheme = self.scheme;
    if ([NSString isEmptyString:scheme]) {
        return NO;
    }
    
    BOOL handledScheme = [schemesThatUIDataDetectorsShouldHandle containsObject:scheme];
    
    // Assume everything else is an app-scheme that we'll link ourselves.
    return !handledScheme;
}

@end
