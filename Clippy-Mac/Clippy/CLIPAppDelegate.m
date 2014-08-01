//
//  CLIPAppDelegate.m
//  Clippy
//
//  Created by Tim Johnsen on 7/31/14.
//  Copyright (c) 2014 tijo. All rights reserved.
//

#import "CLIPAppDelegate.h"
#import "CLIPPasteboardPoller.h"
#import <Dropbox/Dropbox.h>

@interface CLIPAppDelegate () <CLIPPasteboardPollerDelegate, NSMenuDelegate>

@property (nonatomic, strong) CLIPPasteboardPoller *poller;

@property (nonatomic, strong) DBAccountManager *accountManager;
@property (nonatomic, strong) DBFilesystem *filesystem;

@property (nonatomic, strong) IBOutlet NSMenu *statusMenu;
@property (nonatomic, strong) IBOutlet NSStatusItem *statusItem;

@property (nonatomic, strong) IBOutlet NSMenuItem *updateInfoMenuItem;

@property (nonatomic, copy) NSString *lastWrittenFilename;

@property (nonatomic, copy) NSString *lastUpdateSource;
@property (nonatomic, copy) NSDate *lastUpdateDate;

@end

@implementation CLIPAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    self.accountManager = [[DBAccountManager alloc] initWithAppKey:@"<DROPBOX-KEY>" secret:@"<DROPBOX-SECRET>"];
    [DBAccountManager setSharedManager:self.accountManager];
    
    DBAccount *linkedAccount = [[DBAccountManager sharedManager] linkedAccount];
    if (linkedAccount) {
        NSLog(@"App already linked");
        [self setupObserver];
    } else {
        [[DBAccountManager sharedManager] linkFromWindow:self.window withCompletionBlock:^(DBAccount *account) {
            if (account) {
                NSLog(@"App linked successfully!");
                [self setupObserver];
            }
        }];
    }
    
    // Poll pasteboard for changes
    self.poller = [[CLIPPasteboardPoller alloc] init];
    self.poller.delegate = self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    [self.statusItem setMenu:self.statusMenu];
    [self.statusItem setImage:[NSImage imageNamed:@"statusclip"]];
    [self.statusItem setHighlightMode:YES];
    
    [self.updateInfoMenuItem setTitle:@"Idle"];
}

- (void)setupObserver
{
    DBAccount *account = [[DBAccountManager sharedManager] linkedAccount];
    self.filesystem = [[DBFilesystem alloc] initWithAccount:account];
    [DBFilesystem setSharedFilesystem:self.filesystem];
    
    [[DBFilesystem sharedFilesystem] addObserver:self forPathAndChildren:[DBPath root] block:^{
        // Get most recent file info
        DBFileInfo *mostRecentFile = nil;
        for (DBFileInfo *fileInfo in [[DBFilesystem sharedFilesystem] listFolder:[DBPath root] error:nil]) {
            if (!mostRecentFile || [fileInfo.modifiedTime isGreaterThan:mostRecentFile.modifiedTime]) {
                mostRecentFile = fileInfo;
            }
        }
        
        if (mostRecentFile && ![[[mostRecentFile path] name] isEqualToString:self.lastWrittenFilename]) {
            
            NSLog(@"Add");
            
            DBFile *file = [[DBFilesystem sharedFilesystem] openFile:mostRecentFile.path error:nil];
            DBFileStatus *status = file.status;
            if (!status.cached) {
                NSLog(@"Not cached 1");
                [file addObserver:self block:^{
                    if (file.status.cached) {
                        NSLog(@"Cached");
                        DBError *err = nil;
                        [file update:&err];
                        if (err) {
                            NSLog(@"Err %@", err);
                        }
                        
                        NSData *data = [file readData:nil];
                        NSLog(@"%zu", [data length]);
                        
                        if ([data length] > 0) {
                            NSDictionary *pasteboard = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
                            
                            NSString *pasteboardString = [pasteboard objectForKey:@"string"];
                            NSData *pasteboardImageData = [pasteboard objectForKey:@"image"];
                            NSString *pasteboardURL = [pasteboard objectForKey:@"url"];
                            
                            self.poller.suppressChangeEvents = YES;
                            
                            if (pasteboardString || pasteboardImageData || pasteboardURL) {
                                [[NSPasteboard generalPasteboard] clearContents];
                                
                                NSUserNotification *notification = [[NSUserNotification alloc] init];
                                
                                [notification setTitle:@"Clipboard updated remotely"];
                                
                                if (pasteboardImageData) {
                                    NSImage *image = [[NSImage alloc] initWithData:pasteboardImageData];
                                    [notification setContentImage:image];
                                } /*else if (pasteboardString) {
                                    [notification setInformativeText:pasteboardString];
                                }*/
                                
                                [[NSUserNotificationCenter defaultUserNotificationCenter] scheduleNotification:notification];
                            }
                            
                            if (pasteboardString) {
                                [[NSPasteboard generalPasteboard] setString:pasteboardString forType:NSStringPboardType];
                                NSLog(@"Set string");
                            }

                            if (pasteboardImageData) {
                                [[NSPasteboard generalPasteboard] setData:[[[NSImage alloc] initWithData:pasteboardImageData] TIFFRepresentation] forType:NSTIFFPboardType];
                                NSLog(@"Set image");
                            }
                            
                            if (pasteboardURL) {
                                [[NSPasteboard generalPasteboard] setString:pasteboardURL forType:NSURLPboardType];
                                NSLog(@"Set URL");
                            }
                            
                            self.lastUpdateSource = @"remotely";
                            self.lastUpdateDate = [NSDate date];
                            
                            self.poller.suppressChangeEvents = NO;
                            
                            [file removeObserver:self];
                        }
                        
                    } else {
                        NSLog(@"Not cached");
                    }
                }];
            } else {
                NSLog(@"Cached");
            }
            
#if 0
            
            // No access to path real path in FS...
            //            [[NSPasteboard generalPasteboard] writeFileContents:[mostRecentFile.path stringValue]];
            
            DBFile *file = [[DBFilesystem sharedFilesystem] openFile:mostRecentFile.path error:nil];
            
            [file addObserver:self block:^{
                [file update:nil];
//                if (file.status.state == DBFileStateIdle) {
                    NSError *readError = nil;
//                    NSData *data = [file readData:&readError];
                    NSFileHandle *fileHandle = [file readHandle:nil];

                    NSData *data = [fileHandle readDataToEndOfFile];

                    if (readError) {
                        NSLog(@"Read %@", readError);
                    }

                    NSError *loadError = nil;
                    NSDictionary *contents = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&loadError];

                    if (loadError) {
                        NSLog(@"Load %@", loadError);
                    }
                    
                    // TODO: Remove observer
//                }
            }];
            
//            NSError *readError = nil;
//            NSData *data = [file readData:&readError];
//            NSFileHandle *fileHandle = [file readHandle:nil];
            
//            NSData *data = [fileHandle readDataToEndOfFile];
//            
//            if (readError) {
//                NSLog(@"Read %@", readError);
//            }
//            
//            NSError *loadError = nil;
//            NSDictionary *contents = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&loadError];
//            
//            if (loadError) {
//                NSLog(@"Load %@", loadError);
//            }
//            
//            [[NSPasteboard generalPasteboard] clearContents];
//            
//            if ([contents objectForKey:@"string"]) {
//                [[NSPasteboard generalPasteboard] setString:[contents objectForKey:@"string"] forType:NSStringPboardType];
//                NSLog(@"Set string");
//            } else {
//                NSLog(@"Did not set string");
//            }
            
                
//                [[NSPasteboard generalPasteboard] setData:[NSKeyedUnarchiver unarchiveObjectWithData:[file readData:nil]] forType:type];
            
            // Might work?
//            [[NSPasteboard generalPasteboard] writeObjects:@[[file readData:nil]]];
#endif
        }
    }];
}

//- (void)pollPasteboard:(id)sender
//{
//    NSInteger changeCount = [[NSPasteboard generalPasteboard] changeCount];
//    if (self.changeCount != changeCount) {
//        self.changeCount = changeCount;
//
//        NSPasteboardItem *item = [[[NSPasteboard generalPasteboard] pasteboardItems] firstObject];
//
//        // Save to Dropbox
//        // Once done notify with URL of new file...
//    }
//}

- (void)pasteboardDidChange
{
    NSMutableDictionary *encodedPasteboardContents = [[NSMutableDictionary alloc] init];
    
    NSImage *image = [[NSImage alloc] initWithData:[[NSPasteboard generalPasteboard] dataForType:NSTIFFPboardType]];
    NSData *imageData = [[[image representations] firstObject] representationUsingType:NSJPEGFileType properties:@{NSImageCompressionFactor : @(0.5)}];
    [encodedPasteboardContents setValue:[[NSPasteboard generalPasteboard] stringForType:NSStringPboardType] forKey:@"string"];
    [encodedPasteboardContents setValue:imageData forKey:@"image"];
    
//    NSData *imageData = [[NSPasteboard generalPasteboard] dataForType:NSTIFFPboardType];
//    
//    if (imageData) {
//        CGImageRef img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL), 0, NULL);
//        CGFloat scale = 0.0;
//        if (CGImageGetWidth(img) > CGImageGetHeight(img)) {
//            scale = 640.0 / CGImageGetWidth(img);
//        } else {
//            scale = 640.0 / CGImageGetHeight(img);
//        }
//        
//        scale = MIN(scale, 1.0);
//        NSImage *image = [[NSImage alloc] initWithCGImage:img size:NSSizeFromCGSize(CGSizeMake(CGImageGetWidth(img) * scale, CGImageGetHeight(img) * scale))];
//        [[[[image representations] firstObject] representationUsingType:NSJPEGFileType properties:@{NSImageCompressionFactor : @(0.5)}] writeToFile:@"/Users/tim/Desktop/test.jpg" atomically:YES];
//    }
    
    [encodedPasteboardContents setValue:imageData forKeyPath:@"image"];
    [encodedPasteboardContents setValue:[[NSPasteboard generalPasteboard] stringForType:NSURLPboardType] forKey:@"url"];
    
    NSString *filename = [NSString stringWithFormat:@"%f", [NSDate timeIntervalSinceReferenceDate]];
    
    self.lastWrittenFilename = filename;
    
    DBPath *newPath = [[DBPath root] childPath:filename];
    DBFile *file = [[DBFilesystem sharedFilesystem] createFile:newPath error:nil];
    [file writeData:[NSPropertyListSerialization dataFromPropertyList:encodedPasteboardContents format:NSPropertyListBinaryFormat_v1_0 errorDescription:nil] error:nil];
    [file close];
    
    self.lastUpdateSource = @"locally";
    self.lastUpdateDate = [NSDate date];
}

- (void)menuWillOpen:(NSMenu *)menu
{
    [self updateInfoText];
}

- (void)updateInfoText
{
    if (self.lastUpdateDate && self.lastUpdateSource) {
        NSUInteger t = fabs([self.lastUpdateDate timeIntervalSinceNow]);
        NSString *timeString = nil;
        if (t < 60) {
            // seconds
            NSUInteger val = t;
            timeString = [NSString stringWithFormat:@"%zd second%@ ago", t, val != 1 ? @"s" : @""];
        } else if (t < 3600) {
            // minutes
            NSUInteger val = t / 60;
            timeString = [NSString stringWithFormat:@"%zd minute%@ ago", val, val != 1 ? @"s" : @""];
        } else if (t < 86400) {
            // hours
            NSUInteger val = t / 3600;
            timeString = [NSString stringWithFormat:@"%zd hour%@ ago", val, val != 1 ? @"s" : @""];
        } else if (t < 86400 * 7) {
            // days
            NSUInteger val = t / 86400;
            timeString = [NSString stringWithFormat:@"%zd day%@ ago", val, val != 1 ? @"s" : @""];
        } else {
            timeString = @"a long time ago";
        }
        self.updateInfoMenuItem.title = [NSString stringWithFormat:@"Last updated %@ %@", self.lastUpdateSource, timeString];
    } else {
        self.updateInfoMenuItem.title = @"Idle";
    }
}

@end
